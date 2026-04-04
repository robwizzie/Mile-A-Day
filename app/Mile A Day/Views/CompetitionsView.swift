import SwiftUI

struct CompetitionsView: View {
    @ObservedObject var competitionService: CompetitionService

    var body: some View {
        CompetitionsListView(competitionService: competitionService)
    }
}

#Preview {
    NavigationStack {
        CompetitionsView(competitionService: CompetitionService())
    }
}
