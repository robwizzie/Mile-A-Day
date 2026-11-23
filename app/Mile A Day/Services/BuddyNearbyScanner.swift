import CoreBluetooth
import Foundation
import SwiftUI

/// Finds friends physically next to you while buddy setup is open.
///
/// FOREGROUND ONLY, OPT-IN, FRIENDS ONLY. Ambient background proximity was
/// rejected (`BuddyJoinFriendCard`: battery, reliability, a heavy privacy
/// surface); this is the narrow version: only while the setup screen is on
/// screen, only after the user taps "Find friends next to me" once, and it
/// stops the moment the screen closes.
///
/// How it identifies nobody: each phone broadcasts an 8-character random
/// token from the server (`POST /buddy/nearby/token`, 10 minutes, rotating)
/// as its BLE local name under one service UUID, and listens for the same.
/// Heard tokens go to `POST /buddy/nearby/resolve`, which answers ONLY with
/// the caller's friends (presence-gated, blocks respected). A stranger's
/// phone hears random characters that resolve to nothing.
///
/// No location: Bluetooth only, under the existing `NSBluetoothAlwaysUsage
/// Description` (now also naming this use).
@MainActor
final class BuddyNearbyScanner: NSObject, ObservableObject {
    static let shared = BuddyNearbyScanner()

    enum State: Equatable {
        case off
        /// Waiting on the Bluetooth permission prompt / radio.
        case starting
        case scanning
        /// Bluetooth off, denied, or unsupported: says which.
        case unavailable(String)
    }

    @Published private(set) var state: State = .off
    /// Friends heard in the last `forgetAfter` seconds, nearest-heard first.
    @Published private(set) var nearbyFriends: [BuddyCandidate] = []

    /// The user turned this on once; setup then starts it on its own.
    @AppStorage("buddyNearbyEnabledV1") var isEnabled = false

    /// One fixed UUID marks a Mile A Day nearby broadcast.
    static let serviceUUID = CBUUID(string: "8D6F2B1C-4E57-4A3B-9C1E-6A2F0B7D5E91")
    private static let namePrefix = "MAD"
    /// A friend not heard for this long drops off the list.
    private let forgetAfter: TimeInterval = 60

    private var central: CBCentralManager?
    private var peripheral: CBPeripheralManager?
    private var myToken: String?
    private var tokenExpires: Date?
    /// token → last heard.
    private var heard: [String: Date] = [:]
    /// token → the friend it belongs to; a token the server didn't
    /// recognise (a stranger, expired) maps to nil and isn't asked about again.
    private var resolved: [String: BuddyCandidate?] = [:]
    private var ticks = 0
    private var loopTask: Task<Void, Never>?

    private override init() { super.init() }

    /// Start from the user's tap: this is what raises the Bluetooth prompt
    /// the first time, so it's never called without one before `isEnabled`.
    func enableAndStart() {
        isEnabled = true
        start()
    }

    /// Setup opened (or the user tapped). No-op unless enabled.
    func start() {
        guard isEnabled, loopTask == nil else { return }
        state = .starting
        loopTask = Task { [weak self] in
            guard let self else { return }
            guard let issued = await BuddySessionService.shared.nearbyToken() else {
                self.state = .unavailable(String(localized: "Turn on \u{201C}Show when I'm out\u{201D} in Privacy to find friends nearby."))
                self.loopTask = nil
                return
            }
            self.myToken = issued.token
            self.tokenExpires = Date().addingTimeInterval(issued.expiresIn)
            // The managers' delegates fire on the main queue; creating them
            // is what asks for Bluetooth the first time.
            self.central = CBCentralManager(delegate: self, queue: .main)
            self.peripheral = CBPeripheralManager(delegate: self, queue: .main)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { break }
                await self.tick()
            }
        }
    }

    /// Setup closed: stop broadcasting and listening, and retire the token.
    func stop() {
        // Runs every time setup closes; only a scanner that was running has
        // a token to retire.
        let wasRunning = loopTask != nil || myToken != nil
        loopTask?.cancel()
        loopTask = nil
        central?.stopScan()
        peripheral?.stopAdvertising()
        central = nil
        peripheral = nil
        myToken = nil
        heard = [:]
        resolved = [:]
        nearbyFriends = []
        if state != .off { state = .off }
        if wasRunning { Task { await BuddySessionService.shared.clearNearbyToken() } }
    }

    /// Turned off by the user: stop and don't start again on its own.
    func disable() {
        isEnabled = false
        stop()
    }

    // MARK: - Loop

    private func tick() async {
        // Rotate the broadcast before it expires.
        if let expires = tokenExpires, expires.timeIntervalSinceNow < 60,
           let fresh = await BuddySessionService.shared.nearbyToken() {
            myToken = fresh.token
            tokenExpires = Date().addingTimeInterval(fresh.expiresIn)
            advertise()
        }
        let now = Date()
        heard = heard.filter { now.timeIntervalSince($0.value) < forgetAfter }
        // A failed lookup reads like "not a friend": re-ask about tokens that
        // came back unrecognised every ~30s, so a network blip can't hide a
        // friend standing right there for the rest of the screen.
        ticks += 1
        if ticks % 10 == 0 { resolved = resolved.filter { $0.value != nil } }
        let unknown = heard.keys.filter { resolved[$0] == nil }
        if !unknown.isEmpty {
            let matches = await BuddySessionService.shared.resolveNearby(tokens: Array(unknown))
            for token in unknown { resolved[token] = .some(nil) }
            for match in matches { resolved[match.token.lowercased()] = .some(match.candidate) }
        }
        // Everyone whose token was heard recently, most recently heard first.
        var seen = Set<String>()
        nearbyFriends = heard
            .sorted { $0.value > $1.value }
            .compactMap { resolved[$0.key] ?? nil }
            .filter { seen.insert($0.userId).inserted }
    }

    private func advertise() {
        guard let peripheral, peripheral.state == .poweredOn, let myToken else { return }
        peripheral.stopAdvertising()
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
            CBAdvertisementDataLocalNameKey: Self.namePrefix + myToken,
        ])
    }

    private func scan() {
        guard let central, central.state == .poweredOn else { return }
        central.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    private func reflectRadio(_ radio: CBManagerState) {
        switch radio {
        case .poweredOn:
            state = .scanning
        case .unauthorized:
            state = .unavailable(String(localized: "Allow Bluetooth for Mile A Day in Settings to find friends nearby."))
        case .poweredOff:
            state = .unavailable(String(localized: "Turn on Bluetooth to find friends nearby."))
        case .unsupported:
            state = .unavailable(String(localized: "This phone can't look for friends nearby."))
        default:
            break
        }
    }

    fileprivate func heardName(_ name: String) {
        guard name.hasPrefix(Self.namePrefix) else { return }
        let token = String(name.dropFirst(Self.namePrefix.count)).lowercased()
        guard token.count == 8, token != myToken else { return }
        heard[token] = Date()
    }
}

extension BuddyNearbyScanner: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let radio = central.state
        MainActor.assumeIsolated {
            reflectRadio(radio)
            scan()
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String else { return }
        MainActor.assumeIsolated { heardName(name) }
    }
}

extension BuddyNearbyScanner: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        let radio = peripheral.state
        MainActor.assumeIsolated {
            reflectRadio(radio)
            advertise()
        }
    }
}
