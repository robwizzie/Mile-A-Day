import SwiftUI

/// Modal presentation of the ghost-race picker.
///
/// The picker itself lives in `GhostRaceOptionsContent` — this is only the
/// chrome for showing it as a sheet. The walk/run wizard renders that same
/// content as an inline step instead (no sheet), so the two surfaces can never
/// drift: change the picker once, both get it.
///
/// Kept as a sheet for the buddy lobby, whose job is getting someone into the
/// room; the race is one row on it, not a step in a flow.
struct GhostRaceSetupSheet: View {
    let activityKey: String
    /// Backend fastest-mile PR in seconds, when there is one.
    let seedPaceSeconds: Double?
    /// Currently armed target, so re-opening shows what's already set.
    let current: BestEffortStore.GhostTarget?
    /// Non-nil = race this. Nil = don't race this session.
    let onDone: (BestEffortStore.GhostTarget?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

                GhostRaceOptionsContent(
                    activityKey: activityKey,
                    seedPaceSeconds: seedPaceSeconds,
                    current: current,
                    accent: MADTheme.workoutColor(activityKey),
                    accentForeground: MADTheme.Colors.madWhite,
                    declineTitle: current == nil ? "Not this time" : "Turn off racing",
                    onRace: { target in
                        onDone(target)
                        dismiss()
                    },
                    onDecline: {
                        onDone(nil)
                        dismiss()
                    }
                )
            }
            .navigationTitle("Ghost Race")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Pure abort: leaves whatever is already armed untouched.
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
