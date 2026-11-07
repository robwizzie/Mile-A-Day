import SwiftUI
import MapKit

/// Buddy walk command center: your live route beside the crew. Only YOUR line
/// is drawn, from this phone. Friends only ever learn that you're moving, so
/// nothing here reads or sends anyone's location.
struct DuoBuddyPanel<Roster: View>: View {
    @ViewBuilder let roster: () -> Roster
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        VStack(spacing: 12) {
            TimelineView(.periodic(from: .now, by: 3)) { _ in
                let trail = WorkoutLocationManager.shared.duoTrail
                Map(position: $position, interactionModes: [.zoom, .pan]) {
                    UserAnnotation()
                    if trail.count > 1 {
                        MapPolyline(coordinates: trail)
                            .stroke(MADTheme.Colors.madRed, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityLabel("Your live route")

            roster()
        }
        .padding(.trailing, 16)
        .padding(.bottom, 12)
    }
}
