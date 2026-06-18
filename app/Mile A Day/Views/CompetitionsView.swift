import SwiftUI

struct CompetitionsView: View {
    @ObservedObject var competitionService: CompetitionService

    /// Competition opened via deep link (mileaday://competition/<id> from the
    /// home-screen Competition widget).
    @State private var deepLinkedCompetition: Competition?

    var body: some View {
        CompetitionsListView(competitionService: competitionService)
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MAD_OpenCompetition"))) { notification in
                guard let id = notification.userInfo?["competitionId"] as? String else { return }
                if let competition = competitionService.competitions.first(where: { $0.competition_id == id }) {
                    deepLinkedCompetition = competition
                }
            }
            .sheet(item: $deepLinkedCompetition) { competition in
                NavigationStack {
                    CompetitionDetailView(competition: competition, competitionService: competitionService)
                }
            }
    }
}

#Preview {
    NavigationStack {
        CompetitionsView(competitionService: CompetitionService())
    }
}
