import SwiftUI

// Hide start & end — the setting, and the one-time note that it exists.
//
// The trim itself is the SERVER's (every route a non-owner is served is cut at
// read, by the owner's setting), so this screen's only job is to write the
// number and say plainly what it does. The local copy in
// `NotificationPreferences.routePrivacyMeters` mirrors the server for the two
// on-phone readers (the share studio and the owner's own detail sheet).

enum RoutePrivacyLabels {
    /// "Off" / "⅛ mi" / "200 m" … in the user's display unit. The options are
    /// fractions of a MILE (Strava's set), so kilometre users get the
    /// rounded metric equivalent rather than odd decimals.
    static func short(_ meters: Int, unit: DisplayDistanceUnit = DistanceUnits.current) -> String {
        guard meters > 0 else { return String(localized: "Off") }
        switch unit {
        case .miles:
            switch meters {
            case 201: return "⅛ mi"
            case 402: return "¼ mi"
            case 805: return "½ mi"
            case 1609: return "1 mi"
            default: return String(format: "%.2f mi", Double(meters) / 1609.344)
            }
        case .kilometers:
            switch meters {
            case 201: return "200 m"
            case 402: return "400 m"
            case 805: return "800 m"
            case 1609: return "1.6 km"
            default: return "\(meters) m"
            }
        }
    }
}

/// Server → local mirror. Every screen that reads the preferences response
/// passes it through here, so a change made on another phone reaches this
/// one's share cards and detail sheets.
enum RoutePrivacySync {
    static func adopt(_ settings: NotificationSettingsResponse) {
        guard let meters = settings.route_privacy_meters,
              RoutePrivacyTrim.options.contains(meters) else { return }
        var prefs = NotificationPreferences.load()
        guard prefs.routePrivacyMeters != meters else { return }
        prefs.routePrivacyMeters = meters
        prefs.save()
    }
}

/// The "Hide start & end" control on the Privacy page. Owns its ONE server
/// write (`route_privacy_meters`), sent on its own so nothing else on the
/// preferences row is touched.
struct RoutePrivacySettingRow: View {
    @ObservedObject var friendService: FriendService

    @State private var meters: Int = NotificationPreferences.load().routePrivacyMeters
    @State private var saveFailed = false
    /// Guards the picker's onChange while a server value is being adopted.
    @State private var adopting = false

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            MADSettingsRow(
                icon: "eye.slash.circle.fill",
                title: "Hide Start & End",
                subtitle: meters > 0
                    ? String(localized: "On — friends don't see where you start and finish")
                    : String(localized: "Off — friends see your whole route"),
                iconColor: .indigo
            )
            Picker("Hide start & end", selection: $meters) {
                ForEach(RoutePrivacyTrim.options, id: \.self) { option in
                    Text(verbatim: RoutePrivacyLabels.short(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: meters) { old, new in
                guard !adopting, old != new else { return }
                MADHaptics.tap()
                Task { await save(new, previous: old) }
            }
            Text("Friends see your route begin and end a short way from where you actually started. Your stats don't change.")
                .madFont(size: 11, design: .rounded)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if saveFailed {
                Text("Couldn't save that change. Check your connection and try again.")
                    .madFont(size: 11, weight: .semibold, design: .rounded)
                    .foregroundColor(MADTheme.Colors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { await loadFromServer() }
    }

    private func save(_ value: Int, previous: Int) async {
        do {
            let response = try await friendService.updateNotificationSettings([
                "route_privacy_meters": value,
            ])
            var prefs = NotificationPreferences.load()
            prefs.routePrivacyMeters = response.route_privacy_meters ?? value
            prefs.save()
            saveFailed = false
        } catch {
            // The server is the one that trims, so a change it never took
            // must not look applied.
            adopting = true
            meters = previous
            adopting = false
            saveFailed = true
        }
    }

    private func loadFromServer() async {
        guard let settings = try? await friendService.getNotificationSettings() else { return }
        RoutePrivacySync.adopt(settings)
        let served = NotificationPreferences.load().routePrivacyMeters
        if served != meters {
            adopting = true
            meters = served
            adopting = false
        }
    }
}

/// A one-time, dismissible note that hide-start-&-end now exists and is on.
/// Never a modal: it sits in the feed until the user closes it or opens the
/// setting, and is stamped seen on either.
struct RoutePrivacyIntroCard: View {
    static let seenKey = "routePrivacyIntroSeenV1"

    @AppStorage(RoutePrivacyIntroCard.seenKey) private var seen = false
    @State private var showPrivacy = false
    /// Owned here so the sheet's Privacy page keeps one service across
    /// re-renders (the feed doesn't hand one down). Its init is a defaults read.
    @StateObject private var friendService = FriendService()

    var body: some View {
        // Only while it's true: someone who already turned it off on another
        // phone must not be told it's on.
        if !seen, RoutePrivacyTrim.currentSettingMeters > 0 {
            HStack(alignment: .top, spacing: MADTheme.Spacing.md) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.indigo.opacity(0.8)))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Start & end hidden")
                        .madFont(size: 15, weight: .bold, design: .rounded)
                        .foregroundColor(.white)
                    Text("We now hide where your walks start and end from friends. Change it in Privacy.")
                        .madFont(size: 13, design: .rounded)
                        .foregroundColor(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        showPrivacy = true
                    } label: {
                        Text("Privacy settings")
                            .madFont(size: 13, weight: .bold, design: .rounded)
                            .foregroundColor(MADTheme.Colors.madRed)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }

                Spacer(minLength: 0)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { seen = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Dismiss"))
            }
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                            .strokeBorder(Color.indigo.opacity(0.35), lineWidth: 1)
                    )
            )
            // Padded INSIDE the condition, so a seen card leaves nothing —
            // not even a gutter — in the feed's stack.
            .padding(.horizontal, MADTheme.Spacing.md)
            .sheet(isPresented: $showPrivacy, onDismiss: { seen = true }) {
                NavigationStack {
                    PrivacyHubView(friendService: friendService)
                }
            }
        }
    }
}
