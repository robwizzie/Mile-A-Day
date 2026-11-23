//
//  BuddyWalkLiveActivity.swift
//
//  BYTE-IDENTICAL in `Mile A Day/Widgets/` and `MileADayWidgets/` (cp + cmp):
//  the app starts and updates the activity, the extension draws it, and both
//  must agree on the attributes' shape.
//

import ActivityKit
import SwiftUI
import WidgetKit

/// A buddy walk's lock-screen card: "Waiting for Rob to start" → the shared
/// countdown → "It's started — tap to start recording".
///
/// The guest who taps Ready and pockets the phone is exactly the person whose
/// phone used to record nothing: the hand-off into tracking only happens with
/// the app on screen. This card is on the lock screen from the lobby, and the
/// SERVER pushes the countdown to it when the host starts (an alerting update,
/// so the screen lights), so the walk starting is visible without the app —
/// and one tap opens straight into the hand-off.
struct BuddyWalkActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// "waiting" | "countdown" | "started" | "ended". A string, not an
        /// enum: the server writes it, and an unknown value must still decode.
        var phase: String
        /// Unix seconds of the shared start (countdown / started).
        var startsAtUnix: Double?
        /// People on the walk, the host included.
        var crewCount: Int

        var startsAt: Date? {
            startsAtUnix.map { Date(timeIntervalSince1970: $0) }
        }
    }

    var sessionId: String
    /// The host's first name, for "Rob's buddy walk".
    var hostName: String
    var isRun: Bool
    /// The viewer IS the host (their card says "your", not "Rob's").
    var isHost: Bool

    var walkNoun: String { isRun ? "run" : "walk" }

    var title: String {
        isHost ? "Your buddy \(walkNoun)" : "\(hostName)'s buddy \(walkNoun)"
    }

    var openURL: URL {
        URL(string: "mileaday://buddy-session/\(sessionId)") ?? URL(string: "mileaday://dashboard")!
    }
}

/// The phase line under the title.
private struct BuddyWalkPhaseText: View {
    let attributes: BuddyWalkActivityAttributes
    let state: BuddyWalkActivityAttributes.ContentState

    var body: some View {
        switch state.phase {
        case "countdown":
            if let starts = state.startsAt, starts > Date() {
                HStack(spacing: 4) {
                    Text("Starts in")
                    // Never a range past its own end (`StreakRiskCountdown`'s
                    // trap): only drawn while the start is still ahead.
                    Text(timerInterval: Date()...starts, countsDown: true)
                        .monospacedDigit()
                }
            } else {
                Text("It's started. Tap to start recording")
            }
        case "started":
            Text("It's started. Tap to start recording")
        case "ended":
            Text("Recording")
        default:
            Text(attributes.isHost ? "Start when everyone's ready" : "Waiting for \(attributes.hostName) to start")
        }
    }
}

private extension BuddyWalkActivityAttributes.ContentState {
    /// Started and not recording: the card turns red, the way the in-app
    /// banner does.
    var needsTap: Bool {
        if phase == "started" { return true }
        if phase == "countdown", let starts = startsAt { return starts <= Date() }
        return false
    }
}

private let buddyBlue = Color(red: 0.16, green: 0.42, blue: 0.95)
private let buddyRed = Color(red: 217 / 255, green: 64 / 255, blue: 63 / 255)

struct BuddyWalkLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BuddyWalkActivityAttributes.self) { context in
            BuddyWalkLockScreenView(attributes: context.attributes, state: context.state)
                .widgetURL(context.attributes.openURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.attributes.isRun ? "figure.run" : "figure.2")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(context.state.needsTap ? buddyRed : buddyBlue)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    BuddyWalkPhaseText(attributes: context.attributes, state: context.state)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            } compactLeading: {
                Image(systemName: "figure.2")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(context.state.needsTap ? buddyRed : buddyBlue)
            } compactTrailing: {
                if context.state.phase == "countdown", let starts = context.state.startsAt, starts > Date() {
                    Text(timerInterval: Date()...starts, countsDown: true)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(maxWidth: 40)
                } else {
                    Image(systemName: context.state.needsTap ? "exclamationmark.circle.fill" : "hourglass")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(context.state.needsTap ? buddyRed : .white.opacity(0.8))
                }
            } minimal: {
                Image(systemName: "figure.2")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(context.state.needsTap ? buddyRed : buddyBlue)
            }
            .widgetURL(context.attributes.openURL)
        }
    }
}

private struct BuddyWalkLockScreenView: View {
    let attributes: BuddyWalkActivityAttributes
    let state: BuddyWalkActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill((state.needsTap ? buddyRed : buddyBlue).opacity(0.25))
                Image(systemName: attributes.isRun ? "figure.run" : "figure.2")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(state.needsTap ? buddyRed : buddyBlue)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(attributes.title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                BuddyWalkPhaseText(attributes: attributes, state: state)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(state.needsTap ? .white : .white.opacity(0.75))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if state.crewCount > 1 {
                    Text("\(state.crewCount) walking together")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if state.needsTap {
                Text("Start")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(buddyRed)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white))
            }
        }
        .padding(16)
        .activityBackgroundTint(Color.black.opacity(0.82))
        .activitySystemActionForegroundColor(.white)
    }
}
