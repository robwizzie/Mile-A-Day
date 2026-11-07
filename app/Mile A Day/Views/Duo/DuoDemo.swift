#if DEBUG
import SwiftUI
import CoreLocation

/// Test builds only: `-MADDuoDemo flyover|share` opens that real screen with
/// sample data, for screens that otherwise need a recorded route. Compiled out
/// of Release.
private struct DuoDemoCover: ViewModifier {
    enum Demo: String, Identifiable {
        case flyover, share
        var id: String { rawValue }
    }

    @State private var demo: Demo?

    private static let route: [CLLocationCoordinate2D] = (0...120).map { step in
        let t = Double(step) / 120 * 2 * .pi
        return CLLocationCoordinate2D(latitude: 40.7812 + 0.0105 * sin(t),
                                      longitude: -73.9665 + 0.0072 * sin(2 * t))
    }

    func body(content: Content) -> some View {
        content
            .task {
                // After launch settles: a cover raised during it is dropped.
                try? await Task.sleep(for: .seconds(3))
                demo = UserDefaults.standard.string(forKey: "MADDuoDemo").flatMap(Demo.init)
            }
            .fullScreenCover(item: $demo) { demo in
            switch demo {
            case .flyover:
                RouteFlyoverPlayerView(launch: FlyoverLaunch(
                    coordinates: Self.route,
                    workoutType: "running",
                    stats: nil,
                    author: nil,
                    splitBars: [
                        WorkoutSplitBar(mile: 1, paceSeconds: 561, partialDistance: nil),
                        WorkoutSplitBar(mile: 2, paceSeconds: 538, partialDistance: nil),
                        WorkoutSplitBar(mile: 3, paceSeconds: 574, partialDistance: nil),
                        WorkoutSplitBar(mile: 4, paceSeconds: 522, partialDistance: nil),
                    ],
                    officialDistanceMiles: 4
                ))
            case .share:
                ShareStudioView(content: {
                    var content = MADStoryContent()
                    content.distanceMiles = 3.1
                    content.paceSecondsPerMile = 561
                    content.durationSeconds = 1739
                    content.streak = 128
                    content.totalMiles = 412
                    content.activityName = "Run"
                    content.date = Date()
                    content.coordinates = Self.route
                    return content
                }(), link: nil, initialTemplate: nil)
            }
        }
    }
}

extension View {
    func duoDemoCover() -> some View { modifier(DuoDemoCover()) }
}
#endif
