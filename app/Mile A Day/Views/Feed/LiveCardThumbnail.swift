import SwiftUI
import CoreLocation

/// The small face of a post that has no picture — an AUTO card — drawn live
/// from the walk: its route's shape glowing in the activity colour on the
/// Route Art canvas, or (routeless) the activity glyph on that canvas.
///
/// Auto cards used to be a baked image uploaded with the post, so a grid tile
/// was just that picture shrunk. They're data now (`RunPostService`), and a
/// tile is where most people meet their history, so it draws the same thing
/// the card does rather than a spinner over a picture that doesn't exist.
/// Deliberately light: one `Shape` over a static canvas — no map snapshot, no
/// draw-on animation — because a grid materialises dozens at once.
struct LiveCardThumbnail: View {
    let coordinates: [CLLocationCoordinate2D]?
    let workoutType: String?

    init(post: PostItem) {
        coordinates = post.routeCoordinates
        workoutType = post.workout_type
    }

    var body: some View {
        let accent = ActivityCardView.color(workoutType)
        GeometryReader { geo in
            let inset = min(geo.size.width, geo.size.height) * 0.16
            ZStack {
                ArtCanvasBackground(accent: accent)
                if let coordinates, coordinates.count >= 2 {
                    ShareRouteGlyph(coordinates: coordinates)
                        .stroke(accent.opacity(0.35),
                                style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                        .blur(radius: 3)
                        .padding(inset)
                    ShareRouteGlyph(coordinates: coordinates)
                        .stroke(accent,
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .padding(inset)
                } else {
                    Image(systemName: ActivityCardView.icon(workoutType))
                        .font(.system(size: min(geo.size.width, geo.size.height) * 0.3, weight: .bold))
                        .foregroundColor(accent)
                        .shadow(color: accent.opacity(0.6), radius: 6)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }
}
