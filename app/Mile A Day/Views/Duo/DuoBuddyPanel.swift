import SwiftUI
import MapKit

/// Buddy walk command center: your live route beside the crew. Only YOUR line
/// is drawn, from this phone. Friends only ever learn that you're moving, so
/// nothing here reads or sends anyone's location.
struct DuoBuddyPanel<Roster: View>: View {
    @ViewBuilder let roster: () -> Roster

    /// Close enough to read the next few blocks at a glance mid-walk.
    private var followDistance: CLLocationDistance { 1_100 }

    @State private var trail: [CLLocationCoordinate2D] = []
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                if let here = trail.last {
                    Map(position: $position, interactionModes: []) {
                        if trail.count > 1 {
                            MapPolyline(coordinates: trail)
                                .stroke(MADTheme.Colors.madRed,
                                        style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                        }
                        Annotation("You", coordinate: here) {
                            Circle()
                                .fill(MADTheme.Colors.madRed)
                                .frame(width: 18, height: 18)
                                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                        }
                        .annotationTitles(.hidden)
                    }
                    .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                } else {
                    // Never the map's own fallback: with no fix it shows a
                    // whole continent.
                    VStack(spacing: 10) {
                        Image(systemName: "location.magnifyingglass")
                            .font(.system(size: 30, weight: .semibold))
                            .accessibilityHidden(true)
                        Text("Finding your route")
                            .madFont(size: 15, weight: .semibold, design: .rounded, maxScale: 1.3)
                    }
                    .foregroundColor(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.22))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityLabel("Your live route")
            .task {
                // A slow poll, not a publisher: one fix a second must never
                // redraw the tracker around this map.
                while !Task.isCancelled {
                    refresh()
                    try? await Task.sleep(for: .seconds(3))
                }
            }

            roster()
        }
        .padding(.trailing, 16)
        .padding(.bottom, 12)
    }

    private func refresh() {
        let latest = WorkoutLocationManager.shared.duoTrail
        guard latest.count != trail.count, let here = latest.last else { return }
        trail = latest
        withAnimation(.easeInOut(duration: 1)) {
            position = .camera(MapCamera(centerCoordinate: here, distance: followDistance))
        }
    }
}
