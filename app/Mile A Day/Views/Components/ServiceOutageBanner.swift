import SwiftUI

/// "Mile A Day is down" — shown when the app can't reach the server.
///
/// Hosted ONCE at MainTabView root, like the celebration container and the
/// notification banner: an outage is a fact about the whole app, and a banner
/// owned by a tab plays to nobody when the user is on a different one.
///
/// It says which of two different things went wrong, because the fixes are
/// different: the phone has no connection, or the service is down. Telling
/// someone in a lift that Mile A Day is broken is a lie that costs trust the
/// next time it isn't.
struct ServiceOutageBanner: View {
    @ObservedObject private var monitor = ServiceHealthMonitor.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Re-checks while the banner is up, so it clears itself when the service
    /// comes back even if the user isn't touching anything.
    private let clock = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    private var isOffline: Bool { monitor.health == .deviceOffline }

    private var title: String {
        if isOffline { return "You're offline" }
        return monitor.notice?.title ?? "Mile A Day is down"
    }

    private var message: String {
        if isOffline {
            return "Your walks are still being recorded. They'll sync when you're back on."
        }
        return monitor.notice?.message
            ?? "We're on it. Your walks are recorded on your phone and will sync as soon as we're back."
    }

    private var backText: String? {
        guard let until = monitor.notice?.until, until > Date() else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDateInToday(until) ? "h:mm a" : "EEE h:mm a"
        return "Back by \(formatter.string(from: until))"
    }

    /// Offline is grey — the app isn't broken and shouldn't wear an alarm
    /// colour for something the user can see on their own status bar.
    private var tint: Color { isOffline ? .white.opacity(0.6) : MADTheme.Colors.warning }

    var body: some View {
        Group {
            if monitor.showsBanner {
                content
                    .transition(reduceMotion
                                ? .opacity
                                : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: monitor.showsBanner)
        .onReceive(clock) { _ in
            guard monitor.isDown else { return }
            monitor.recheck()
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isOffline ? "wifi.slash" : "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text(message)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                if let backText {
                    Text(backText)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(tint)
                }
            }

            Spacer(minLength: 4)

            Button {
                monitor.isDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.55))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .padding(.horizontal, 12)
    }
}
