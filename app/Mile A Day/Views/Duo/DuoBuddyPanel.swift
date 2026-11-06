import SwiftUI

/// Buddy walk command center: your live route beside the crew.
struct DuoBuddyPanel<Roster: View>: View {
    let session: BuddySessionState
    @ViewBuilder let roster: () -> Roster

    var body: some View {
        VStack(spacing: 12) {
            LiveRouteMap(session: session)
            roster()
        }
        .padding(.trailing, 16)
        .padding(.bottom, 12)
    }
}
