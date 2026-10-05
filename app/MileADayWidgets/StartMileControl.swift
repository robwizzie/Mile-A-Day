import AppIntents
import SwiftUI
import WidgetKit

/// Control Center / Lock Screen / Action Button control: "Start My Mile".
///
/// Runs `StartMileIntent` (Shared/WidgetDataStore.swift — compiled into both
/// this extension and the app), whose `openAppWhenRun` makes the system launch
/// the app and perform the intent THERE, where it reaches the app's routing.
/// Nothing here starts a workout on its own: the app opens the tracker, or
/// reopens the workout already in progress.
@available(iOS 18.0, *)
struct StartMileControl: ControlWidget {
    static let kind = "StartMileControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartMileIntent()) {
                Label("Start My Mile", systemImage: "figure.walk")
            }
        }
        .displayName("Start My Mile")
        .description("Open Mile A Day's workout tracker, or return to the workout in progress.")
    }
}
