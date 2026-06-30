import SwiftUI

/// Shows the competitions behind a competition medal (won / started / joined),
/// embedded in BadgeDetailView. Loads the viewer's competitions and filters by
/// the badge family inferred from its id prefix.
struct CompetitionBadgeSection: View {
    let badgeId: String

    @StateObject private var service = CompetitionService()
    @State private var loaded = false

    private var myId: String? { UserDefaults.standard.string(forKey: "backendUserId") }

    private enum Kind { case won, started, joined }
    private var kind: Kind {
        if badgeId.hasPrefix("comp_won_") { return .won }
        if badgeId.hasPrefix("comp_started_") { return .started }
        return .joined
    }

    private var sectionTitle: String {
        switch kind {
        case .won: return "COMPETITIONS WON"
        case .started: return "COMPETITIONS YOU STARTED"
        case .joined: return "COMPETITIONS YOU JOINED"
        }
    }

    private var matches: [Competition] {
        guard let myId else { return [] }
        switch kind {
        case .won:
            return service.competitions.filter { $0.winner == myId }
        case .started:
            return service.competitions.filter { $0.owner == myId }
        case .joined:
            return service.competitions.filter { comp in
                comp.users.contains { $0.user_id == myId && $0.invite_status == .accepted }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            Text(sectionTitle)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)

            if !loaded {
                ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, MADTheme.Spacing.md)
            } else if matches.isEmpty {
                Text("These competitions will appear here.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
            } else {
                ForEach(matches.prefix(20)) { comp in
                    row(comp)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            if !loaded {
                try? await service.loadCompetitions(status: "all")
                loaded = true
            }
        }
    }

    private func row(_ comp: Competition) -> some View {
        HStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: kind == .won ? "crown.fill" : (kind == .started ? "flag.checkered" : "figure.run"))
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(kind == .won ? .yellow : MADTheme.Colors.madRed)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.white.opacity(0.06)))

            VStack(alignment: .leading, spacing: 2) {
                Text(comp.competition_name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(subtitle(comp))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer()
            if comp.winner == myId {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.yellow)
            }
        }
        .padding(MADTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func subtitle(_ comp: Competition) -> String {
        let type = comp.type.rawValue.capitalized
        let players = comp.users.filter { $0.invite_status == .accepted }.count
        if let start = comp.start_date {
            let end = comp.end_date.map { " – \($0)" } ?? ""
            return "\(type) · \(players) players · \(start)\(end)"
        }
        return "\(type) · \(players) players"
    }
}
