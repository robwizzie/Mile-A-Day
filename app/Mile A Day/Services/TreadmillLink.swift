//
//  TreadmillLink.swift
//  Mile A Day
//
//  Reads a gym treadmill's own belt distance over Bluetooth during an INDOOR
//  in-app workout. Gym treadmills (Life Fitness, Precor, Matrix, Technogym…)
//  broadcast the Bluetooth SIG Fitness Machine Service (FTMS, 0x1826); its
//  Treadmill Data characteristic (0x2ACD) streams speed, total distance,
//  elapsed time and more about once a second, no vendor SDK needed.
//
//  READ-ONLY by design: this file never writes the Fitness Machine Control
//  Point (0x2AD9). That characteristic can change a machine's speed and
//  incline, and the person on the belt is a stranger in a public gym.
//
//  Distance contract: the console's total distance is an odometer for ITS
//  workout. Once the machine is PROVEN the user's (below), the tracker starts
//  from the console's own time and distance (`TreadmillConsoleSeed`), so the
//  app and the treadmill read the same; from there the belt's movement
//  (`segmentMiles`, monotonic) counts on top. A console reset (new workout on
//  the machine) rebases instead of going backwards, a glitchy jump is
//  dropped, and a workout ending marks the console (`TreadmillConsoleMark`)
//  so the next one on it never re-credits that ground. The tracker folds it
//  all into the indoor distance via `WorkoutLocationManager`.
//
//  Picking the machine: a gym is a wall of identical `LF…` advertisers. The
//  sheet asks for the phone to be held on the console and auto-connects only
//  to a machine that is clearly the strongest signal (`autoPickCandidate`);
//  everything else is a manual pick from the list, nearest first. Signal
//  strength only NOMINATES a machine: nothing from it counts (not the belt,
//  not the console's earlier distance) until the user presses speed or GO
//  and THAT machine's speed changes
//  (`TreadmillOwnershipCheck`, phase `.confirming`). No change in 20 s →
//  `.unconfirmed`, with "Try the next one" moving down the list.
//

import Foundation
import CoreBluetooth

// MARK: - FTMS Treadmill Data parsing

/// One decoded Treadmill Data (0x2ACD) notification. Every field is optional:
/// the flags word says which are present, and a machine may split a reading
/// across packets ("More Data", bit 0).
struct FTMSTreadmillSample: Equatable {
    var speedKmh: Double?
    var totalDistanceMeters: Int?
    var inclinePercent: Double?
    var elapsedSeconds: Int?
    var totalEnergyKcal: Int?

    /// Decode per the FTMS spec (v1.0, §4.9). Returns nil for a packet too
    /// short for the fields its own flags declare, so a truncated packet is
    /// dropped rather than misread.
    ///
    /// Field order and sizes (little-endian), present when the flag is set:
    ///  bit 0 CLEAR → instantaneous speed  u16, 0.01 km/h
    ///  bit 1  average speed               u16
    ///  bit 2  total distance              u24, metres
    ///  bit 3  inclination s16 (0.1 %) + ramp angle s16
    ///  bit 4  elevation gain +/-          u16 + u16
    ///  bit 5  instantaneous pace          u8
    ///  bit 6  average pace                u8
    ///  bit 7  energy total u16 + per hour u16 + per minute u8
    ///  bit 8  heart rate                  u8
    ///  bit 9  metabolic equivalent        u8
    ///  bit 10 elapsed time                u16, seconds
    ///  bit 11 remaining time              u16
    ///  bit 12 force on belt s16 + power output s16
    static func parse(_ data: Data) -> FTMSTreadmillSample? {
        let bytes = [UInt8](data)
        var i = 0
        func u16() -> Int? {
            guard i + 2 <= bytes.count else { return nil }
            defer { i += 2 }
            return Int(bytes[i]) | Int(bytes[i + 1]) << 8
        }
        func s16() -> Int? {
            guard let raw = u16() else { return nil }
            return raw >= 0x8000 ? raw - 0x10000 : raw
        }
        func u24() -> Int? {
            guard i + 3 <= bytes.count else { return nil }
            defer { i += 3 }
            return Int(bytes[i]) | Int(bytes[i + 1]) << 8 | Int(bytes[i + 2]) << 16
        }
        func skip(_ n: Int) -> Bool {
            guard i + n <= bytes.count else { return false }
            i += n
            return true
        }

        guard let flags = u16() else { return nil }
        func has(_ bit: Int) -> Bool { flags & (1 << bit) != 0 }

        var sample = FTMSTreadmillSample()
        if !has(0) {
            guard let v = u16() else { return nil }
            sample.speedKmh = Double(v) / 100
        }
        if has(1) { guard skip(2) else { return nil } }
        if has(2) {
            guard let v = u24() else { return nil }
            sample.totalDistanceMeters = v
        }
        if has(3) {
            guard let incline = s16(), skip(2) else { return nil }
            // 0x7FFF = "not available".
            if incline != 0x7FFF { sample.inclinePercent = Double(incline) / 10 }
        }
        if has(4) { guard skip(4) else { return nil } }
        if has(5) { guard skip(1) else { return nil } }
        if has(6) { guard skip(1) else { return nil } }
        if has(7) {
            guard let total = u16(), skip(3) else { return nil }
            if total != 0xFFFF { sample.totalEnergyKcal = total }
        }
        if has(8) { guard skip(1) else { return nil } }
        if has(9) { guard skip(1) else { return nil } }
        if has(10) {
            guard let v = u16() else { return nil }
            sample.elapsedSeconds = v
        }
        if has(11) { guard skip(2) else { return nil } }
        if has(12) { guard skip(4) else { return nil } }
        return sample
    }
}

/// Turns a stream of Treadmill Data readings into "metres the belt moved
/// since counting started". Pure, so every rule is testable.
///
/// Two sources, never mixed within one segment:
/// - TOTAL DISTANCE (preferred): the console's own odometer, as deltas.
///   Once a machine has sent it, readings without it (the other half of a
///   split "More Data" pair) add nothing.
/// - SPEED × TIME: for machines that never send a total (the field is
///   optional in FTMS). Each reading credits the previous speed over the
///   time since the previous reading; gaps longer than `maxIntegrationGap`
///   credit nothing (the data stopped, not the belt — the tracker falls
///   back to the pedometer then).
struct TreadmillOdometer: Equatable {
    private(set) var segmentMeters: Double = 0
    private var lastTotal: Int?
    private var lastTotalAt: Date?
    private var lastReadingAt: Date?
    private var lastSpeedKmh: Double?
    private var sawTotal = false

    /// Belt speed no runner reaches (~32 km/h) plus slack for a late packet.
    static let maxMetersPerSecond: Double = 9
    /// Longest silence speed integration bridges.
    static let maxIntegrationGap: TimeInterval = 5

    /// Feed one reading (either field may be absent); returns the
    /// (monotonic) segment.
    @discardableResult
    mutating func ingest(totalMeters: Int?, speedKmh: Double?, at now: Date) -> Double {
        defer {
            lastReadingAt = now
            if let speedKmh { lastSpeedKmh = speedKmh }
        }
        if let totalMeters {
            sawTotal = true
            return ingestTotal(totalMeters, at: now)
        }
        guard !sawTotal,
              let previousAt = lastReadingAt,
              let kmh = lastSpeedKmh ?? speedKmh, kmh > 0 else { return segmentMeters }
        let seconds = now.timeIntervalSince(previousAt)
        guard seconds > 0, seconds <= Self.maxIntegrationGap else { return segmentMeters }
        let metersPerSecond = min(kmh / 3.6, Self.maxMetersPerSecond)
        segmentMeters += metersPerSecond * seconds
        return segmentMeters
    }

    /// Total-only convenience (tests, and machines that always send it).
    @discardableResult
    mutating func ingest(totalMeters: Int, at now: Date) -> Double {
        ingest(totalMeters: totalMeters, speedKmh: nil, at: now)
    }

    private mutating func ingestTotal(_ totalMeters: Int, at now: Date) -> Double {
        defer {
            lastTotal = totalMeters
            lastTotalAt = now
        }
        guard let previous = lastTotal, let previousAt = lastTotalAt else {
            // First reading is the baseline: the console's earlier distance
            // belongs to whatever happened before we connected.
            return segmentMeters
        }
        let delta = totalMeters - previous
        if delta <= 0 {
            // Equal: belt stopped. Negative: the console started a new
            // workout and zeroed its total — rebase on the new figure.
            return segmentMeters
        }
        let seconds = max(1, now.timeIntervalSince(previousAt))
        if Double(delta) > Self.maxMetersPerSecond * seconds + 5 {
            // A jump no belt makes (bit error, a different machine's
            // numbers after a reconnect). Drop it and rebase.
            return segmentMeters
        }
        segmentMeters += Double(delta)
        return segmentMeters
    }
}

/// Proof the connected machine is the user's own: the user presses speed
/// up/down (or GO) once, and the belt speed THIS machine reports changes.
/// A neighbour's treadmill changing speed in that same window is the only
/// way to fool it. Pure, so the rule is testable.
struct TreadmillOwnershipCheck: Equatable {
    /// One press on a Life Fitness console is 0.1 mph = 0.16 km/h.
    static let minimumChangeKmh = 0.15
    private var baselineKmh: Double?

    /// Feed each reading's speed; true once it moved from the first one.
    /// A reading WITHOUT speed (the second half of a split "More Data"
    /// pair) says nothing — reading it as 0 would fake a change.
    mutating func observe(speedKmh: Double?) -> Bool {
        guard let speed = speedKmh else { return false }
        guard let baselineKmh else {
            self.baselineKmh = speed
            return false
        }
        return abs(speed - baselineKmh) >= Self.minimumChangeKmh
    }
}

/// Where a machine's console stood when a workout on it ended. The next
/// workout on the SAME machine, while the console hasn't started a new
/// workout of its own, starts from here instead of from the console's zero,
/// so finishing and starting again never credits the same ground twice.
struct TreadmillConsoleMark: Codable, Equatable {
    var machine: UUID
    var totalMeters: Int
    var elapsedSeconds: Int
    var at: Date
}

/// The workout's starting point, read off a PROVEN machine's console: how
/// long the console's own workout has been running and how far its belt has
/// gone. The tracker starts its clock and distance there, so the app and the
/// treadmill read the same and nothing walked before connecting is lost.
/// Pure, so every rule is testable.
///
/// Nil (count from zero, as before) when the console can't give both
/// numbers, the reading is stale, the numbers aren't a belt's, or the
/// console's workout began before today's midnight (a day's mile can't hold
/// yesterday's ground).
struct TreadmillConsoleSeed: Equatable {
    /// Console seconds credited to this workout: the start moves back by this.
    var elapsedSeconds: TimeInterval
    /// Console distance credited to this workout.
    var miles: Double
    var startDate: Date

    /// Longer than any console session we'd trust as one workout.
    static let maxElapsed: TimeInterval = 4 * 60 * 60
    /// A mark older than this is from some other day at the gym.
    static let markLifetime: TimeInterval = 6 * 60 * 60

    static func resolve(
        totalMeters: Int?,
        elapsedSeconds: Int?,
        elapsedReadAt: Date?,
        machine: UUID,
        mark: TreadmillConsoleMark?,
        now: Date,
        calendar: Calendar = .current
    ) -> TreadmillConsoleSeed? {
        guard let totalMeters, let elapsedSeconds, let elapsedReadAt else { return nil }
        let age = now.timeIntervalSince(elapsedReadAt)
        guard age >= 0, age <= TreadmillLink.staleAfter else { return nil }

        var meters = totalMeters
        var seconds = elapsedSeconds
        // Same machine, console still on the workout the last one ended on
        // (neither number went backwards): only what came after counts.
        if let mark, mark.machine == machine,
           now.timeIntervalSince(mark.at) < markLifetime,
           totalMeters >= mark.totalMeters, elapsedSeconds >= mark.elapsedSeconds {
            meters -= mark.totalMeters
            seconds -= mark.elapsedSeconds
        }
        guard seconds > 0, meters >= 0 else { return nil }
        // Same ceiling the odometer uses for a belt.
        guard Double(meters) <= TreadmillOdometer.maxMetersPerSecond * Double(seconds) + 5 else { return nil }
        // The console's clock kept running since that reading.
        let elapsed = Double(seconds) + age
        guard elapsed <= maxElapsed else { return nil }
        let start = now.addingTimeInterval(-elapsed)
        guard start >= calendar.startOfDay(for: now) else { return nil }
        return TreadmillConsoleSeed(
            elapsedSeconds: elapsed,
            miles: Double(meters) / 1609.344,
            startDate: start
        )
    }
}

// MARK: - Connection

@Observable
final class TreadmillLink: NSObject {
    static let shared = TreadmillLink()

    static let fitnessMachineService = CBUUID(string: "1826")
    static let treadmillDataCharacteristic = CBUUID(string: "2ACD")

    enum Phase: Equatable {
        case idle
        /// Bluetooth permission refused (or restricted) — Settings only.
        case unauthorized
        /// Radio off or unsupported.
        case bluetoothOff
        case scanning
        case connecting(name: String)
        /// Connected, waiting for the user's speed press to prove it's theirs.
        /// No belt distance counts yet.
        case confirming(name: String)
        /// No speed change seen in `confirmWindow`: likely a neighbour's.
        /// Still connected so "Try again" doesn't reconnect.
        case unconfirmed(name: String)
        /// Proven and counting.
        case connected(name: String)
        /// The machine dropped or never answered; scanning restarts on retry.
        case failed(String)
    }

    struct Nearby: Identifiable, Equatable {
        let id: UUID
        var name: String
        var rssi: Int
        var lastSeen: Date
    }

    private(set) var phase: Phase = .idle
    /// Nearest first. Only FTMS advertisers that say they're treadmills (or
    /// don't say what they are).
    private(set) var nearby: [Nearby] = []
    /// Live console numbers while connected.
    private(set) var speedKmh: Double?
    private(set) var inclinePercent: Double?
    /// Belt distance since counting started (current stretch), miles.
    private(set) var segmentMiles: Double = 0
    /// Belt distance from earlier stretches of THIS workout (before the data
    /// went quiet and came back). Display only: the tracker owns the total.
    private(set) var bankedMiles: Double = 0
    /// The console's own distance this workout started from
    /// (`TreadmillConsoleSeed`). Display only, like `bankedMiles`.
    private(set) var seededMiles: Double = 0
    /// Belt miles this workout, for the sheet's "From the belt".
    var beltMiles: Double { seededMiles + bankedMiles + segmentMiles }
    /// Counting, but no reading for `staleAfter`: the tracker is on the
    /// pedometer until data comes back.
    private(set) var isStale = false
    /// The machine went away mid-workout; offer to reconnect.
    private(set) var lostDuringWorkout = false
    /// Scanned for `searchTimeout` without connecting to anything.
    private(set) var searchTimedOut = false

    var isConnected: Bool {
        if case .connected = phase { return true }
        return false
    }

    /// Mid-handshake: connecting, or connected but not yet proven.
    var isBusy: Bool {
        switch phase {
        case .connecting, .confirming, .unconfirmed: return true
        default: return false
        }
    }

    /// 0…1 "getting warmer" for the nearest machine: −90 dBm (across the
    /// room) to the on-console strength.
    var nearestSignal: Double {
        guard let rssi = nearby.first?.rssi else { return 0 }
        let low = -90.0, high = Double(Self.onConsoleRSSI)
        return min(1, max(0, (Double(rssi) - low) / (high - low)))
    }

    /// Whether another not-yet-tried machine is in the list.
    var hasUntriedNearby: Bool {
        nearby.contains { !tried.contains($0.id) }
    }

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var active: CBPeripheral?
    @ObservationIgnored private var odometer = TreadmillOdometer()
    @ObservationIgnored private var wantsScan = false
    @ObservationIgnored private var connectTimeout: DispatchWorkItem?
    /// Candidate that has been the clear nearest since this time.
    @ObservationIgnored private var autoPickSince: (id: UUID, at: Date)?
    @ObservationIgnored private var ownership = TreadmillOwnershipCheck()
    @ObservationIgnored private var confirmTimeout: DispatchWorkItem?
    /// Machines tried this sheet session, so "Try the next one" moves on.
    @ObservationIgnored private var tried: Set<UUID> = []
    @ObservationIgnored private var lastSampleAt: Date?
    @ObservationIgnored private var staleTimer: Timer?
    @ObservationIgnored private var scanStartedAt: Date?
    /// The console's latest own numbers (its workout, not ours), each with
    /// when it arrived: a split "More Data" pair can carry them separately.
    @ObservationIgnored private var consoleTotal: (meters: Int, at: Date)?
    @ObservationIgnored private var consoleElapsed: (seconds: Int, at: Date)?

    private static let consoleMarkKey = "MAD_TreadmillConsoleMarkV1"

    /// No reading for this long while counting = stale.
    static let staleAfter: TimeInterval = 10
    /// How long the wizard looks before offering a normal indoor walk.
    static let searchTimeout: TimeInterval = 20

    /// How far a mid-workout console's clock may run ahead of the workout's
    /// and still count as the same session (connect + press take a while).
    static let consoleClockSlack: TimeInterval = 30

    /// How long the user has to press a speed button.
    static let confirmWindow: TimeInterval = 20

    /// RSSI a phone lying ON the console reaches; neighbours sit well below.
    static let onConsoleRSSI = -55
    /// How far ahead of the runner-up the nearest must be to auto-connect.
    static let autoPickLeadDB = 10
    /// …and for how long, so one lucky packet doesn't pick a neighbour.
    static let autoPickHold: TimeInterval = 1.5

    // MARK: Public API (main thread)

    /// Start looking. Creating the central manager is what raises the
    /// Bluetooth permission prompt, so it only happens on the user's tap.
    func startScanning() {
        wantsScan = true
        searchTimedOut = false
        scanStartedAt = Date()
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
            return // scanning starts in centralManagerDidUpdateState
        }
        beginScanIfReady()
    }

    func stopScanning() {
        wantsScan = false
        central?.stopScan()
        autoPickSince = nil
        if phase == .scanning { phase = .idle }
    }

    func connect(_ id: UUID) {
        guard let central, let peripheral = peripherals[id] else { return }
        searchTimedOut = false
        lostDuringWorkout = false
        central.stopScan()
        wantsScan = false
        if let current = active, current.identifier != id {
            central.cancelPeripheralConnection(current)
        }
        active = peripheral
        tried.insert(id)
        confirmTimeout?.cancel()
        peripheral.delegate = self
        phase = .connecting(name: Self.displayName(peripheral.name))
        central.connect(peripheral)

        connectTimeout?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, case .connecting = self.phase else { return }
            self.central?.cancelPeripheralConnection(peripheral)
            self.active = nil
            self.phase = .failed("That treadmill didn't answer. It may already be connected to another phone.")
        }
        connectTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
    }

    /// Drop the machine (user tap, or the workout ended). Distance already
    /// credited stays credited — the tracker's distance only ratchets.
    func disconnect() {
        connectTimeout?.cancel()
        confirmTimeout?.cancel()
        tried = []
        wantsScan = false
        central?.stopScan()
        if let active { central?.cancelPeripheralConnection(active) }
        active = nil
        // A user's mid-workout Disconnect: the pedometer takes over from the
        // distance already counted. (At workout end the tracker has already
        // closed its segment, so this is a no-op then.)
        WorkoutLocationManager.shared.endTreadmillSegment()
        stopStaleWatch()
        resetLiveNumbers()
        bankedMiles = 0
        seededMiles = 0
        lostDuringWorkout = false
        searchTimedOut = false
        nearby = []
        autoPickSince = nil
        phase = .idle
    }

    /// Called by the wizard's poll loop: after `searchTimeout` of scanning
    /// with nothing connected, stop auto-connecting and offer a normal
    /// indoor walk instead.
    func checkSearchTimeout(now: Date = Date()) {
        guard phase == .scanning, !searchTimedOut,
              let scanStartedAt, now.timeIntervalSince(scanStartedAt) >= Self.searchTimeout
        else { return }
        searchTimedOut = true
    }

    /// "Keep looking" after a timeout.
    func keepLooking() {
        searchTimedOut = false
        scanStartedAt = Date()
        if phase != .scanning { startScanning() }
    }

    /// Where the proven machine's console stands right now, for the tracker
    /// to start from (`TreadmillConsoleSeed`). Nil unless a machine is
    /// proven, live (not stale) and sent both its distance and its time.
    func consoleSeed(now: Date = Date()) -> TreadmillConsoleSeed? {
        guard isConnected, !isStale, let active else { return nil }
        return TreadmillConsoleSeed.resolve(
            totalMeters: consoleTotal?.meters,
            elapsedSeconds: consoleElapsed?.seconds,
            elapsedReadAt: consoleElapsed?.at,
            machine: active.identifier,
            mark: Self.loadConsoleMark(),
            now: now
        )
    }

    /// The indoor workout just started tracking. A machine proven in the
    /// start wizard (before there was a workout to feed) counts from here:
    /// from the console's own distance when the tracker took `seed` (its
    /// clock already starts at `seed.startDate`), else from zero.
    func workoutDidStart(seed: TreadmillConsoleSeed? = nil) {
        guard isConnected else { return }
        primeOdometer()
        segmentMiles = 0
        bankedMiles = 0
        seededMiles = seed?.miles ?? 0
        isStale = false
        WorkoutLocationManager.shared.beginTreadmillSegment(consoleMiles: seed?.miles)
    }

    /// The workout using this machine is ending: remember where its console
    /// stands, so a next workout on it doesn't re-credit the same ground.
    func workoutDidEnd() {
        guard isConnected, let active, let total = consoleTotal, let elapsed = consoleElapsed else { return }
        let mark = TreadmillConsoleMark(
            machine: active.identifier,
            totalMeters: total.meters,
            elapsedSeconds: elapsed.seconds,
            at: Date()
        )
        if let data = try? JSONEncoder().encode(mark) {
            UserDefaults.standard.set(data, forKey: Self.consoleMarkKey)
        }
    }

    private static func loadConsoleMark() -> TreadmillConsoleMark? {
        guard let data = UserDefaults.standard.data(forKey: consoleMarkKey) else { return nil }
        return try? JSONDecoder().decode(TreadmillConsoleMark.self, from: data)
    }

    /// A fresh odometer whose baseline is the console's latest total, so the
    /// belt's very next metre counts (an unprimed one waits a reading).
    private func primeOdometer() {
        odometer = TreadmillOdometer()
        if let consoleTotal {
            odometer.ingest(totalMeters: consoleTotal.meters, speedKmh: nil, at: consoleTotal.at)
        }
    }

    /// Start the speed-press check over on the machine already connected.
    func rearmConfirmation() {
        guard let active else { return }
        armConfirmation(name: Self.displayName(active.name))
    }

    /// The machine didn't respond to the user's press: drop it and connect
    /// to the next-nearest one not tried yet. Back to scanning if none.
    func tryNextNearest() {
        confirmTimeout?.cancel()
        if let active { central?.cancelPeripheralConnection(active) }
        active = nil
        resetLiveNumbers()
        if let next = nearby.first(where: { !tried.contains($0.id) }) {
            connect(next.id)
        } else {
            tried = []
            phase = .idle
            startScanning()
        }
    }

    /// The nearest machine, when it is unmistakably the one the phone is
    /// lying on: on-console strength, a clear lead over every other machine,
    /// held for `autoPickHold`. Nil means "let the user choose".
    func autoPickCandidate(now: Date = Date()) -> UUID? {
        guard let first = nearby.first, first.rssi >= Self.onConsoleRSSI else { return nil }
        if nearby.count > 1, first.rssi - nearby[1].rssi < Self.autoPickLeadDB { return nil }
        guard let since = autoPickSince, since.id == first.id,
              now.timeIntervalSince(since.at) >= Self.autoPickHold else { return nil }
        return first.id
    }

    /// "LF0c7a5addf5bda206" → "Treadmill ·DA206"-style label: the raw names
    /// are serial-ish and identical up front, so the tail is what tells two
    /// apart if the user compares with a neighbour.
    static func displayName(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "Treadmill" }
        if raw.count > 10 { return "Treadmill \(raw.suffix(5).uppercased())" }
        return raw
    }

    // MARK: Private

    private func beginScanIfReady() {
        guard wantsScan, let central, central.state == .poweredOn else { return }
        phase = .scanning
        nearby = []
        autoPickSince = nil
        // Duplicates on: RSSI keeps updating, which is how "hold it on the
        // console" works at all.
        central.scanForPeripherals(
            withServices: [Self.fitnessMachineService],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    private func armConfirmation(name: String) {
        ownership = TreadmillOwnershipCheck()
        phase = .confirming(name: name)
        confirmTimeout?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, case .confirming(let name) = self.phase else { return }
            self.phase = .unconfirmed(name: name)
        }
        confirmTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.confirmWindow, execute: work)
    }

    private func confirmOwnership(name: String) {
        confirmTimeout?.cancel()
        // The belt counts from here, on a fresh odometer. Proven in the start
        // wizard (no workout yet), `workoutDidStart` takes it from there.
        primeOdometer()
        segmentMiles = 0
        phase = .connected(name: name)
        let tracker = WorkoutLocationManager.shared
        // Proven mid-workout: the console's distance counts too, but only
        // when its whole session fits inside this workout's clock. Then all
        // of it is this workout's ground and the pace stays true; a console
        // that has been going longer (started before the workout, or kept
        // running through a pause) falls back to counting from here.
        var consoleMiles: Double?
        if tracker.acceptsTreadmill, let seed = consoleSeed(),
           seed.elapsedSeconds <= tracker.workoutElapsedSeconds + Self.consoleClockSlack {
            consoleMiles = seed.miles
            // The console's figure already covers the earlier stretches.
            seededMiles = seed.miles
            bankedMiles = 0
        }
        tracker.beginTreadmillSegment(consoleMiles: consoleMiles)
        startStaleWatch()
    }

    /// Every 2 s while counting: no reading for `staleAfter` → hand the
    /// distance to the pedometer (`endTreadmillSegment`) until data returns.
    /// Rides a RunLoop timer, which keeps firing while the indoor workout's
    /// location keep-alive holds the process up.
    private func startStaleWatch() {
        staleTimer?.invalidate()
        lastSampleAt = Date()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, self.isConnected, !self.isStale,
                  let last = self.lastSampleAt,
                  Date().timeIntervalSince(last) > Self.staleAfter else { return }
            self.goStale()
        }
        RunLoop.main.add(timer, forMode: .common)
        staleTimer = timer
    }

    private func stopStaleWatch() {
        staleTimer?.invalidate()
        staleTimer = nil
        isStale = false
    }

    private func goStale() {
        isStale = true
        bankedMiles += segmentMiles
        segmentMiles = 0
        WorkoutLocationManager.shared.endTreadmillSegment()
    }

    /// Data came back after going stale: a fresh stretch, counted on top of
    /// whatever the pedometer credited meanwhile.
    private func resumeFromStale() {
        isStale = false
        odometer = TreadmillOdometer()
        segmentMiles = 0
        WorkoutLocationManager.shared.beginTreadmillSegment()
    }

    private func resetLiveNumbers() {
        speedKmh = nil
        inclinePercent = nil
        segmentMiles = 0
        odometer = TreadmillOdometer()
        lastSampleAt = nil
        consoleTotal = nil
        consoleElapsed = nil
    }

    private func noteAdvertisement(_ peripheral: CBPeripheral, advertisement: [String: Any], rssi: Int) {
        // 127 = RSSI unavailable.
        guard rssi < 0, rssi > -105 else { return }
        if let serviceData = advertisement[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
           let ftms = serviceData[Self.fitnessMachineService], ftms.count >= 3 {
            // Byte 0 flags, bytes 1-2 machine type; bit 0 = treadmill.
            let type = Int(ftms[ftms.startIndex + 1]) | Int(ftms[ftms.startIndex + 2]) << 8
            guard type == 0 || type & 0x0001 != 0 else { return }
        }
        peripherals[peripheral.identifier] = peripheral
        let now = Date()
        let name = (advertisement[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        if let index = nearby.firstIndex(where: { $0.id == peripheral.identifier }) {
            // Smooth: RSSI from one packet swings ±6 dB.
            nearby[index].rssi = (nearby[index].rssi * 2 + rssi) / 3
            nearby[index].lastSeen = now
            if let name { nearby[index].name = Self.displayName(name) }
        } else {
            nearby.append(Nearby(id: peripheral.identifier, name: Self.displayName(name), rssi: rssi, lastSeen: now))
        }
        nearby.removeAll { now.timeIntervalSince($0.lastSeen) > 8 }
        nearby.sort { $0.rssi > $1.rssi }

        if let first = nearby.first, first.rssi >= Self.onConsoleRSSI {
            if autoPickSince?.id != first.id { autoPickSince = (first.id, now) }
        } else {
            autoPickSince = nil
        }
    }

    private func ingest(_ sample: FTMSTreadmillSample) {
        lastSampleAt = Date()
        // A split "More Data" reading omits speed (and maybe incline): keep
        // showing the last known values rather than blanking them.
        if let speed = sample.speedKmh { speedKmh = speed }
        if let incline = sample.inclinePercent { inclinePercent = incline }
        if let meters = sample.totalDistanceMeters { consoleTotal = (meters: meters, at: Date()) }
        if let seconds = sample.elapsedSeconds { consoleElapsed = (seconds: seconds, at: Date()) }
        switch phase {
        case .confirming(let name):
            guard ownership.observe(speedKmh: sample.speedKmh) else { return }
            confirmOwnership(name: name)
            // Fall through so this reading becomes the odometer's baseline.
        case .connected:
            if isStale { resumeFromStale() }
        default:
            return
        }
        let meters = odometer.ingest(
            totalMeters: sample.totalDistanceMeters,
            speedKmh: sample.speedKmh,
            at: Date()
        )
        let miles = meters / 1609.344
        guard miles > segmentMiles else { return }
        segmentMiles = miles
        WorkoutLocationManager.shared.ingestTreadmillDistance(miles)
    }

    private func connectionLost(_ message: String?) {
        connectTimeout?.cancel()
        confirmTimeout?.cancel()
        if isConnected, WorkoutLocationManager.shared.acceptsTreadmill {
            // Mid-workout: the pedometer carries on from here.
            lostDuringWorkout = true
            bankedMiles += segmentMiles
            WorkoutLocationManager.shared.endTreadmillSegment()
        }
        stopStaleWatch()
        active = nil
        resetLiveNumbers()
        if let message {
            phase = .failed(message)
        } else {
            phase = .idle
        }
    }
}

// MARK: - CoreBluetooth delegates (main queue)

extension TreadmillLink: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if case .bluetoothOff = phase { phase = .idle }
            beginScanIfReady()
        case .unauthorized:
            phase = .unauthorized
        case .poweredOff, .unsupported:
            if active != nil { connectionLost(nil) }
            phase = .bluetoothOff
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard phase == .scanning else { return }
        noteAdvertisement(peripheral, advertisement: advertisementData, rssi: RSSI.intValue)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral.identifier == active?.identifier else { return }
        peripheral.discoverServices([Self.fitnessMachineService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == active?.identifier else { return }
        connectionLost("Couldn't connect to that treadmill. Try again, or pick another.")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == active?.identifier else { return }
        // A disconnect we asked for clears `active` first, so landing here
        // means the machine went away (powered down, walked out of range).
        connectionLost("Lost the treadmill. Your distance so far is kept.")
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.fitnessMachineService }) else {
            central?.cancelPeripheralConnection(peripheral)
            connectionLost("That machine doesn't share treadmill data.")
            return
        }
        peripheral.discoverCharacteristics([Self.treadmillDataCharacteristic], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.treadmillDataCharacteristic }) else {
            central?.cancelPeripheralConnection(peripheral)
            connectionLost("That machine doesn't share treadmill data.")
            return
        }
        peripheral.setNotifyValue(true, for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.treadmillDataCharacteristic else { return }
        guard error == nil, characteristic.isNotifying else {
            central?.cancelPeripheralConnection(peripheral)
            connectionLost("The treadmill wouldn't send its data. Try again.")
            return
        }
        connectTimeout?.cancel()
        resetLiveNumbers()
        armConfirmation(name: Self.displayName(peripheral.name))
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.treadmillDataCharacteristic,
              error == nil, let data = characteristic.value,
              let sample = FTMSTreadmillSample.parse(data) else { return }
        ingest(sample)
    }
}
