import SwiftUI
import HealthKit

// MARK: - Watch Theme
// Mirrors `MADTheme` from the iOS app so the watch feels like a tiny version
// of the phone app — same red brand palette, same rounded type, same vibe.
enum WatchTheme {
    // Brand
    static let madRed = Color(red: 0.85, green: 0.25, blue: 0.35)
    static let madRedDeep = Color(red: 0.70, green: 0.18, blue: 0.27)
    static let madRedBright = Color(red: 0.95, green: 0.32, blue: 0.42)

    // Status
    static let success = Color(red: 0.30, green: 0.82, blue: 0.45)
    static let successDeep = Color(red: 0.18, green: 0.62, blue: 0.32)
    static let warning = Color(red: 1.00, green: 0.65, blue: 0.10)

    // Neutrals
    static let surfaceHigh = Color.white.opacity(0.14)
    static let surface = Color.white.opacity(0.08)
    static let surfaceLow = Color.white.opacity(0.05)
    static let hairline = Color.white.opacity(0.18)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.42)

    // Backgrounds — tinted near-black with a hint of red, mirroring iOS `appBackgroundGradient`.
    static let appBackground = LinearGradient(
        colors: [
            Color(red: 0.16, green: 0.07, blue: 0.10),
            Color(red: 0.08, green: 0.03, blue: 0.05),
            Color.black
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let primaryButton = LinearGradient(
        colors: [madRedBright, madRedDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let successGradient = LinearGradient(
        colors: [success, successDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let progressGradient = AngularGradient(
        colors: [madRedBright, warning, madRedBright, madRedDeep, madRedBright],
        center: .center,
        startAngle: .degrees(-90),
        endAngle: .degrees(270)
    )

    static let progressGradientComplete = AngularGradient(
        colors: [success, Color(red: 0.55, green: 0.92, blue: 0.55), success, successDeep, success],
        center: .center,
        startAngle: .degrees(-90),
        endAngle: .degrees(270)
    )
}

// MARK: - Reusable Watch Components

/// Press feedback button style for watch — tiny scale + dim on press.
struct WatchPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var userManager: UserManager

    @State private var showWorkoutView = false
    @State private var selectedActivityType: HKWorkoutActivityType = .running
    @State private var locationType: HKWorkoutSessionLocationType = .outdoor
    @State private var ringPulse: Bool = false

    private var goalDistance: Double {
        userManager.currentUser.goalMiles > 0 ? userManager.currentUser.goalMiles : 1.0
    }

    private var currentDistance: Double { healthManager.todaysDistance }

    private var progress: Double { min(currentDistance / goalDistance, 1.0) }

    private var isCompleted: Bool { currentDistance >= goalDistance }

    private var currentStreak: Int { healthManager.retroactiveStreak }

    private var remainingDistance: Double { max(goalDistance - currentDistance, 0) }

    private var greetingFirstName: String? {
        let first = userManager.currentUser.firstName?.trimmingCharacters(in: .whitespaces) ?? ""
        if !first.isEmpty { return first }
        let fallback = userManager.currentUser.name.split(separator: " ").first.map(String.init) ?? ""
        return fallback.isEmpty ? nil : fallback
    }

    var body: some View {
        ZStack {
            WatchTheme.appBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    header
                        .padding(.top, 2)

                    heroRing
                        .padding(.top, 2)

                    goalStatus

                    streakPill

                    activityButtons
                        .padding(.top, 4)

                    locationToggle
                        .padding(.top, 2)
                        .padding(.bottom, 4)
                }
                .padding(.horizontal, 6)
            }
        }
        .fullScreenCover(isPresented: $showWorkoutView) {
            WorkoutView(
                healthManager: healthManager,
                userManager: userManager,
                goalDistance: goalDistance,
                startingDistance: currentDistance,
                activityType: selectedActivityType,
                locationType: locationType
            )
        }
        .onAppear {
            healthManager.fetchTodaysDistance()
            // Gentle pulse on the ring when not yet complete — adds life to the screen.
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                ringPulse.toggle()
            }
        }
        .onChange(of: showWorkoutView) { oldValue, newValue in
            if oldValue && !newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    healthManager.fetchTodaysDistance()
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 1) {
            HStack(spacing: 4) {
                if let name = greetingFirstName {
                    Text("Hey, ")
                        .foregroundColor(WatchTheme.textSecondary)
                    + Text(name)
                        .foregroundColor(WatchTheme.textPrimary)
                } else {
                    Text("Mile A Day")
                        .foregroundColor(WatchTheme.textPrimary)
                }
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            Text(Date(), format: .dateTime.weekday(.wide).month().day())
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(WatchTheme.textTertiary)
        }
    }

    // MARK: - Hero Ring

    private var heroRing: some View {
        ZStack {
            // Outer soft glow that breathes when not complete
            Circle()
                .stroke(
                    (isCompleted ? WatchTheme.success : WatchTheme.madRedBright)
                        .opacity(ringPulse && !isCompleted ? 0.22 : 0.10),
                    lineWidth: 1
                )
                .frame(width: 132, height: 132)
                .blur(radius: 4)

            // Track
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 11)
                .frame(width: 122, height: 122)

            // Progress arc
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    isCompleted ? WatchTheme.progressGradientComplete : WatchTheme.progressGradient,
                    style: StrokeStyle(lineWidth: 11, lineCap: .round)
                )
                .frame(width: 122, height: 122)
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.9, dampingFraction: 0.75), value: progress)
                .shadow(
                    color: (isCompleted ? WatchTheme.success : WatchTheme.madRedBright).opacity(0.35),
                    radius: 6, x: 0, y: 0
                )

            // Center content
            VStack(spacing: 0) {
                if isCompleted {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WatchTheme.successGradient)
                        .padding(.bottom, 2)
                }
                Text(String(format: "%.2f", currentDistance))
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundColor(WatchTheme.textPrimary)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                HStack(spacing: 2) {
                    Text("/")
                    Text(String(format: "%.1f", goalDistance))
                    Text("mi")
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(WatchTheme.textTertiary)
            }
        }
    }

    // MARK: - Goal Status

    private var goalStatus: some View {
        Group {
            if isCompleted {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                    Text("Goal complete!")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(WatchTheme.successGradient)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(WatchTheme.success.opacity(0.16))
                )
            } else {
                Text(String(format: "%.2f mi to goal", remainingDistance))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(WatchTheme.textSecondary)
            }
        }
    }

    // MARK: - Streak Pill

    private var streakPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [WatchTheme.warning, WatchTheme.madRedBright],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            Text("\(currentStreak)")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(WatchTheme.textPrimary)
                .contentTransition(.numericText())
            Text(currentStreak == 1 ? "day streak" : "day streak")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(WatchTheme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(WatchTheme.surface)
                .overlay(Capsule().stroke(WatchTheme.hairline, lineWidth: 0.5))
        )
    }

    // MARK: - Activity Buttons

    private var activityButtons: some View {
        VStack(spacing: 8) {
            Button {
                start(activity: .running)
            } label: {
                actionButtonLabel(
                    icon: "figure.run",
                    title: "Start Run",
                    style: .primary
                )
            }
            .buttonStyle(WatchPressStyle())

            Button {
                start(activity: .walking)
            } label: {
                actionButtonLabel(
                    icon: "figure.walk",
                    title: "Start Walk",
                    style: .secondary
                )
            }
            .buttonStyle(WatchPressStyle())
        }
    }

    private enum ActionButtonStyle { case primary, secondary }

    private func actionButtonLabel(icon: String, title: String, style: ActionButtonStyle) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .heavy))
                .opacity(0.7)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(style == .primary
                        ? AnyShapeStyle(WatchTheme.primaryButton)
                        : AnyShapeStyle(WatchTheme.surfaceHigh))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        style == .primary
                            ? Color.white.opacity(0.18)
                            : WatchTheme.hairline,
                        lineWidth: 0.6
                    )
            }
        )
        .shadow(
            color: style == .primary ? WatchTheme.madRedDeep.opacity(0.35) : .clear,
            radius: 6, x: 0, y: 3
        )
    }

    // MARK: - Indoor / Outdoor Toggle

    private var locationToggle: some View {
        HStack(spacing: 0) {
            locationChip(option: .outdoor, label: "Outdoor", icon: "location.fill")
            locationChip(option: .indoor, label: "Indoor", icon: "house.fill")
        }
        .padding(3)
        .background(
            Capsule()
                .fill(WatchTheme.surfaceLow)
                .overlay(Capsule().stroke(WatchTheme.hairline, lineWidth: 0.5))
        )
        .frame(maxWidth: .infinity)
    }

    private func locationChip(option: HKWorkoutSessionLocationType, label: String, icon: String) -> some View {
        let isSelected = locationType == option
        return Button {
            guard locationType != option else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                locationType = option
            }
            WKInterfaceDevice.current().play(.click)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundColor(isSelected ? .white : WatchTheme.textSecondary)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(
                Capsule()
                    .fill(isSelected ? WatchTheme.madRed.opacity(0.85) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func start(activity: HKWorkoutActivityType) {
        selectedActivityType = activity
        WKInterfaceDevice.current().play(.start)
        showWorkoutView = true
    }
}

#Preview {
    ContentView()
        .environmentObject(HealthKitManager.shared)
        .environmentObject(UserManager.shared)
}
