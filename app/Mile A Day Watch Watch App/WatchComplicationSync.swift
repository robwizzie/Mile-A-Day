import Foundation
import WidgetKit

/// Keeps the watch face in step with the app. Complications have a daily
/// reload budget, so a reload is spent only when something they show changed:
/// the streak, the goal, whether it's done, or a tenth of a mile of progress.
enum WatchComplicationSync {
    private static var lastShown: String?

    static func update(streak: Int, miles: Double, goal: Double) {
        let snapshot = WatchDayStore.Snapshot(streak: streak, miles: miles, goal: goal,
                                              day: WatchDayStore.dayStamp())
        guard snapshot != WatchDayStore.load() else { return }
        WatchDayStore.save(snapshot)

        let shown = "\(streak)|\(goal)|\(miles >= goal)|\(Int(miles * 10))|\(snapshot.day)"
        guard shown != lastShown else { return }
        lastShown = shown
        WidgetCenter.shared.reloadAllTimelines()
    }
}
