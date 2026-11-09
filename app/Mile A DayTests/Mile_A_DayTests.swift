//
//  Mile_A_DayTests.swift
//  Mile A DayTests
//
//  Created by Robert Wiscount on 6/7/25.
//

import Foundation
import Testing
@testable import Mile_A_Day

struct Mile_A_DayTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

}

/// Real Treadmill Data (0x2ACD) packets captured from a Life Fitness console
/// (North Pole Engineering FTMS module) at 3.0 mph, 14 s apart.
struct TreadmillDataTests {
    static func bytes(_ hex: String) -> Data {
        let clean = hex.replacingOccurrences(of: " ", with: "")
        var data = Data()
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            data.append(UInt8(clean[index..<next], radix: 16)!)
            index = next
        }
        return data
    }

    static let first = bytes("FE17 E201 0000 B40B 0000 00FF 7F00 0000 0000 C0CB 00FE 00FF 0021 1A06 FF7F 2D00")
    static let second = bytes("FE17 E201 0000 C70B 0000 00FF 7F00 0000 0000 C0CC 00FE 00FF 0021 2806 FF7F 2D00")

    @Test func decodesLifeFitnessPacket() throws {
        let sample = try #require(FTMSTreadmillSample.parse(Self.first))
        #expect(sample.speedKmh == 4.82)
        #expect(sample.totalDistanceMeters == 2996)
        #expect(sample.inclinePercent == 0)
        #expect(sample.totalEnergyKcal == 203)
        #expect(sample.elapsedSeconds == 1562)
    }

    @Test func truncatedPacketIsDropped() {
        #expect(FTMSTreadmillSample.parse(Self.first.prefix(10)) == nil)
    }

    @Test func odometerCountsOnlyAfterConnect() throws {
        let t0 = Date()
        var odometer = TreadmillOdometer()
        let a = try #require(FTMSTreadmillSample.parse(Self.first)?.totalDistanceMeters)
        let b = try #require(FTMSTreadmillSample.parse(Self.second)?.totalDistanceMeters)
        #expect(odometer.ingest(totalMeters: a, at: t0) == 0)
        #expect(odometer.ingest(totalMeters: b, at: t0.addingTimeInterval(14)) == 19)
    }

    @Test func odometerRebasesOnConsoleResetAndDropsJumps() {
        let t0 = Date()
        var odometer = TreadmillOdometer()
        odometer.ingest(totalMeters: 500, at: t0)
        odometer.ingest(totalMeters: 510, at: t0.addingTimeInterval(5))
        // New workout on the console: total back to 0 — never negative.
        #expect(odometer.ingest(totalMeters: 0, at: t0.addingTimeInterval(6)) == 10)
        #expect(odometer.ingest(totalMeters: 4, at: t0.addingTimeInterval(7)) == 14)
        // 2 km in one second is not a belt.
        #expect(odometer.ingest(totalMeters: 2004, at: t0.addingTimeInterval(8)) == 14)
        #expect(odometer.ingest(totalMeters: 2008, at: t0.addingTimeInterval(9)) == 18)
    }

    @Test func ownershipNeedsASpeedChange() {
        var check = TreadmillOwnershipCheck()
        #expect(!check.observe(speedKmh: 4.82)) // baseline
        #expect(!check.observe(speedKmh: 4.82)) // nobody pressed anything
        #expect(check.observe(speedKmh: 4.99))  // one press: +0.1 mph
    }

    @Test func ownershipAcceptsGoFromAStoppedBelt() {
        var check = TreadmillOwnershipCheck()
        #expect(!check.observe(speedKmh: 0))    // baseline: belt stopped
        #expect(check.observe(speedKmh: 0.8))   // GO
    }

    /// The second half of a split "More Data" pair carries no speed. It must
    /// neither set the baseline nor read as a change.
    @Test func ownershipIgnoresReadingsWithoutSpeed() {
        var check = TreadmillOwnershipCheck()
        #expect(!check.observe(speedKmh: nil))
        #expect(!check.observe(speedKmh: 4.82)) // first real speed = baseline
        #expect(!check.observe(speedKmh: nil))
        #expect(!check.observe(speedKmh: 4.82))
    }

    /// Flags 0x0001: "More Data" set, so no speed field; nothing else.
    @Test func moreDataPacketHasNoSpeed() throws {
        let sample = try #require(FTMSTreadmillSample.parse(Self.bytes("0100")))
        #expect(sample.speedKmh == nil)
        #expect(sample.totalDistanceMeters == nil)
    }

    /// A machine that never sends Total Distance: speed × time.
    @Test func odometerIntegratesSpeedWhenNoTotal() {
        let t0 = Date()
        var odometer = TreadmillOdometer()
        odometer.ingest(totalMeters: nil, speedKmh: 3.6, at: t0)          // 1 m/s
        odometer.ingest(totalMeters: nil, speedKmh: 3.6, at: t0.addingTimeInterval(1))
        let after = odometer.ingest(totalMeters: nil, speedKmh: 7.2, at: t0.addingTimeInterval(2))
        #expect(abs(after - 2) < 0.0001)                                  // 1 m + 1 m
        // A 30 s silence is lost data, not belt distance: nothing credited.
        let gap = odometer.ingest(totalMeters: nil, speedKmh: 7.2, at: t0.addingTimeInterval(32))
        #expect(abs(gap - 2) < 0.0001)
        let resumed = odometer.ingest(totalMeters: nil, speedKmh: 7.2, at: t0.addingTimeInterval(33))
        #expect(abs(resumed - 4) < 0.0001)                                // 2 m/s for 1 s
    }

    /// Once a machine sends totals, its speed-only half-packets add nothing.
    @Test func odometerPrefersTotalsOverSpeed() {
        let t0 = Date()
        var odometer = TreadmillOdometer()
        odometer.ingest(totalMeters: 100, speedKmh: 3.6, at: t0)
        odometer.ingest(totalMeters: nil, speedKmh: 3.6, at: t0.addingTimeInterval(0.5))
        let after = odometer.ingest(totalMeters: 101, speedKmh: nil, at: t0.addingTimeInterval(1))
        #expect(after == 1)
    }

    // MARK: Console seed (start where the treadmill is)

    static let machine = UUID()
    /// Noon, so a few minutes back never crosses midnight.
    static var noon: Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
    }

    @Test func seedStartsAtTheConsolesTimeAndDistance() throws {
        let now = Self.noon
        let seed = try #require(TreadmillConsoleSeed.resolve(
            totalMeters: 1609, elapsedSeconds: 900, elapsedReadAt: now.addingTimeInterval(-1),
            machine: Self.machine, mark: nil, now: now))
        #expect(seed.elapsedSeconds == 901)                     // the clock ran on since the read
        #expect(abs(seed.miles - 1609 / 1609.344) < 0.0001)
        #expect(seed.startDate == now.addingTimeInterval(-901))
    }

    @Test func seedNeedsBothNumbersAndAFreshReading() {
        let now = Self.noon
        #expect(TreadmillConsoleSeed.resolve(totalMeters: nil, elapsedSeconds: 900, elapsedReadAt: now,
                                             machine: Self.machine, mark: nil, now: now) == nil)
        #expect(TreadmillConsoleSeed.resolve(totalMeters: 500, elapsedSeconds: nil, elapsedReadAt: now,
                                             machine: Self.machine, mark: nil, now: now) == nil)
        #expect(TreadmillConsoleSeed.resolve(totalMeters: 500, elapsedSeconds: 900,
                                             elapsedReadAt: now.addingTimeInterval(-60),
                                             machine: Self.machine, mark: nil, now: now) == nil)
    }

    @Test func seedRejectsNumbersNoBeltMakes() {
        let now = Self.noon
        // 5 km in 60 s.
        #expect(TreadmillConsoleSeed.resolve(totalMeters: 5000, elapsedSeconds: 60, elapsedReadAt: now,
                                             machine: Self.machine, mark: nil, now: now) == nil)
        // Longer than any session we'd trust.
        #expect(TreadmillConsoleSeed.resolve(totalMeters: 5000, elapsedSeconds: 5 * 3600, elapsedReadAt: now,
                                             machine: Self.machine, mark: nil, now: now) == nil)
    }

    @Test func seedNeverReachesBackPastMidnight() {
        let midnight = Calendar.current.startOfDay(for: Date())
        let now = midnight.addingTimeInterval(120)
        #expect(TreadmillConsoleSeed.resolve(totalMeters: 300, elapsedSeconds: 600, elapsedReadAt: now,
                                             machine: Self.machine, mark: nil, now: now) == nil)
    }

    /// Finish a workout, start another on the same machine without the
    /// console starting over: only what came after the first one counts.
    @Test func seedSubtractsWhereTheLastWorkoutEnded() throws {
        let now = Self.noon
        let mark = TreadmillConsoleMark(machine: Self.machine, totalMeters: 1700, elapsedSeconds: 1200,
                                        at: now.addingTimeInterval(-300))
        let seed = try #require(TreadmillConsoleSeed.resolve(
            totalMeters: 2100, elapsedSeconds: 1500, elapsedReadAt: now,
            machine: Self.machine, mark: mark, now: now))
        #expect(seed.elapsedSeconds == 300)
        #expect(abs(seed.miles - 400 / 1609.344) < 0.0001)
        // Ended exactly there: nothing new to start from.
        #expect(TreadmillConsoleSeed.resolve(totalMeters: 1700, elapsedSeconds: 1200, elapsedReadAt: now,
                                             machine: Self.machine, mark: mark, now: now) == nil)
    }

    @Test func seedIgnoresAMarkFromAnotherMachineOrAReset() throws {
        let now = Self.noon
        let mark = TreadmillConsoleMark(machine: Self.machine, totalMeters: 1700, elapsedSeconds: 1200,
                                        at: now.addingTimeInterval(-300))
        // Another machine.
        let other = try #require(TreadmillConsoleSeed.resolve(
            totalMeters: 2100, elapsedSeconds: 1500, elapsedReadAt: now,
            machine: UUID(), mark: mark, now: now))
        #expect(other.elapsedSeconds == 1500)
        // Same machine, console started a new workout since.
        let reset = try #require(TreadmillConsoleSeed.resolve(
            totalMeters: 200, elapsedSeconds: 150, elapsedReadAt: now,
            machine: Self.machine, mark: mark, now: now))
        #expect(reset.elapsedSeconds == 150)
        #expect(abs(reset.miles - 200 / 1609.344) < 0.0001)
    }

    // MARK: Machine status (ended on the console)

    @Test func statusStopResetAndSafetyKeyEndTheWorkout() {
        #expect(FTMSMachineStatus.endsWorkout(Self.bytes("0201")))  // stopped by the user
        #expect(FTMSMachineStatus.endsWorkout(Self.bytes("01")))    // reset
        #expect(FTMSMachineStatus.endsWorkout(Self.bytes("03")))    // safety key
    }

    @Test func statusPauseAndOthersDoNot() {
        #expect(!FTMSMachineStatus.endsWorkout(Self.bytes("0202"))) // paused, not stopped
        #expect(!FTMSMachineStatus.endsWorkout(Self.bytes("02")))   // no parameter
        #expect(!FTMSMachineStatus.endsWorkout(Self.bytes("04")))   // started / resumed
        #expect(!FTMSMachineStatus.endsWorkout(Self.bytes("05E803"))) // target speed changed
        #expect(!FTMSMachineStatus.endsWorkout(Data()))
    }
}
