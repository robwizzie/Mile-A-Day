import SwiftUI
import HealthKit
import WatchKit

// MARK: - A run the iPhone records

/// The Watch app's delegate. Its one job: a run started on the iPhone
/// (`HKHealthStore.startWatchApp(with:)`, `WatchWorkoutLink` on the phone)
/// launches or wakes this app and lands here with the run's configuration.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        PhoneRunCompanion.shared.start(workoutConfiguration)
    }
}

/// Owns the Watch's side of a phone-recorded run: a `WatchWorkoutManager`
/// in companion mode (heart rate to the phone, the phone's plan on the
/// wrist, the workout discarded at the end). `ContentView` shows
/// `PhoneRunView` while `manager` is set.
final class PhoneRunCompanion: ObservableObject {
    static let shared = PhoneRunCompanion()

    @Published private(set) var manager: WatchWorkoutManager?

    private init() {}

    /// Main thread (the application delegate).
    func start(_ configuration: HKWorkoutConfiguration) {
        // A repeat call for the run already on the wrist: the iPhone app was
        // relaunched mid-run. Offer it the session again (HealthKit may
        // already have reconnected it; then this just fails quietly).
        if let manager, !manager.companionFinished {
            manager.remirrorCompanion()
            return
        }
        // The Watch is recording its own workout: one session at a time, so
        // the phone's run goes on without heart rate.
        guard WatchWorkoutManager.live == nil else {
            print("[Watch] A workout is already running; not starting the iPhone's")
            return
        }
        let fresh = WatchWorkoutManager()
        manager = fresh
        fresh.startCompanion(configuration: configuration)
    }

    func close() {
        manager = nil
    }
}

/// The wrist during a run the iPhone records: the plan page (the same one a
/// Watch plan run shows, fed by the phone) or the phone's distance and time,
/// with heart rate; then pause and end, which the phone follows.
struct PhoneRunView: View {
    @ObservedObject var manager: WatchWorkoutManager
    @State private var page = 0
    @State private var confirmEnd = false

    var body: some View {
        ZStack {
            WatchTheme.appBackground
                .ignoresSafeArea()

            if let failure = manager.startupFailure {
                failureView(failure)
            } else {
                pager
            }
        }
        .onChange(of: manager.companionFinished) { _, finished in
            if finished { PhoneRunCompanion.shared.close() }
        }
    }

    private var pager: some View {
        TabView(selection: $page) {
            firstPage
                .tag(0)
            controls
                .tag(1)
        }
        .tabViewStyle(.verticalPage)
        .confirmationDialog("End this run on your iPhone too?", isPresented: $confirmEnd) {
            Button("End run", role: .destructive) {
                WKInterfaceDevice.current().play(.stop)
                manager.endWorkout { _ in }
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    /// Health refused the session (no permission). The iPhone's run goes on
    /// without heart rate.
    private func failureView(_ message: String) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("No heart rate for this run")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(WatchTheme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(WatchTheme.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Close") {
                    // The phone's run carries on: only this session ends.
                    manager.standDownCompanion()
                    PhoneRunCompanion.shared.close()
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 8)
        }
    }

    @ViewBuilder
    private var firstPage: some View {
        if let status = manager.planStatus {
            WatchPlanPage(workoutManager: manager, status: status, time: time)
        } else {
            summaryPage
        }
    }

    /// A run without a plan, or before the phone's first update.
    private var summaryPage: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "iphone")
                    .accessibilityHidden(true)
                Text(manager.isPaused ? "PAUSED" : "ON YOUR IPHONE")
            }
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundColor(manager.isPaused ? WatchTheme.warning : WatchTheme.madRedBright)
            .tracking(1.0)

            Text(String(format: "%.2f", manager.distance))
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundColor(WatchTheme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("MI")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundColor(WatchTheme.textTertiary)
                .tracking(1.5)

            HStack(spacing: 10) {
                Text(time)
                    .monospacedDigit()
                    .foregroundColor(WatchTheme.textSecondary)
                if manager.currentHeartRate > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                            .accessibilityHidden(true)
                        Text("\(Int(manager.currentHeartRate.rounded()))")
                            .monospacedDigit()
                            .foregroundColor(WatchTheme.textPrimary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Heart rate \(Int(manager.currentHeartRate.rounded()))")
                }
            }
            .font(.system(size: 16, weight: .heavy, design: .rounded))
        }
        .padding(.horizontal, 8)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                Button {
                    if manager.isPaused {
                        manager.resumeWorkout()
                    } else {
                        manager.pauseWorkout()
                    }
                    WKInterfaceDevice.current().play(.click)
                } label: {
                    circle(icon: manager.isPaused ? "play.fill" : "pause.fill",
                           background: WatchTheme.warning, foreground: .black)
                }
                .buttonStyle(WatchPressStyle())
                .disabled(manager.isEnding)
                .accessibilityLabel(manager.isPaused ? "Resume run" : "Pause run")

                Button {
                    confirmEnd = true
                } label: {
                    circle(icon: "stop.fill", background: WatchTheme.madRed, foreground: .white)
                }
                .buttonStyle(WatchPressStyle())
                .disabled(manager.isEnding)
                .accessibilityLabel("End run")
            }

            Text("Your iPhone records this run and saves it.")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(WatchTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 10)
    }

    private func circle(icon: String, background: Color, foreground: Color) -> some View {
        ZStack {
            Circle()
                .fill(background)
                .frame(width: 50, height: 50)
            Image(systemName: icon)
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(foreground)
        }
    }

    private var time: String {
        PlanRunFormat.clock(manager.elapsedTime)
    }
}
