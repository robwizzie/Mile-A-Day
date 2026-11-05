import SwiftUI
import HealthKit

struct HealthAccessView: View {
    @Environment(\.appStateManager) var appStateManager
    @State private var isRequesting = false
    @State private var wasDenied = false

    var body: some View {
        OnboardingStepScaffold(
            colors: [Color(red: 0.98, green: 0.36, blue: 0.42), Color(red: 0.70, green: 0.14, blue: 0.30)],
            chip: "Almost there",
            headline: "Connect Apple Health",
            message: wasDenied
                ? "Health isn't available right now. Turn it on in Settings › Privacy & Security › Health › Mile A Day so your miles count."
                : "Every walk and run in Apple Health counts: your Watch, a treadmill or any app. Your health data stays private.",
            art: { height in HealthHeroArt(height: height) },
            actions: {
                OnboardingPrimaryButton(title: wasDenied ? "Open Settings" : "Connect Health",
                                        isLoading: isRequesting,
                                        action: requestAccess)
            }
        )
    }

    private func requestAccess() {
        if wasDenied {
            // Open app settings so user can enable Health access
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            return
        }

        isRequesting = true

        let healthStore = HKHealthStore()
        guard HKHealthStore.isHealthDataAvailable() else {
            isRequesting = false
            wasDenied = true
            return
        }

        let readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKSeriesType.workoutRoute()
        ]

        let writeTypes: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            // Lets in-app GPS workouts save their route — the source of the
            // feed's route maps at sync time.
            HKSeriesType.workoutRoute()
        ]

        healthStore.requestAuthorization(toShare: writeTypes, read: readTypes) { success, error in
            DispatchQueue.main.async {
                isRequesting = false

                if success {
                    withAnimation(MADTheme.Animation.standard) {
                        appStateManager.completeHealthAccess()
                    }
                } else {
                    wasDenied = true
                }
            }
        }
    }
}

/// A heart in a mile ring with the kinds of activity Health brings in.
private struct HealthHeroArt: View {
    let height: CGFloat
    @Environment(\.introArtWidth) private var artWidth

    var body: some View {
        let ring = min(height * 0.62, 200)
        ZStack {
            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 10)
                .frame(width: ring, height: ring)
                .introPop(0)
            Circle()
                .trim(from: 0, to: 0.85)
                .stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: ring, height: ring)
                .introPop(0.05)
            Image(systemName: "heart.fill")
                .font(.system(size: ring * 0.34, weight: .bold))
                .foregroundColor(.white)
                .introPop(0.1)
                .introBob(4, period: 1.2)
                .accessibilityHidden(true)

            IntroChip(text: "🚶 Walks").introBob(5, period: 3.0, phase: 0.1).introPop(0.2)
                .offset(x: introClampX(-ring * 0.62, "🚶 Walks", width: artWidth), y: -ring * 0.32)
            IntroChip(text: "🏃 Runs").introBob(5, period: 3.3, phase: 0.4).introPop(0.28)
                .offset(x: introClampX(ring * 0.62, "🏃 Runs", width: artWidth), y: -ring * 0.18)
            IntroChip(text: "👟 Steps").introBob(5, period: 3.6, phase: 0.7).introPop(0.36)
                .offset(x: introClampX(-ring * 0.5, "👟 Steps", width: artWidth), y: ring * 0.42)
            IntroChip(text: "⌚️ Watch").introBob(5, period: 3.1, phase: 0.9).introPop(0.44)
                .offset(x: introClampX(ring * 0.55, "⌚️ Watch", width: artWidth), y: ring * 0.38)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    HealthAccessView()
        .environmentObject(AppStateManager())
}
