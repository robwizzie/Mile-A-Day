import SwiftUI
import HealthKit

struct HealthAccessView: View {
    @Environment(\.appStateManager) var appStateManager
    @State private var isRequesting = false
    @State private var wasDenied = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    MADTheme.Colors.madWhite,
                    MADTheme.Colors.secondaryBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: MADTheme.Spacing.xl) {
                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(MADTheme.Colors.madRed.opacity(0.1))
                        .frame(width: 120, height: 120)

                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 56))
                        .foregroundColor(MADTheme.Colors.madRed)
                }

                // Title & description
                VStack(spacing: MADTheme.Spacing.md) {
                    Text("Health Data Access")
                        .font(MADTheme.Typography.title1)
                        .fontWeight(.bold)
                        .foregroundColor(MADTheme.Colors.primaryText)

                    Text("Mile A Day needs access to your Health data to track your runs and keep your streak going.")
                        .font(MADTheme.Typography.body)
                        .foregroundColor(MADTheme.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, MADTheme.Spacing.md)
                }

                // Feature list
                VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                    featureRow(icon: "figure.run", text: "Track your running workouts")
                    featureRow(icon: "flame.fill", text: "Calculate calories and distance")
                    featureRow(icon: "chart.line.uptrend.xyaxis", text: "Sync workout history")
                    featureRow(icon: "bolt.fill", text: "Maintain your daily streak")
                }
                .padding(MADTheme.Spacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .fill(MADTheme.Colors.cardBackground)
                )

                if wasDenied {
                    VStack(spacing: MADTheme.Spacing.sm) {
                        Text("Health access is required for this app to function.")
                            .font(MADTheme.Typography.caption)
                            .foregroundColor(MADTheme.Colors.error)
                            .multilineTextAlignment(.center)

                        Text("Please enable Health access in Settings > Privacy & Security > Health > Mile A Day.")
                            .font(MADTheme.Typography.caption)
                            .foregroundColor(MADTheme.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, MADTheme.Spacing.md)
                }

                Spacer()

                // Action button
                VStack(spacing: MADTheme.Spacing.md) {
                    Button(action: requestAccess) {
                        HStack {
                            if isRequesting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Text(wasDenied ? "Open Settings" : "Allow Health Access")
                                    .font(MADTheme.Typography.headline)
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MADTheme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                .fill(MADTheme.Colors.madRed)
                        )
                        .foregroundColor(.white)
                    }
                    .disabled(isRequesting)

                    Text("Without Health access, Mile A Day cannot track your workouts or streaks.")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(MADTheme.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(MADTheme.Spacing.lg)
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(MADTheme.Colors.madRed)
                .frame(width: 28)

            Text(text)
                .font(MADTheme.Typography.body)
                .foregroundColor(MADTheme.Colors.primaryText)
        }
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
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
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

#Preview {
    HealthAccessView()
        .environmentObject(AppStateManager())
}
