import Foundation
import SwiftUI

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

                return CompetitionTrophy(
                    id: competition.competition_id,
                    competitionName: competition.competition_name,
                    competitionType: competition.type,
                    placement: myIndex + 1,
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
}
