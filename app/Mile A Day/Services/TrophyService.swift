import Foundation
import SwiftUI

/// Per-mode record. Every mode is present even at zero so the Record tab can
/// draw a stable grid instead of a list that reflows as you play.
///
/// Top-level rather than nested in `TrophyService` so it carries no actor
/// isolation — views store it directly.
struct CompetitionModeRecord: Identifiable {
    let type: CompetitionType
    var wins: Int
    var losses: Int

    var id: String { type.rawValue }
    var total: Int { wins + losses }
}

/// Your competition record, derived client-side from the competitions the tab
/// already has.
///
/// This is the Phase-1 source for the Record tab and stays afterwards as the
/// offline/degraded fallback: a server deploy and an App Store rollout are
/// weeks apart in both directions, so the tab must be able to show a record
/// with no endpoint at all.
///
/// It can only see competitions in `competitionService.competitions` (one page,
/// `status: "all"`), so it undercounts a long history — which is exactly what
/// the server-side record endpoint exists to fix.
@MainActor
class TrophyService: ObservableObject {
    static let shared = TrophyService()

    @Published var trophies: [CompetitionTrophy] = []

    /// Recompute trophies from the live competition data
    func updateTrophies(from competitions: [Competition]) {
        let currentUserId = UserDefaults.standard.string(forKey: "backendUserId")

        trophies = competitions
            .filter { $0.status == .finished }
            .compactMap { competition -> CompetitionTrophy? in
                let rankedUsers = competition.users
                    .filter { $0.invite_status == .accepted }
                    .sorted { ($0.score ?? 0) > ($1.score ?? 0) }

                guard let myIndex = rankedUsers.firstIndex(where: { $0.user_id == currentUserId }) else {
                    return nil
                }
                let myUser = rankedUsers[myIndex]

                // Use authoritative winner field for 1st place accuracy
                let placement: Int
                if let winnerId = competition.winner, winnerId == currentUserId {
                    placement = 1
                } else if competition.winner != nil && competition.winner != currentUserId && myIndex == 0 {
                    // Backend says someone else won, but score sort puts us first (tie scenario)
                    // Trust backend winner — we're at least 2nd
                    placement = 2
                } else {
                    placement = myIndex + 1
                }

                return CompetitionTrophy(
                    id: competition.competition_id,
                    competitionName: competition.competition_name,
                    competitionType: competition.type,
                    placement: placement,
                    score: myUser.score ?? 0,
                    totalParticipants: rankedUsers.count,
                    completedDate: competition.end_date ?? "",
                    unit: competition.options.unit
                )
            }
    }

    var goldCount: Int { trophies.filter { $0.placement == 1 }.count }
    var silverCount: Int { trophies.filter { $0.placement == 2 }.count }
    var bronzeCount: Int { trophies.filter { $0.placement == 3 }.count }
    var totalCompetitions: Int { trophies.count }
    var winRate: Double {
        guard totalCompetitions > 0 else { return 0 }
        return Double(goldCount) / Double(totalCompetitions) * 100
    }

    // MARK: - Record

    /// A win is 1st place. Everything else you finished is a loss — there is no
    /// third outcome, because the backend resolves ties to a single `winner`
    /// before a competition is ever marked ended.
    var wins: Int { goldCount }
    var losses: Int { max(0, totalCompetitions - goldCount) }
    var podiums: Int { trophies.filter { $0.placement <= 3 }.count }

    /// "4–7" for the record hero.
    var recordText: String { "\(wins)–\(losses)" }

    /// Consecutive wins ending at the most recent finished competition.
    var currentWinStreak: Int {
        var streak = 0
        for trophy in trophiesNewestFirst {
            guard trophy.placement == 1 else { break }
            streak += 1
        }
        return streak
    }

    var bestWinStreak: Int {
        var best = 0
        var run = 0
        for trophy in trophiesNewestFirst {
            if trophy.placement == 1 {
                run += 1
                best = max(best, run)
            } else {
                run = 0
            }
        }
        return best
    }

    /// Every mode, in the enum's own order, so the grid never reorders itself.
    var byMode: [CompetitionModeRecord] {
        CompetitionType.allCases.map { type in
            let forType = trophies.filter { $0.competitionType == type }
            let modeWins = forType.filter { $0.placement == 1 }.count
            return CompetitionModeRecord(
                type: type,
                wins: modeWins,
                losses: max(0, forType.count - modeWins)
            )
        }
    }

    /// Your best mode by win rate, used for a one-line callout. Nil until
    /// you've actually finished something in at least one mode.
    var strongestMode: CompetitionModeRecord? {
        byMode
            .filter { $0.total > 0 }
            .max { lhs, rhs in
                let l = Double(lhs.wins) / Double(lhs.total)
                let r = Double(rhs.wins) / Double(rhs.total)
                return l == r ? lhs.total < rhs.total : l < r
            }
    }

    /// Finished competitions, newest first. `completedDate` is a "YYYY-MM-DD"
    /// `date` column, so a plain string sort is chronological.
    var trophiesNewestFirst: [CompetitionTrophy] {
        trophies.sorted { $0.completedDate > $1.completedDate }
    }
}
