import Foundation
import SwiftUI

@MainActor
class TrophyService: ObservableObject {
    static let shared = TrophyService()
    private let storageKey = "competitionTrophies"

    @Published var trophies: [CompetitionTrophy] = []

    init() {
        loadTrophies()
    }

    private func loadTrophies() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            trophies = try JSONDecoder().decode([CompetitionTrophy].self, from: data)
        } catch {
            print("[TrophyService] Failed to decode trophies: \(error)")
        }
    }

    private func saveTrophies() {
        do {
            let data = try JSONEncoder().encode(trophies)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("[TrophyService] Failed to encode trophies: \(error)")
        }
    }

    func recordResult(from competition: Competition) {
        guard !trophies.contains(where: { $0.id == competition.competition_id }) else { return }
        guard competition.status == .finished else { return }

        let currentUserId = UserDefaults.standard.string(forKey: "backendUserId")
        let rankedUsers = competition.users
            .filter { $0.invite_status == .accepted }
            .sorted { ($0.score ?? 0) > ($1.score ?? 0) }

        guard let myIndex = rankedUsers.firstIndex(where: { $0.user_id == currentUserId }) else { return }
        let myUser = rankedUsers[myIndex]

        let trophy = CompetitionTrophy(
            id: competition.competition_id,
            competitionName: competition.competition_name,
            competitionType: competition.type,
            placement: myIndex + 1,
            score: myUser.score ?? 0,
            totalParticipants: rankedUsers.count,
            completedDate: competition.end_date ?? "",
            unit: competition.options.unit
        )

        trophies.append(trophy)
        saveTrophies()
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
