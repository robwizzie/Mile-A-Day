//
//  TreadmillConnectView.swift
//  Mile A Day
//
//  The tracker's treadmill row (indoor workouts only) and the sheet behind
//  it. All Bluetooth lives in `TreadmillLink`; this file only draws its
//  state. Nothing here starts Bluetooth until the user taps — creating the
//  central manager is what raises the permission prompt.
//
//  The flow is three steps, shown as such: FIND (hold the phone on the
//  console, a warmer/colder meter), CONFIRM (press speed or GO once, so we
//  know it's YOUR machine and not the neighbour's), COUNTING.
//

import SwiftUI
import UIKit

// MARK: - Formatting

enum TreadmillFormat {
    /// "3.0 mph" / "4.8 km/h" — follows the distance unit preference.
    static func speed(kmh: Double) -> String {
        switch DistanceUnits.current {
        case .miles: return String(format: "%.1f mph", kmh / 1.609344)
        case .kilometers: return String(format: "%.1f km/h", kmh)
        }
    }

    static func incline(_ percent: Double) -> String {
        String(format: "%.1f%%", percent)
    }

    /// `figure.run.treadmill` is newer than some iOS 17 symbol sets; fall
    /// back rather than render a blank box.
    static let glyph: String = UIImage(systemName: "figure.run.treadmill") != nil
        ? "figure.run.treadmill"
        : "antenna.radiowaves.left.and.right"
}

// MARK: - Tracker row

/// Unconnected: a quiet "Connect treadmill" chip (most indoor walks aren't
/// on a treadmill). Mid-handshake: an amber chip that says what to do.
/// Counting: a full-width card with the console's live numbers, so it's
/// obvious where the distance is coming from. Owns its sheet so the
/// tracker's body gains one view, not a modifier chain.
struct TreadmillTrackerRow: View {
    private let link = TreadmillLink.shared
    @State private var showSheet = false

    var body: some View {
        Button {
            showSheet = true
        } label: {
            if link.isConnected {
                connectedCard
            } else {
                chip
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .sheet(isPresented: $showSheet) {
            TreadmillConnectSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .madTypeCap(.madCardCap)
        }
    }

    private var chip: some View {
        HStack(spacing: 6) {
            if link.isBusy || link.lostDuringWorkout {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: TreadmillFormat.glyph)
                    .madFont(size: 12, weight: .bold)
                    .accessibilityHidden(true)
            }
            Text(chipLabel)
                .madFont(size: 13, weight: .bold, design: .rounded)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.white.opacity(0.16)))
    }

    private var chipLabel: String {
        if link.isBusy { return "Finish connecting your treadmill" }
        if link.lostDuringWorkout { return "Treadmill lost · Reconnect" }
        return "Connect treadmill"
    }

    private var connectedCard: some View {
        HStack(spacing: 12) {
            Image(systemName: TreadmillFormat.glyph)
                .madFont(size: 20, weight: .semibold)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(link.isStale ? "Treadmill went quiet" : "Treadmill distance")
                        .madFont(size: 14, weight: .heavy, design: .rounded)
                        .lineLimit(1)
                    if !link.isStale { LiveDot() }
                }
                Text(detail)
                    .madFont(size: 13, weight: .semibold, design: .rounded, monospacedDigit: true)
                    .opacity(0.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .madFont(size: 12, weight: .bold)
                .opacity(0.6)
                .accessibilityHidden(true)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.14))
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the connected treadmill")
    }

    private var detail: String {
        // Say what's counting, not just that something broke.
        if link.isStale { return "Counting with your phone until it's back" }
        var parts: [String] = []
        if let kmh = link.speedKmh { parts.append(TreadmillFormat.speed(kmh: kmh)) }
        if let incline = link.inclinePercent, incline != 0 {
            parts.append("\(TreadmillFormat.incline(incline)) incline")
        }
        return parts.isEmpty ? "Connected" : parts.joined(separator: " · ")
    }
}

/// Small green "LIVE" tag. Static (no pulse), so nothing to gate on
/// Reduce Motion.
private struct LiveDot: View {
    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(Color.green).frame(width: 6, height: 6)
            Text("LIVE")
                .madFont(size: 9, weight: .heavy, design: .rounded)
                .tracking(0.8)
        }
        .foregroundColor(.green)
        .accessibilityLabel("Live")
    }
}

// MARK: - Sheet

struct TreadmillConnectSheet: View {
    private let link = TreadmillLink.shared
    @Environment(\.dismiss) private var dismiss
    @State private var scanStartedAt = Date()
    @State private var showList = false
    /// Set when the proof lands while the sheet is open: celebrate, then
    /// close on its own. Opening the sheet already-connected never does.
    @State private var justConfirmed = false

    private enum Step: Int { case find, confirm, counting }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Connect your treadmill")
                    .madFont(size: 22, weight: .heavy, design: .rounded)
                    .padding(.top, 24)

                stepper

                content

                Text("Mile A Day only reads the treadmill's speed and distance. It never controls the machine.")
                    .madFont(size: 12, weight: .medium)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            if !link.isConnected, !link.isBusy {
                scanStartedAt = Date()
                link.startScanning()
            }
        }
        .onDisappear {
            // Leave a connection alone; stop a scan nobody is watching.
            if !link.isConnected, !link.isBusy { link.stopScanning() }
        }
        .onChange(of: link.isConnected) { _, connected in
            guard connected else { return }
            MADHaptics.success()
            justConfirmed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                if justConfirmed, link.isConnected { dismiss() }
            }
        }
        // Auto-connect to the machine the phone is lying on. Polled rather
        // than observed: the candidate needs a hold time, not just a change.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                if link.phase == .scanning, let id = link.autoPickCandidate() {
                    MADHaptics.action()
                    link.connect(id)
                }
            }
        }
    }

    // MARK: Step indicator

    private var step: Step {
        switch link.phase {
        case .confirming, .unconfirmed: return .confirm
        case .connected: return .counting
        case .connecting: return .confirm
        default: return .find
        }
    }

    private var stepper: some View {
        HStack(spacing: 6) {
            stepPill("Find", .find)
            stepPill("Confirm", .confirm)
            stepPill("Counting", .counting)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue + 1) of 3")
    }

    private func stepPill(_ title: String, _ pill: Step) -> some View {
        let reached = step.rawValue >= pill.rawValue
        return VStack(alignment: .leading, spacing: 5) {
            Capsule()
                .fill(reached ? MADTheme.Colors.madRed : Color.primary.opacity(0.12))
                .frame(height: 4)
            Text(title)
                .madFont(size: 11, weight: .bold, design: .rounded)
                .foregroundColor(reached ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.25), value: reached)
    }

    // MARK: Content per phase

    @ViewBuilder
    private var content: some View {
        switch link.phase {
        case .idle, .scanning:
            find
        case .connecting(let name):
            HStack(spacing: 12) {
                ProgressView()
                Text("Connecting to \(name)…")
                    .madFont(size: 16, weight: .semibold)
                    .lineLimit(2)
            }
        case .confirming(let name):
            confirm(name: name)
        case .unconfirmed(let name):
            unconfirmed(name: name)
        case .connected(let name):
            counting(name: name)
        case .failed(let message):
            notice(
                icon: "exclamationmark.triangle.fill",
                title: message,
                action: ("Try again", {
                    scanStartedAt = Date()
                    link.startScanning()
                })
            )
        case .unauthorized:
            notice(
                icon: "lock.fill",
                title: "Bluetooth access is off for Mile A Day. Turn it on in Settings to connect a treadmill.",
                action: ("Open Settings", {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                })
            )
        case .bluetoothOff:
            notice(
                icon: "antenna.radiowaves.left.and.right.slash",
                title: "Bluetooth is off. Turn it on in Control Center, then come back.",
                action: nil
            )
        }
    }

    // Step 1
    private var find: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hold your phone flat on your treadmill's screen.")
                .madFont(size: 17, weight: .bold)
                .fixedSize(horizontal: false, vertical: true)

            signalMeter

            if !link.nearby.isEmpty {
                DisclosureGroup(isExpanded: $showList) {
                    VStack(spacing: 8) {
                        ForEach(link.nearby.prefix(6)) { machine in
                            machineRow(machine)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Or pick from a list (\(link.nearby.count) nearby)")
                        .madFont(size: 14, weight: .semibold)
                }
                .tint(.primary)
            } else {
                TimelineView(.periodic(from: scanStartedAt, by: 1)) { context in
                    if context.date.timeIntervalSince(scanStartedAt) > 10 {
                        Text("No treadmills found yet. Not every treadmill shares its data over Bluetooth. Your steps still count either way.")
                            .madFont(size: 13, weight: .medium)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// Warmer/colder: fills as the nearest machine's signal climbs to
    /// on-console strength, which is also the auto-connect threshold.
    private var signalMeter: some View {
        let level = link.nearestSignal
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule()
                        .fill(level >= 1 ? Color.green : MADTheme.Colors.madRed)
                        .frame(width: max(10, geo.size.width * level))
                }
            }
            .frame(height: 12)
            .animation(.easeOut(duration: 0.3), value: level)

            HStack(spacing: 8) {
                if level < 1 { ProgressView().controlSize(.small) }
                Text(meterCaption(level))
                    .madFont(size: 13, weight: .semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func meterCaption(_ level: Double) -> String {
        if link.nearby.isEmpty { return "Looking for treadmills…" }
        if level >= 1 { return "Found it. Connecting…" }
        if level >= 0.6 { return "Getting warmer. Keep it right on the screen." }
        return "Bring your phone closer to the console."
    }

    private func machineRow(_ machine: TreadmillLink.Nearby) -> some View {
        Button {
            link.connect(machine.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: TreadmillFormat.glyph)
                    .madFont(size: 16, weight: .semibold)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(machine.name)
                        .madFont(size: 15, weight: .semibold)
                        .lineLimit(1)
                    Text(proximity(machine.rssi))
                        .madFont(size: 12, weight: .medium)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .madFont(size: 12, weight: .bold)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }

    // Step 2
    private func confirm(name: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Press speed ▲ or GO on your treadmill once.")
                .madFont(size: 17, weight: .bold)
                .fixedSize(horizontal: false, vertical: true)
            Text("That's how we know \(name) is yours and not the one next to you.")
                .madFont(size: 14, weight: .medium)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.speedKmh.map { TreadmillFormat.speed(kmh: $0) } ?? "—")
                        .madFont(size: 28, weight: .bold, design: .rounded, monospacedDigit: true)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                    Text("This treadmill's speed right now")
                        .madFont(size: 12, weight: .medium)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
        }
    }

    private func unconfirmed(name: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            notice(
                icon: "questionmark.circle.fill",
                title: "We didn't see \(name) change speed. It may be the treadmill next to you.",
                action: nil
            )
            HStack(spacing: 12) {
                secondaryButton("Try again") { link.rearmConfirmation() }
                if link.hasUntriedNearby {
                    primaryButton("Try the next one") { link.tryNextNearest() }
                }
            }
        }
    }

    // Step 3
    private func counting(name: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .madFont(size: 22, weight: .bold)
                    .foregroundColor(.green)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(justConfirmed ? "It's yours!" : "Connected to \(name)")
                        .madFont(size: 17, weight: .bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("Your mile now counts the treadmill's own distance.")
                        .madFont(size: 13, weight: .medium)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                metric(link.speedKmh.map { TreadmillFormat.speed(kmh: $0) } ?? "—", "Speed")
                metric(link.inclinePercent.map { TreadmillFormat.incline($0) } ?? "—", "Incline")
                metric(link.beltMiles.distanceFormatted, "From the belt")
            }

            HStack(spacing: 12) {
                secondaryButton("Disconnect") {
                    justConfirmed = false
                    link.disconnect()
                    scanStartedAt = Date()
                    link.startScanning()
                }
                primaryButton("Done") { dismiss() }
            }
        }
    }

    // MARK: Pieces

    private func metric(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .madFont(size: 22, weight: .bold, design: .rounded, monospacedDigit: true)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text(caption)
                .madFont(size: 12, weight: .medium)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .madFont(size: 15, weight: .bold)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(MADTheme.Colors.madRed))
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .madFont(size: 15, weight: .bold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private func notice(icon: String, title: String, action: (String, () -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .madFont(size: 16, weight: .bold)
                    .foregroundColor(.orange)
                    .accessibilityHidden(true)
                Text(title)
                    .madFont(size: 15, weight: .medium)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let action {
                primaryButton(action.0, action: action.1)
            }
        }
    }

    private func proximity(_ rssi: Int) -> String {
        if rssi >= TreadmillLink.onConsoleRSSI { return "Right here" }
        if rssi >= -70 { return "Close by" }
        return "Further away"
    }
}

// MARK: - Start wizard step

/// The treadmill step of the start wizard: Indoor → "Connect to the
/// treadmill". Same chrome as every other step (and as buddy setup): the
/// tracker renders the top bar and the glyph-over-question header from
/// `TreadmillWizardCopy`; this is the panel under it.
///
/// One instruction per screen, and a way out on every one:
/// - FIND: hold the phone on the console; it connects by itself.
/// - PRESS GO: starting the belt is also the proof it's YOUR machine, so
///   the step moves on by itself the moment that treadmill's speed changes.
/// - Nothing found in `TreadmillLink.searchTimeout`: say so plainly and
///   offer the normal indoor workout, with the promise that the distance
///   can be fixed at the end (the recap's Treadmill Distance card).
struct TreadmillWizardPanel: View {
    let activityNoun: String
    let onConfirmed: () -> Void
    let onSkip: () -> Void

    private let link = TreadmillLink.shared
    @State private var showList = false
    /// Proof landed while this step was on screen: celebrate, then advance.
    /// Re-entering the step already connected waits for "Continue" instead.
    @State private var advanceScheduled = false

    var body: some View {
        VStack(spacing: 16) {
            content
            if showsSkipLink {
                Button(action: onSkip) {
                    Text("Track with my phone instead")
                        .madFont(size: 15, weight: .semibold, design: .rounded)
                        .foregroundColor(.white.opacity(0.8))
                        .underline()
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundColor(.white)
        .onAppear {
            if !link.isConnected, !link.isBusy {
                link.startScanning()
            }
        }
        .onChange(of: link.isConnected) { _, connected in
            guard connected, !advanceScheduled else { return }
            advanceScheduled = true
            MADHaptics.success()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if link.isConnected { onConfirmed() }
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                link.checkSearchTimeout()
                // No auto-connect behind a "couldn't find it" screen: the
                // user is reading a choice, not waiting.
                if link.phase == .scanning, !link.searchTimedOut,
                   let id = link.autoPickCandidate() {
                    MADHaptics.action()
                    link.connect(id)
                }
            }
        }
    }

    /// The timed-out screen carries its own primary "track with my phone";
    /// a second, underlined copy of it would just be noise.
    private var showsSkipLink: Bool {
        if link.isConnected { return false }
        if case .scanning = link.phase, link.searchTimedOut { return false }
        return true
    }

    @ViewBuilder
    private var content: some View {
        switch link.phase {
        case .idle, .scanning:
            if link.searchTimedOut {
                notFound
            } else {
                find
            }
        case .connecting:
            WizardPanel {
                HStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text("Connecting…")
                        .madFont(size: 16, weight: .semibold, design: .rounded)
                }
            }
        case .confirming:
            liveSpeedPanel(waiting: true)
        case .unconfirmed(let name):
            VStack(spacing: 12) {
                WizardPanel {
                    Text("\(name) didn't change speed, so it may be the one next to you.")
                        .madFont(size: 15, weight: .medium, design: .rounded)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if link.hasUntriedNearby {
                    WizardPrimaryButton(title: "Try the next one") { link.tryNextNearest() }
                }
                quietButton("Try again") { link.rearmConfirmation() }
            }
        case .connected:
            VStack(spacing: 12) {
                liveSpeedPanel(waiting: false)
                if !advanceScheduled {
                    WizardPrimaryButton(title: "Continue", action: onConfirmed)
                }
            }
        case .failed(let message):
            problem(message, action: ("Try again", { link.startScanning() }))
        case .unauthorized:
            problem("Bluetooth is off for Mile A Day, so we can't look for treadmills. You can turn it on in Settings, or track with your phone.",
                    action: ("Open Settings", {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }))
        case .bluetoothOff:
            problem("Bluetooth is turned off. Switch it on in Control Center, or track with your phone.", action: nil)
        }
    }

    private var find: some View {
        VStack(spacing: 12) {
            WizardPanel {
                VStack(alignment: .leading, spacing: 10) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.18))
                            Capsule()
                                .fill(Color.white)
                                .frame(width: max(12, geo.size.width * link.nearestSignal))
                        }
                    }
                    .frame(height: 12)
                    .animation(.easeOut(duration: 0.3), value: link.nearestSignal)

                    HStack(spacing: 8) {
                        if link.nearestSignal < 1 { ProgressView().tint(.white).controlSize(.small) }
                        Text(meterCaption)
                            .madFont(size: 14, weight: .semibold, design: .rounded)
                            .opacity(0.9)
                            .lineLimit(2)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            if !link.nearby.isEmpty {
                nearbyList
            }
        }
    }

    /// Nothing connected after the search window. Plain words: what
    /// happened, what we'll do instead, and that it can be made exact later.
    private var notFound: some View {
        VStack(spacing: 12) {
            WizardPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text("We'll track your \(activityNoun) with your phone's motion sensors instead.")
                        .madFont(size: 15, weight: .bold, design: .rounded)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("It can be a little off on a treadmill. At the end you can type in the distance from the treadmill's screen.")
                        .madFont(size: 14, weight: .medium, design: .rounded)
                        .opacity(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            WizardPrimaryButton(title: "Start a normal indoor \(activityNoun)", action: onSkip)
            quietButton("Keep looking") { link.keepLooking() }
            if !link.nearby.isEmpty {
                nearbyList
            }
        }
    }

    private var nearbyList: some View {
        DisclosureGroup(isExpanded: $showList) {
            VStack(spacing: 8) {
                ForEach(link.nearby.prefix(6)) { machine in
                    Button {
                        link.connect(machine.id)
                    } label: {
                        WizardPanel(prominent: false, cornerRadius: 14, padding: 12) {
                            HStack(spacing: 10) {
                                Text(machine.name)
                                    .madFont(size: 15, weight: .semibold, design: .rounded)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(machine.rssi >= TreadmillLink.onConsoleRSSI ? "Right here"
                                     : machine.rssi >= -70 ? "Close by" : "Further away")
                                    .madFont(size: 12, weight: .medium, design: .rounded)
                                    .opacity(0.75)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
        } label: {
            Text("Or pick from a list (\(link.nearby.count) nearby)")
                .madFont(size: 14, weight: .semibold, design: .rounded)
                .opacity(0.85)
        }
        .tint(.white)
    }

    private var meterCaption: String {
        if link.nearby.isEmpty { return "Looking for treadmills…" }
        let level = link.nearestSignal
        if level >= 1 { return "Found it. Connecting…" }
        if level >= 0.6 { return "Getting warmer. Keep it right on the screen." }
        return "Bring your phone closer to the console."
    }

    private func liveSpeedPanel(waiting: Bool) -> some View {
        WizardPanel {
            HStack(spacing: 14) {
                if waiting {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .madFont(size: 26, weight: .bold)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.speedKmh.map { TreadmillFormat.speed(kmh: $0) } ?? "—")
                        .madFont(size: 30, weight: .bold, design: .rounded, monospacedDigit: true)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(waiting ? "Waiting for the belt to change speed…" : "Belt speed")
                        .madFont(size: 13, weight: .medium, design: .rounded)
                        .opacity(0.8)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func problem(_ message: String, action: (String, () -> Void)?) -> some View {
        VStack(spacing: 12) {
            WizardPanel {
                Text(message)
                    .madFont(size: 15, weight: .medium, design: .rounded)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let action {
                WizardPrimaryButton(title: action.0, action: action.1)
            }
        }
    }

    private func quietButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .madFont(size: 16, weight: .semibold, design: .rounded)
                .frame(maxWidth: .infinity)
                .frame(height: WizardMetrics.controlHeight)
                .background(Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

/// The question above `TreadmillWizardPanel`: one sentence that says what to
/// do right now. Never promises every treadmill: "many", not "all".
enum TreadmillWizardCopy {
    static func title(_ link: TreadmillLink, activityNoun: String) -> String {
        switch link.phase {
        case .idle, .scanning:
            return link.searchTimedOut ? "Couldn't find your treadmill" : "Hold your phone on the treadmill"
        case .confirming: return "Press GO on the treadmill"
        case .unconfirmed: return "Is this your treadmill?"
        case .connected: return "It's yours!"
        case .connecting: return "Found a treadmill"
        case .failed, .unauthorized, .bluetoothOff: return "Couldn't connect"
        }
    }

    static func subtitle(_ link: TreadmillLink, activityNoun: String) -> String {
        switch link.phase {
        case .idle, .scanning:
            return link.searchTimedOut
                ? "Many gym treadmills can connect, but not all of them. That's normal."
                : "Lay it flat on the treadmill's screen. Many gym treadmills can connect, but not all."
        case .confirming: return "Belt already moving? Tap speed ▲ once. That's how we know it's yours."
        case .unconfirmed: return "Press GO or speed ▲ on yours, or try the next one."
        case .connected: return "Your \(activityNoun) will count the treadmill's own distance."
        case .connecting: return "Hang on a second…"
        case .failed, .unauthorized, .bluetoothOff: return "You can still track this \(activityNoun) with your phone."
        }
    }
}
