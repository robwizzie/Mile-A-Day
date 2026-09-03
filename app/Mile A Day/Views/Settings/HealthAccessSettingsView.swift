import SwiftUI
import HealthKit

/// What Mile A Day can and can't see in Health, and how to fix it.
///
/// This screen exists because the failure it describes is completely silent.
/// HealthKit doesn't error when it's switched off — it returns nothing, which
/// is the same answer as "you haven't walked today". So a user whose access is
/// half-granted sees a streak that won't move and a dashboard reading 0.00,
/// with no message anywhere telling them why.
///
/// The old Settings row went straight to `x-apple-health://`, which opens the
/// Health app on Summary: a wall of charts with the switches the user needs
/// three taps away under a tab called Sharing. Most people never found them.
struct HealthAccessSettingsView: View {
    @ObservedObject private var monitor = HealthAccessMonitor.shared
    @ObservedObject private var healthManager = HealthKitManager.shared
    @State private var isRequesting = false

    var body: some View {
        ScrollView {
            VStack(spacing: MADTheme.Spacing.lg) {
                statusCard
                if monitor.state != .unavailable {
                    typesCard
                    routeMapsNote
                    readAccessNote
                    openHealthCard
                }
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, MADTheme.Spacing.md)
        }
        .background(MADTheme.Colors.appBackgroundGradient)
        .navigationTitle("Health Access")
        .navigationBarTitleDisplayMode(.large)
        .task { monitor.refresh() }
        // Fixing this means leaving for the Health app and coming back, so the
        // screen has to re-check on return or it keeps showing the problem the
        // user just solved.
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didBecomeActiveNotification
        )) { _ in
            monitor.refresh()
        }
    }

    // MARK: - Status

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            HStack(spacing: MADTheme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 46, height: 46)
                    Image(systemName: statusIcon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(statusColor)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(.primary)
                    Text(statusSubtitle)
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            // Only offered when it can actually do something. Apple's sheet
            // shows nothing for a type the user has already answered, so
            // putting this button in front of someone whose access is DENIED
            // would be a button that does nothing when tapped.
            if monitor.state == .needsRequest {
                Button {
                    isRequesting = true
                    monitor.requestMissingPermissions { isRequesting = false }
                } label: {
                    HStack(spacing: 8) {
                        if isRequesting {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 14, weight: .bold))
                        }
                        Text(isRequesting ? "Waiting for Health…" : "Grant access")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(MADTheme.Colors.redGradient))
                }
                .buttonStyle(.plain)
                .disabled(isRequesting)
            }
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    private var statusColor: Color {
        switch monitor.state {
        case .granted: return .green
        case .needsRequest: return .orange
        case .someWritesDenied: return MADTheme.Colors.madRed
        case .unavailable: return .gray
        }
    }

    private var statusIcon: String {
        switch monitor.state {
        case .granted: return "checkmark.circle.fill"
        case .needsRequest: return "exclamationmark.circle.fill"
        case .someWritesDenied: return "xmark.circle.fill"
        case .unavailable: return "heart.slash"
        }
    }

    private var statusTitle: String {
        switch monitor.state {
        case .granted: return "Health access looks good"
        case .needsRequest: return "Some access hasn't been granted"
        case .someWritesDenied: return "Mile A Day is blocked from some data"
        case .unavailable: return "Health isn't available on this device"
        }
    }

    private var statusSubtitle: String {
        switch monitor.state {
        case .granted:
            return "Everything Mile A Day asks for has been answered. If your miles still look wrong, check the read switches in Apple Health below."
        case .needsRequest:
            return "One or more types were never answered — usually because an update started using something new. You can grant them right here."
        case .someWritesDenied:
            let blocked = monitor.blockedTitles
            let list = ListFormat.and(blocked)
            return "\(list) \(blocked.count == 1 ? "is" : "are") turned off, so walks you track in the app can't be saved properly. Turn them back on in Apple Health."
        case .unavailable:
            return "This device doesn't have Apple Health, so Mile A Day can't count workouts automatically."
        }
    }

    // MARK: - Per-type list

    private var typesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("WHAT MILE A DAY USES")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundColor(.secondary)
                .padding(.bottom, MADTheme.Spacing.sm)

            ForEach(Array(monitor.kinds.enumerated()), id: \.element.id) { index, kind in
                if index > 0 {
                    Divider()
                        .overlay(Color.white.opacity(0.06))
                        .padding(.vertical, MADTheme.Spacing.xs)
                }
                typeRow(kind)
            }
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    private func typeRow(_ kind: HealthDataKind) -> some View {
        HStack(spacing: MADTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill((kind.isBlocked ? MADTheme.Colors.madRed : Color.teal).opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: kind.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(kind.isBlocked ? MADTheme.Colors.madRed : .teal)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                    .font(MADTheme.Typography.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                Text(kind.purpose)
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            statusPill(kind)
        }
        .padding(.vertical, MADTheme.Spacing.xs)
    }

    /// Only a claim we can back up. For a read-only type Apple tells us
    /// nothing, so the pill says nothing — a green tick there would be a
    /// guess, and a red one would be a false alarm on a user whose access is
    /// perfectly fine.
    @ViewBuilder
    private func statusPill(_ kind: HealthDataKind) -> some View {
        if kind.isBlocked {
            pill("Off", color: MADTheme.Colors.madRed)
        } else if kind.isWritable && kind.writeStatus == .sharingAuthorized {
            pill("On", color: .green)
        } else if kind.isWritable {
            pill("Not asked", color: .orange)
        } else {
            pill("Read only", color: .secondary)
        }
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundColor(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    // MARK: - The part Apple won't tell us

    private var routeMapsNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "map.badge.exclamationmark")
                    .font(.system(size: 12, weight: .bold))
                Text("WHY A WALK HAS NO MAP")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.1)
            }
            .foregroundColor(.secondary)

            Text("If Route is off under Apple Health, a walk you track in Mile A Day can save without GPS, and that map cannot be recovered later. Mile A Day's route sharing, post default, and Stealth Mode settings only decide whether an existing route is shown to other people.")
                .font(MADTheme.Typography.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                .fill(Color.teal.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .strokeBorder(Color.teal.opacity(0.22), lineWidth: 1)
                )
        )
    }

    private var readAccessNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "eye.trianglebadge.exclamationmark")
                    .font(.system(size: 12, weight: .bold))
                Text("ABOUT READING YOUR DATA")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.1)
            }
            .foregroundColor(.secondary)

            Text("Apple never tells an app whether it's allowed to READ your health data — that's a privacy protection, and it means we genuinely can't check it from in here. If your miles or steps look wrong while everything above says it's on, open Apple Health and make sure the read switches are on too.")
                .font(MADTheme.Typography.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                .fill(Color.white.opacity(0.04))
        )
    }

    // MARK: - The door

    private var openHealthCard: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Button(action: HealthAppLink.openHealthSources) {
                HStack(spacing: MADTheme.Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: "heart.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.red)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open Apple Health")
                            .font(MADTheme.Typography.body)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        Text("Takes you to Sharing → Apps")
                            .font(MADTheme.Typography.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            // Spelled out because the destination is a LIST of apps, not this
            // app's page: Apple provides no deep link to a single app's Health
            // permissions, so the last two taps are the user's to make and they
            // need to know what they're looking for.
            VStack(alignment: .leading, spacing: 5) {
                stepRow(1, "Tap Sharing at the bottom, then Apps")
                stepRow(2, "Choose Mile A Day")
                stepRow(3, "Tap Turn On All")
            }
            .padding(.leading, 2)
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(MADTheme.Colors.madRed.opacity(0.7)))
            Text(text)
                .font(MADTheme.Typography.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// "A", "A and B", "A, B and C" — used in the status message, which names the
/// types that are actually off rather than saying "some data".
enum ListFormat {
    static func and(_ items: [String]) -> String {
        switch items.count {
        case 0: return "Some data"
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default:
            return items.dropLast().joined(separator: ", ") + " and " + (items.last ?? "")
        }
    }
}

// MARK: - Banner

/// The in-app warning: a tappable strip that appears on the Dashboard whenever
/// Health access is incomplete, and disappears the moment it isn't.
///
/// This is the message the app was missing. Everything downstream of a revoked
/// permission looks like a bug rather than a setting — a streak stuck at 0, a
/// dashboard that won't count today's walk, widgets a day behind — so the one
/// place it must be said is the first screen the user opens.
struct HealthAccessBanner: View {
    @ObservedObject private var monitor = HealthAccessMonitor.shared
    let onTap: () -> Void

    var body: some View {
        Group {
            if monitor.hasChecked && monitor.state.needsAttention {
                Button(action: onTap) {
                    HStack(spacing: MADTheme.Spacing.sm) {
                        Image(systemName: "heart.slash.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundColor(.primary)
                            Text(subtitle)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .padding(MADTheme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .fill(tint.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                                    .strokeBorder(tint.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .task { monitor.refresh() }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didBecomeActiveNotification
        )) { _ in
            monitor.refresh()
        }
    }

    private var tint: Color {
        monitor.state == .someWritesDenied ? MADTheme.Colors.madRed : .orange
    }

    private var title: String {
        monitor.state == .someWritesDenied
            ? "Health access is turned off"
            : "Finish setting up Health access"
    }

    private var subtitle: String {
        switch monitor.state {
        case .someWritesDenied:
            return "\(ListFormat.and(monitor.blockedTitles)) — your walks may not count. Tap to fix."
        default:
            return "Mile A Day is missing permission for some of your activity data. Tap to grant it."
        }
    }
}
