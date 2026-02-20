import SwiftUI

struct CreateCompetitionView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var competitionService = CompetitionService()
    @StateObject private var friendService = FriendService()

    // Form fields
    @State private var selectedFriends: Set<BackendUser> = []
    @State private var selectedType: CompetitionType = .apex
    @State private var competitionName = ""
    @State private var goal: Double = 5.0
    @State private var unit: CompetitionUnit = .miles
    @State private var durationHours: Int = 24
    @State private var customDurationDays: Int = 3
    @State private var isCustomDuration: Bool = false
    @State private var hasEndDate: Bool = true
    @State private var customEndDate: Date = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
    @State private var selectedWorkouts: Set<CompetitionActivity> = [.run]
    @State private var firstTo: Int = 1
    @State private var interval: CompetitionInterval = .day

    // UI state
    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    @State private var failedInviteCount = 0
    @State private var showFriendPicker = false
    @State private var showTypeSelector = false

    var canCreate: Bool {
        !selectedFriends.isEmpty &&
        (selectedType == .clash || selectedType == .apex || goal > 0)
    }

    var firstSelectedFriend: BackendUser? {
        selectedFriends.first
    }

    var friendBestDistance: Double {
        // In a real implementation, fetch from friend stats
        return goal * 2.4
    }

    // Contextual labels based on competition type
    var goalLabel: String {
        switch selectedType {
        case .streaks:
            return "Daily Goal"
        case .targets:
            return "Goal to Score a Point"
        case .race:
            return "Total Distance to Win"
        case .apex, .clash:
            return "" // These don't use a goal
        }
    }

    var goalDescription: String {
        switch selectedType {
        case .streaks:
            return "Minimum distance to maintain streak each day"
        case .targets:
            return "Distance needed per interval to score a point"
        case .race:
            return "First to reach this distance wins"
        case .apex, .clash:
            return ""
        }
    }

    /// Clash: no goal (whoever goes further wins the point)
    /// Apex: no goal (whoever has most total distance wins)
    var needsGoal: Bool {
        selectedType != .clash && selectedType != .apex
    }

    /// Apex, Targets, Clash use interval-based scoring
    var needsInterval: Bool {
        selectedType == .apex || selectedType == .targets || selectedType == .clash
    }

    var needsFirstTo: Bool {
        selectedType == .streaks || selectedType == .clash
    }

    /// Only Apex and Targets need a fixed duration
    /// Clash ends when point target is reached
    /// Streaks end when someone breaks their streak
    /// Race ends when someone reaches the distance
    var needsDuration: Bool {
        selectedType == .apex || selectedType == .targets
    }

    /// Description for the unit-only section (Clash and Apex)
    var unitOnlyDescription: String {
        switch selectedType {
        case .clash:
            return "Whoever goes further each interval wins the point"
        case .apex:
            return "Whoever covers the most total distance wins"
        default:
            return ""
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient
                    .ignoresSafeArea(.all)

                ScrollView {
                    VStack(spacing: MADTheme.Spacing.xl) {
                        // Challengers Section
                        challengersSection

                        // Competition Type Selection
                        competitionTypeSection

                        // Activity Selection
                        activitySelectionSection

                        // Goal Selection (not needed for Clash - whoever goes further wins)
                        if needsGoal {
                            goalSelectionSection
                        } else {
                            // Clash only needs a unit selector
                            unitOnlySection
                        }

                        // Type-Specific Options
                        if needsInterval {
                            intervalSection
                        }

                        if needsFirstTo {
                            firstToSection
                        }

                        // Duration (only for apex and targets - others end by condition)
                        if needsDuration {
                            durationSection
                        }

                        // Extra space so content is never hidden behind the fixed bottom button
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, MADTheme.Spacing.md)
                    .padding(.top, MADTheme.Spacing.md)
                    .padding(.bottom, MADTheme.Spacing.md)
                }

                // Send Invite Button (Fixed at bottom)
                VStack {
                    Spacer()
                    sendInviteButton
                        .padding(.horizontal, MADTheme.Spacing.lg)
                        .padding(.bottom, MADTheme.Spacing.lg)
                }
            }
            .navigationTitle("Challenge")
            .navigationBarTitleDisplayMode(.inline)
            // iOS 26: Liquid Glass is automatic - no toolbar modifiers needed
            .sheet(isPresented: $showFriendPicker) {
                friendPickerSheet
            }
            .sheet(isPresented: $showTypeSelector) {
                typeSelectorSheet
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("Challenge Created!", isPresented: $showSuccess) {
                Button("View Lobby") {
                    dismiss()
                }
            } message: {
                if failedInviteCount > 0 {
                    Text("Competition created, but \(failedInviteCount) invite\(failedInviteCount == 1 ? "" : "s") failed to send. You can invite friends from the lobby.")
                } else {
                    Text("Your competition is ready! Waiting for friends to accept.")
                }
            }
            .task {
                // Load friends when view appears
                do {
                    try await friendService.loadFriends()
                } catch {
                    print("Failed to load friends: \(error)")
                }
            }
            .onChange(of: selectedType) { _, newType in
                // Reset to sensible defaults for each type
                switch newType {
                case .streaks:
                    firstTo = 1           // Default: first miss = lose
                    goal = 1.0            // 1 mile daily minimum
                    interval = .day       // Always daily for streaks
                    hasEndDate = false
                case .clash:
                    firstTo = 5           // First to 5 points
                    interval = .day       // Daily matchups
                    hasEndDate = false
                case .apex:
                    interval = .day
                    durationHours = 168   // 1 week default
                    hasEndDate = true
                    isCustomDuration = false
                case .targets:
                    goal = 1.0
                    interval = .day
                    durationHours = 168   // 1 week default
                    hasEndDate = true
                    isCustomDuration = false
                case .race:
                    goal = 26.2           // Marathon
                    hasEndDate = false
                }
            }
        }
    }

    // MARK: - Challengers Section

    var challengersSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            HStack {
                Text("Challengers")
                    .font(MADTheme.Typography.subheadline)
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                Button {
                    showFriendPicker = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, MADTheme.Spacing.sm)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MADTheme.Spacing.md) {
                    // Add challenger button
                    Button {
                        showFriendPicker = true
                    } label: {
                        VStack(spacing: MADTheme.Spacing.sm) {
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 70, height: 70)

                                Circle()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                                    .frame(width: 70, height: 70)

                                Image(systemName: "plus")
                                    .font(.title2)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .frame(width: 80, height: 80) // Extra space for proper alignment

                            Text("Add")
                                .font(MADTheme.Typography.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .buttonStyle(ScaleButtonStyle())

                    // Selected friends
                    ForEach(Array(selectedFriends), id: \.user_id) { friend in
                        VStack(spacing: MADTheme.Spacing.sm) {
                            ZStack(alignment: .topTrailing) {
                                // Avatar circle
                                ZStack {
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .frame(width: 70, height: 70)

                                    Circle()
                                        .stroke(MADTheme.Colors.primary, lineWidth: 2)
                                        .frame(width: 70, height: 70)

                                    // Friend initial
                                    Text(friend.displayName.prefix(1).uppercased())
                                        .font(MADTheme.Typography.title2)
                                        .foregroundColor(.white)
                                }

                                // Remove button - positioned outside the circle
                                Button {
                                    selectedFriends.remove(friend)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(MADTheme.Colors.primary)
                                        .background(
                                            Circle()
                                                .fill(.white)
                                                .frame(width: 20, height: 20)
                                        )
                                }
                                .offset(x: 5, y: 0)
                            }
                            .frame(width: 80, height: 80) // Extra space to prevent cutoff
                            .padding(.top, 4) // Extra padding at top

                            Text(friend.displayName)
                                .font(MADTheme.Typography.caption)
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .frame(width: 74)
                                .truncationMode(.tail)
                        }
                    }
                }
                .padding(.horizontal, MADTheme.Spacing.sm)
            }
        }
    }

    // MARK: - Competition Type Section

    var competitionTypeSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text("Competition Type")
                .font(MADTheme.Typography.subheadline)
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, MADTheme.Spacing.sm)

            Button {
                showTypeSelector = true
            } label: {
                HStack(spacing: MADTheme.Spacing.md) {
                    // Type icon
                    Image(systemName: selectedType.icon)
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: selectedType.gradient.map { Color(hex: $0) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Color(hex: selectedType.gradient[0]).opacity(0.15))
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedType.displayName)
                            .font(MADTheme.Typography.headline)
                            .foregroundColor(.white)

                        Text(selectedType.description)
                            .font(MADTheme.Typography.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(2)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(MADTheme.Spacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.horizontal, MADTheme.Spacing.sm)
        }
    }

    // MARK: - Activity Selection Section

    var activitySelectionSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text("Allowed Activities")
                .font(MADTheme.Typography.subheadline)
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, MADTheme.Spacing.sm)

            HStack(spacing: MADTheme.Spacing.md) {
                ForEach(CompetitionActivity.allCases, id: \.self) { activity in
                    ActivityToggle(
                        activity: activity,
                        isSelected: selectedWorkouts.contains(activity),
                        action: {
                            if selectedWorkouts.contains(activity) {
                                if selectedWorkouts.count > 1 {
                                    selectedWorkouts.remove(activity)
                                }
                            } else {
                                selectedWorkouts.insert(activity)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, MADTheme.Spacing.sm)
        }
    }

    // MARK: - Unit Only Section (for Clash)

    var unitOnlySection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Distance Unit")
                    .font(MADTheme.Typography.subheadline)
                    .foregroundColor(.white.opacity(0.6))

                Text(unitOnlyDescription)
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, MADTheme.Spacing.sm)

            HStack(spacing: MADTheme.Spacing.sm) {
                ForEach([CompetitionUnit.miles, CompetitionUnit.kilometers, CompetitionUnit.steps], id: \.self) { unitOption in
                    Button {
                        unit = unitOption
                    } label: {
                        Text(unitOption == .steps ? "Steps" : unitOption.rawValue.capitalized)
                            .font(MADTheme.Typography.callout)
                            .fontWeight(unit == unitOption ? .semibold : .regular)
                            .foregroundColor(unit == unitOption ? .white : .white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, MADTheme.Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                    .fill(unit == unitOption ? MADTheme.Colors.primary.opacity(0.3) : Color.white.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                    .stroke(
                                        unit == unitOption ? MADTheme.Colors.primary : Color.white.opacity(0.1),
                                        lineWidth: unit == unitOption ? 2 : 1
                                    )
                            )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.horizontal, MADTheme.Spacing.sm)
        }
    }

    // MARK: - Goal Selection Section

    var goalSelectionSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(goalLabel)
                    .font(MADTheme.Typography.subheadline)
                    .foregroundColor(.white.opacity(0.6))

                Text(goalDescription)
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, MADTheme.Spacing.sm)

            VStack(spacing: MADTheme.Spacing.lg) {
                // Unit selector
                HStack(spacing: MADTheme.Spacing.sm) {
                    ForEach([CompetitionUnit.miles, CompetitionUnit.kilometers, CompetitionUnit.steps], id: \.self) { unitOption in
                        Button {
                            unit = unitOption
                        } label: {
                            Text(unitOption == .steps ? "Steps" : unitOption.rawValue.capitalized)
                                .font(MADTheme.Typography.callout)
                                .fontWeight(unit == unitOption ? .semibold : .regular)
                                .foregroundColor(unit == unitOption ? .white : .white.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, MADTheme.Spacing.sm)
                                .background(
                                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                        .fill(unit == unitOption ? MADTheme.Colors.primary.opacity(0.3) : Color.white.opacity(0.05))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                        .stroke(
                                            unit == unitOption ? MADTheme.Colors.primary : Color.white.opacity(0.1),
                                            lineWidth: unit == unitOption ? 2 : 1
                                        )
                                )
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                .padding(.horizontal, MADTheme.Spacing.sm)

                // Goal picker with +/- buttons
                HStack(spacing: MADTheme.Spacing.xl) {
                    // Minus button
                    Button {
                        if goal > 1 {
                            goal -= 1
                        }
                    } label: {
                        Image(systemName: "minus")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(ScaleButtonStyle())

                    Spacer()

                    // Goal display with text input
                    VStack(spacing: 8) {
                        TextField("", value: $goal, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(minWidth: 100)
                            .fixedSize(horizontal: true, vertical: false)
                            .onChange(of: goal) { oldValue, newValue in
                                // Ensure minimum value of 0.1
                                if newValue < 0.1 {
                                    goal = 0.1
                                }
                            }

                        Text(unit.shortDisplayName)
                            .font(MADTheme.Typography.title2)
                            .foregroundColor(.white.opacity(0.7))
                    }

                    Spacer()

                    // Plus button
                    Button {
                        goal += 1
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                .padding(.horizontal, MADTheme.Spacing.sm)

                // Friend's best
                if let friend = firstSelectedFriend {
                    Text("\(friend.displayName)'s best  \(String(format: "%.0f", friendBestDistance)) \(unit.shortDisplayName)")
                        .font(MADTheme.Typography.callout)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(.vertical, MADTheme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .padding(.horizontal, MADTheme.Spacing.sm)
        }
    }

    // MARK: - Duration Section

    var durationSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Competition Length")
                    .font(MADTheme.Typography.subheadline)
                    .foregroundColor(.white.opacity(0.6))

                Text(hasEndDate ? "Choose when the challenge ends" : "Competition runs until manually ended")
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, MADTheme.Spacing.sm)

            VStack(spacing: MADTheme.Spacing.md) {
                // Quick presets
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: MADTheme.Spacing.md) {
                    DurationPreset(
                        title: "1 Day",
                        hours: 24,
                        icon: "sun.max.fill",
                        isSelected: hasEndDate && !isCustomDuration && durationHours == 24,
                        action: {
                            hasEndDate = true
                            isCustomDuration = false
                            durationHours = 24
                        }
                    )

                    DurationPreset(
                        title: "3 Days",
                        hours: 72,
                        icon: "calendar",
                        isSelected: hasEndDate && !isCustomDuration && durationHours == 72,
                        action: {
                            hasEndDate = true
                            isCustomDuration = false
                            durationHours = 72
                        }
                    )

                    DurationPreset(
                        title: "1 Week",
                        hours: 168,
                        icon: "calendar.badge.clock",
                        isSelected: hasEndDate && !isCustomDuration && durationHours == 168,
                        action: {
                            hasEndDate = true
                            isCustomDuration = false
                            durationHours = 168
                        }
                    )

                    DurationPreset(
                        title: "Pick Date",
                        hours: 0,
                        icon: "calendar.circle",
                        isSelected: hasEndDate && isCustomDuration,
                        action: {
                            hasEndDate = true
                            isCustomDuration = true
                        }
                    )

                    // No "No End" option - Apex and Targets always have a fixed duration
                }

                // Custom date picker
                if isCustomDuration && hasEndDate {
                    VStack(spacing: MADTheme.Spacing.md) {
                        Text("Tap to select end date")
                            .font(MADTheme.Typography.caption)
                            .foregroundColor(.white.opacity(0.6))

                        DatePicker(
                            "",
                            selection: $customEndDate,
                            in: Date()...,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.graphical)
                        .tint(MADTheme.Colors.primary)
                        .colorScheme(.dark)
                        .padding(MADTheme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        )
                        .onChange(of: customEndDate) { _, newDate in
                            // Total elapsed hours between now and selected end date
                            let now = Date()
                            let totalSeconds = newDate.timeIntervalSince(now)
                            let hours = Int(totalSeconds / 3600)
                            durationHours = max(24, hours)
                        }

                        // Show calculated duration
                        let days = Calendar.current.dateComponents([.day], from: Date(), to: customEndDate).day ?? 1
                        Text("\(max(1, days)) day\(max(1, days) == 1 ? "" : "s") from now")
                            .font(MADTheme.Typography.callout)
                            .foregroundColor(MADTheme.Colors.primary)
                            .padding(.horizontal, MADTheme.Spacing.md)
                            .padding(.vertical, MADTheme.Spacing.sm)
                            .background(
                                Capsule()
                                    .fill(MADTheme.Colors.primary.opacity(0.2))
                            )
                    }
                }
            }
            .padding(.horizontal, MADTheme.Spacing.sm)
        }
    }

    // MARK: - Interval Section

    var intervalSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Scoring Interval")
                    .font(MADTheme.Typography.subheadline)
                    .foregroundColor(.white.opacity(0.6))

                Text("How often to tally points or progress")
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, MADTheme.Spacing.sm)

            HStack(spacing: MADTheme.Spacing.md) {
                ForEach(CompetitionInterval.allCases, id: \.self) { intervalOption in
                    IntervalOptionButton(
                        interval: intervalOption,
                        isSelected: interval == intervalOption,
                        action: { interval = intervalOption }
                    )
                }
            }
            .padding(.horizontal, MADTheme.Spacing.sm)
        }
    }

    // MARK: - First To Section

    var firstToSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedType == .streaks ? "Breaks to Lose" : "Points to Win")
                    .font(MADTheme.Typography.subheadline)
                    .foregroundColor(.white.opacity(0.6))

                Text(selectedType == .streaks
                    ? (firstTo == 1 ? "Miss one day and you're out" : "Miss \(firstTo) days and you're out")
                    : "First to reach this score wins")
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, MADTheme.Spacing.sm)

            HStack(spacing: MADTheme.Spacing.xl) {
                // Minus button
                Button {
                    if firstTo > 1 {
                        firstTo -= 1
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(ScaleButtonStyle())

                Spacer()

                // Value display with text input
                TextField("", value: $firstTo, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(minWidth: 80)
                    .onChange(of: firstTo) { oldValue, newValue in
                        // Ensure minimum value of 1
                        if newValue < 1 {
                            firstTo = 1
                        }
                    }

                Spacer()

                // Plus button
                Button {
                    firstTo += 1
                } label: {
                    Image(systemName: "plus")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .padding(MADTheme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .padding(.horizontal, MADTheme.Spacing.sm)
        }
    }

    // MARK: - Send Invite Button

    var sendInviteButton: some View {
        Button {
            createCompetition()
        } label: {
            HStack(spacing: MADTheme.Spacing.md) {
                if isCreating {
                    ProgressView()
                        .tint(.black)
                } else {
                    Image(systemName: "trophy.fill")
                        .foregroundColor(.black)
                }

                Text("Create Challenge")
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(.black)

                Spacer()

                if selectedFriends.count > 0 {
                    Text("\(selectedFriends.count) challenger\(selectedFriends.count == 1 ? "" : "s")")
                        .font(MADTheme.Typography.callout)
                        .foregroundColor(.black.opacity(0.6))
                }

                Image(systemName: "arrow.right.circle.fill")
                    .foregroundColor(.black)
            }
            .padding(MADTheme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(Color.white)
            )
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        }
        .disabled(!canCreate || isCreating)
        .opacity((canCreate && !isCreating) ? 1.0 : 0.6)
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Friend Picker Sheet

    var friendPickerSheet: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient
                    .ignoresSafeArea()

                if friendService.friends.isEmpty {
                    VStack(spacing: MADTheme.Spacing.lg) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 50))
                            .foregroundColor(.white.opacity(0.3))

                        Text("No Friends Yet")
                            .font(MADTheme.Typography.title2)
                            .foregroundColor(.white)

                        Text("Add friends to challenge them")
                            .font(MADTheme.Typography.callout)
                            .foregroundColor(.white.opacity(0.7))
                    }
                } else {
                    ScrollView {
                        VStack(spacing: MADTheme.Spacing.md) {
                            ForEach(friendService.friends) { friend in
                                FriendSelectRow(
                                    friend: friend,
                                    isSelected: selectedFriends.contains(friend),
                                    action: {
                                        if selectedFriends.contains(friend) {
                                            selectedFriends.remove(friend)
                                        } else {
                                            selectedFriends.insert(friend)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(MADTheme.Spacing.lg)
                    }
                }
            }
            .navigationTitle("Select Friends")
            .navigationBarTitleDisplayMode(.inline)
            // iOS 26: Liquid Glass is automatic - no toolbar modifiers needed
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showFriendPicker = false
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }

    // MARK: - Type Selector Sheet

    var typeSelectorSheet: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: MADTheme.Spacing.lg) {
                        ForEach(CompetitionType.allCases, id: \.self) { type in
                            CompetitionTypeCard(
                                type: type,
                                isSelected: selectedType == type,
                                action: {
                                    selectedType = type
                                    showTypeSelector = false
                                }
                            )
                        }
                    }
                    .padding(MADTheme.Spacing.lg)
                }
            }
            .navigationTitle("Competition Type")
            .navigationBarTitleDisplayMode(.inline)
            // iOS 26: Liquid Glass is automatic - no toolbar modifiers needed
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        showTypeSelector = false
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }

    // MARK: - Helper Functions

    func getCurrentDayName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: Date())
    }

    func getCurrentDayNumber() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: Date())
    }

    // MARK: - Actions

    func createCompetition() {
        guard !selectedFriends.isEmpty else {
            errorMessage = "Please select at least one friend to challenge"
            showError = true
            return
        }

        isCreating = true

        // Generate competition name based on type and participants
        let friendNames = selectedFriends.prefix(2).map { $0.displayName }.joined(separator: " & ")
        let autoName = "\(selectedType.displayName) with \(friendNames)"

        // Calculate duration_hours from the UI selection
        // Only Apex and Targets have fixed durations; others end by condition
        let computedDurationHours: Int?
        if !needsDuration {
            computedDurationHours = nil  // Streaks, Clash, Race end by condition
        } else if isCustomDuration {
            let totalSeconds = customEndDate.timeIntervalSince(Date())
            let hours = Int(totalSeconds / 3600)
            computedDurationHours = max(24, hours)
        } else {
            computedDurationHours = durationHours
        }

        Task {
            do {
                let competitionId = try await competitionService.createCompetition(
                    name: competitionName.isEmpty ? autoName : competitionName,
                    type: selectedType,
                    workouts: Array(selectedWorkouts),
                    goal: needsGoal ? goal : 0,
                    unit: unit,
                    firstTo: firstTo,
                    history: false,
                    interval: interval,
                    durationHours: computedDurationHours
                )

                // Invite all selected friends
                var inviteFailures = 0
                for friend in selectedFriends {
                    do {
                        print("[CreateCompetition] Inviting \(friend.displayName) (\(friend.user_id))")
                        try await competitionService.inviteUser(
                            competitionId: competitionId,
                            userId: friend.user_id
                        )
                        print("[CreateCompetition] Successfully invited \(friend.displayName)")
                    } catch {
                        inviteFailures += 1
                        print("[CreateCompetition] Failed to invite \(friend.displayName): \(error.localizedDescription)")
                    }
                }

                await MainActor.run {
                    isCreating = false
                    failedInviteCount = inviteFailures
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

// MARK: - Supporting Components

struct CompactTypeButton: View {
    let icon: String
    let label: String
    let iconColor: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(isSelected ? iconColor : .white.opacity(0.6))

                Text(label)
                    .font(MADTheme.Typography.callout)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? .white : .white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, MADTheme.Spacing.md)
            .padding(.horizontal, MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(isSelected ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .stroke(
                        isSelected ? iconColor.opacity(0.5) : Color.white.opacity(0.1),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

struct FriendSelectRow: View {
    let friend: BackendUser
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: MADTheme.Spacing.md) {
                // Friend avatar
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(friend.displayName.prefix(1).uppercased())
                            .font(MADTheme.Typography.headline)
                            .foregroundColor(.white)
                    )
                    .overlay(
                        Circle()
                            .stroke(isSelected ? MADTheme.Colors.primary : Color.white.opacity(0.2), lineWidth: 2)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.displayName)
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(.white)

                    if let username = friend.username {
                        Text("@\(username)")
                            .font(MADTheme.Typography.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(MADTheme.Colors.primary)
                } else {
                    Image(systemName: "circle")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .stroke(
                                isSelected ? MADTheme.Colors.primary.opacity(0.5) : Color.white.opacity(0.1),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Custom Text Field Style

struct MADTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .foregroundColor(.white)
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
    }
}

// MARK: - Duration Preset Component

struct DurationPreset: View {
    let title: String
    let hours: Int
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? MADTheme.Colors.primary : .white.opacity(0.6))

                Text(title)
                    .font(MADTheme.Typography.callout)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, MADTheme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(isSelected ? MADTheme.Colors.primary.opacity(0.2) : Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .stroke(
                        isSelected ? MADTheme.Colors.primary : Color.white.opacity(0.1),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Interval Option Button

struct IntervalOptionButton: View {
    let interval: CompetitionInterval
    let isSelected: Bool
    let action: () -> Void

    var icon: String {
        switch interval {
        case .day:
            return "calendar.day.timeline.left"
        case .week:
            return "calendar.badge.clock"
        case .month:
            return "calendar"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(isSelected ? MADTheme.Colors.primary : .white.opacity(0.6))

                Text(interval.displayName)
                    .font(MADTheme.Typography.callout)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, MADTheme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(isSelected ? MADTheme.Colors.primary.opacity(0.2) : Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .stroke(
                        isSelected ? MADTheme.Colors.primary : Color.white.opacity(0.1),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

#Preview {
    CreateCompetitionView()
}

