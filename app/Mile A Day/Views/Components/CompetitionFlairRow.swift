import SwiftUI

/// The trophy row under a feed card — "COMPETING · Summer Sprint · Team Red" —
/// so friends can see who is mid-competition without opening the Compete tab.
///
/// ONE drawing for photo posts (`PostCardView`) and raw workout cards
/// (`ActivityCardView`): the server lists the owner's competitions on the
/// entry's day for both kinds (`competitions`, bounded to three), so the two
/// cards must read the same or a walk looks "in" a competition only once it
/// has a photo. A chip the viewer is ALSO in says so — that is the card that
/// makes someone go out and answer it.
///
/// Tapping switches to the Compete tab: there is no per-competition deep link
/// on iOS, and the tab lists the same competition by name.
struct CompetitionFlairRow: View {
    let competitions: [PostCompetitionRef]

    /// The app's trophy gold — MADTheme's warning amber, which is what every
    /// medal and streak-milestone surface already uses for "achievement".
    private let gold = MADTheme.Colors.warning

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(competitions) { competition in
                    Button {
                        MADHaptics.tap()
                        NotificationCenter.default.post(
                            name: NSNotification.Name("MAD_SwitchTab"),
                            object: nil,
                            userInfo: ["tab": 1]
                        )
                    } label: {
                        chip(competition)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibilityText(competition))
                }
            }
            .padding(.horizontal, 2)
        }
        // A vertical feed must never pick up a sideways wobble from a row
        // that fits: only a genuinely overflowing row scrolls.
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func chip(_ competition: PostCompetitionRef) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(gold)
                .accessibilityHidden(true)
            Text(headline(competition))
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(0.8)
                .foregroundColor(gold)
            Text(competition.displayName)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
            if let team = competition.team_name, !team.isEmpty {
                Text("·")
                    .foregroundColor(.white.opacity(0.35))
                Text("Team \(team)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(gold.opacity(competition.viewer_in == true ? 0.22 : 0.12))
        )
        .overlay(
            Capsule().strokeBorder(gold.opacity(competition.viewer_in == true ? 0.55 : 0), lineWidth: 1)
        )
    }

    /// "COMPETING" for a live one, "COMPETED" once it has ended, and the
    /// viewer's own competitions call that out — a friend's card in YOUR race
    /// is the one worth answering.
    private func headline(_ competition: PostCompetitionRef) -> String {
        let live = competition.ended != true
        if competition.viewer_in == true { return live ? "VS YOU" : "RACED YOU" }
        return live ? "COMPETING" : "COMPETED"
    }

    private func accessibilityText(_ competition: PostCompetitionRef) -> String {
        var parts = [headline(competition).capitalized, "in", competition.displayName]
        if let team = competition.team_name, !team.isEmpty { parts.append("for team \(team)") }
        return parts.joined(separator: " ") + ". Opens the Compete tab."
    }
}
