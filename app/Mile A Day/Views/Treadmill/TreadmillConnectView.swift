//
//  TreadmillConnectView.swift
//  Mile A Day
//
//  The tracker's "Connect treadmill" chip (indoor workouts only) and the
//  sheet behind it. All Bluetooth lives in `TreadmillLink`; this file only
//  draws its state. Nothing here starts Bluetooth until the user taps —
//  creating the central manager is what raises the permission prompt.
//

import SwiftUI
import UIKit

// MARK: - Speed formatting

enum TreadmillFormat {
    /// "3.0 mph" / "4.8 km/h" — follows the distance unit preference.
    static func speed(kmh: Double) -> String {
        switch DistanceUnits.current {
        case .miles: return String(format: "%.1f mph", kmh / 1.609344)
        case .kilometers: return String(format: "%.1f km/h", kmh)
        }
    }

    /// `figure.run.treadmill` is newer than some iOS 17 symbol sets; fall
    /// back rather than render a blank box.
    static let glyph: String = UIImage(systemName: "figure.run.treadmill") != nil
        ? "figure.run.treadmill"
        : "antenna.radiowaves.left.and.right"
}

// MARK: - Tracker chip

/// "Connect treadmill" before, "Treadmill · 3.0 mph" while connected. Owns
/// its sheet so the tracker's body gains one view, not a modifier chain.
struct TreadmillChip: View {
    private let link = TreadmillLink.shared
    @State private var showSheet = false

    var body: some View {
        Button {
            showSheet = true
        } label: {
            HStack(spacing: 6) {
                if link.isConnected {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: TreadmillFormat.glyph)
                        .madFont(size: 12, weight: .bold)
                        .accessibilityHidden(true)
                }
                Text(label)
                    .madFont(size: 13, weight: .bold, design: .rounded)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.16)))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            TreadmillConnectSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .madTypeCap(.madCardCap)
        }
    }

    private var label: String {
        switch link.phase {
        case .connected:
            if let kmh = link.speedKmh {
                return "Treadmill · \(TreadmillFormat.speed(kmh: kmh))"
            }
            return "Treadmill connected"
        case .connecting:
            return "Connecting…"
        default:
            return "Connect treadmill"
        }
    }
}

// MARK: - Sheet

struct TreadmillConnectSheet: View {
    private let link = TreadmillLink.shared
    @Environment(\.dismiss) private var dismiss
    @State private var scanStartedAt = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Connect a treadmill")
                    .madFont(size: 22, weight: .heavy, design: .rounded)
                    .padding(.top, 24)

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
            if !link.isConnected, !isConnecting {
                scanStartedAt = Date()
                link.startScanning()
            }
        }
        .onDisappear {
            // Leave a live connection alone; stop a scan nobody is watching.
            if !link.isConnected, !isConnecting { link.stopScanning() }
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

    private var isConnecting: Bool {
        if case .connecting = link.phase { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch link.phase {
        case .idle, .scanning:
            scanning
        case .connecting(let name):
            HStack(spacing: 12) {
                ProgressView()
                Text("Connecting to \(name)…")
                    .madFont(size: 16, weight: .semibold)
            }
        case .connected(let name):
            connected(name: name)
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

    private var scanning: some View {
        VStack(alignment: .leading, spacing: 14) {
            step(1, "Start the belt on the treadmill.")
            step(2, "Hold your phone flat on the treadmill's screen. We'll connect to it automatically.")

            HStack(spacing: 10) {
                ProgressView()
                Text("Looking for treadmills…")
                    .madFont(size: 14, weight: .medium)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)

            if !link.nearby.isEmpty {
                Text("Or pick yours")
                    .madFont(size: 13, weight: .bold)
                    .foregroundColor(.secondary)
                    .padding(.top, 6)
                ForEach(link.nearby.prefix(6)) { machine in
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

    private func connected(name: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(Color.green).frame(width: 9, height: 9)
                    .accessibilityHidden(true)
                Text("Connected to \(name)")
                    .madFont(size: 15, weight: .semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HStack(alignment: .firstTextBaseline, spacing: 18) {
                metric(
                    value: link.speedKmh.map { TreadmillFormat.speed(kmh: $0) } ?? "—",
                    caption: "Belt speed"
                )
                metric(value: link.segmentMiles.distanceFormatted, caption: "Counted so far")
            }

            Text("Check the speed matches your treadmill. If it doesn't, it's a neighbour's machine: disconnect and pick another.")
                .madFont(size: 13, weight: .medium)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button {
                    link.disconnect()
                    scanStartedAt = Date()
                    link.startScanning()
                } label: {
                    Text("Disconnect")
                        .madFont(size: 15, weight: .bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)

                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .madFont(size: 15, weight: .bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(MADTheme.Colors.madRed))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func metric(value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .madFont(size: 26, weight: .bold, design: .rounded, monospacedDigit: true)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .madFont(size: 12, weight: .medium)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)")
                .madFont(size: 13, weight: .heavy, design: .rounded)
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(MADTheme.Colors.madRed))
            Text(text)
                .madFont(size: 15, weight: .medium)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                Button(action: action.1) {
                    Text(action.0)
                        .madFont(size: 15, weight: .bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(MADTheme.Colors.madRed))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func proximity(_ rssi: Int) -> String {
        if rssi >= TreadmillLink.onConsoleRSSI { return "Right here" }
        if rssi >= -70 { return "Close by" }
        return "Further away"
    }
}
