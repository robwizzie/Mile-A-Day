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
    @State private var selectedWorkouts: Set<CompetitionActivity> = [.run]
    @State private var firstTo: Int = 5
    @State private var interval: CompetitionInterval = .day
    @State private var includeHistory = false

    // UI state
    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    @State private var showFriendPicker = false
    @State private var showTypeSelector = false

    var canCreate: Bool {
        !selectedFriends.isEmpty &&
        goal > 0
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
        case .apex:
            return "Total Distance Target"
        case .targets:
            return "Daily Goal to Score"
        case .clash:
            return "Daily Goal to Win Day"
        case .race:
            return "Total Distance to Win"
        }
    }

    var goalDescription: String {
        switch selectedType {
        case .streaks:
            return "Minimum distance to maintain streak each day"
        case .apex:
            return "Optional milestone distance for the competition"
        case .targets:
            return "Distance needed per interval to score a point"
        case .clash:
            return "Highest distance wins that day's point"
        case .race:
            return "First to reach this distance wins"
        }
    }

    var needsInterval: Bool {
        selectedType == .apex || selectedType == .targets || selectedType == .clash
    }

    var needsFirstTo: Bool {
        selectedType == .streaks || selectedType == .clash
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

                        // Goal Selection
                        goalSelectionSection

                        // Type-Specific Options
                        if needsInterval {
                            intervalSection
                        }

                        if needsFirstTo {
                            firstToSection
                        }

                        // Duration (not needed for race)
                        if selectedType != .race {
                            durationSection
                        }

                        // Historical Data Toggle
                        historyToggleSection

                        Spacer(minLength: MADTheme.Spacing.xxl)
                    }
                    .padding(.top, MADTheme.Spacing.md)
                    .padding(.bottom, MADTheme.Spacing.xl)
                }

                // Send Invite Button (Fixed at bottom)
                VStack {
                    Spacer()
                    sendInviteButton
                        .padding(.horizontal, MADTheme.Spacing.xl)
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
            .alert("Success!", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Your competition has been created successfully!")
            }
            .task {
                // Load friends when view appears
                do {
                    try await friendService.loadFriends()
                } catch {
                    print("Failed to load friends: \(error)")
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
            .padding(.horizontal, MADTheme.Spacing.xl)

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
                                .offset(x: 2, y: -2)
                            }
                            .frame(width: 74, height: 74)

                            Text(friend.displayName)
                                .font(MADTheme.Typography.caption)
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .frame(width: 74)
                                .truncationMode(.tail)
                        }
                    }
                }
                .padding(.horizontal, MADTheme.Spacing.xl)
            }
        }
    }

    // MARK: - Competition Type Section

    var competitionTypeSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text("Competition Type")
                .font(MADTheme.Typography.subheadline)
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, MADTheme.Spacing.xl)

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
            .padding(.horizontal, MADTheme.Spacing.xl)
        }
    }

    // MARK: - Activity Selection Section

    var activitySelectionSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text("Allowed Activities")
                .font(MADTheme.Typography.subheadline)
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, MADTheme.Spacing.xl)

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
            .padding(.horizontal, MADTheme.Spacing.xl)
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
            .padding(.horizontal, MADTheme.Spacing.xl)

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
                .padding(.horizontal, MADTheme.Spacing.xl)

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

                    // Goal display
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.0f", goal))
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .fixedSize()

                        Text(unit == .steps ? "k" : unit.rawValue)
                            .font(MADTheme.Typography.title2)
                            .foregroundColor(.white.opacity(0.7))
                            .fixedSize()
                    }
                    .fixedSize(horizontal: true, vertical: false)

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
                .padding(.horizontal, MADTheme.Spacing.xl)

                // Friend's best
                if let friend = firstSelectedFriend {
                    Text("\(friend.displayName)'s best  \(String(format: "%.0f", friendBestDistance))\(unit.rawValue)")
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
            .padding(.horizontal, MADTheme.Spacing.xl)
        }
    }

    // MARK: - Duration Section

    var durationSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Competition Length")
                    .font(MADTheme.Typography.subheadline)
                    .foregroundColor(.white.opacity(0.6))

                Text("How long the challenge will run")
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, MADTheme.Spacing.xl)

            VStack(spacing: MADTheme.Spacing.md) {
                // Quick presets
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: MADTheme.Spacing.md) {
                    DurationPreset(
                        title: "1 Day",
                        hours: 24,
                        icon: "sun.max.fill",
                        isSelected: !isCustomDuration && durationHours == 24,
                        action: {
                            isCustomDuration = false
                            durationHours = 24
                        }
                    )

                    DurationPreset(
                        title: "3 Days",
                        hours: 72,
                        icon: "calendar",
                        isSelected: !isCustomDuration && durationHours == 72,
                        action: {
                            isCustomDuration = false
                            durationHours = 72
                        }
                    )

                    DurationPreset(
                        title: "1 Week",
                        hours: 168,
                        icon: "calendar.badge.clock",
                        isSelected: !isCustomDuration && durationHours == 168,
                        action: {
                            isCustomDuration = false
                            durationHours = 168
                        }
                    )

                    DurationPreset(
                        title: "Custom",
                        hours: 0,
                        icon: "slider.horizontal.3",
                        isSelected: isCustomDuration,
                        action: {
                            isCustomDuration = true
                            durationHours = customDurationDays * 24
                        }
                    )
                }

                // Custom duration picker
                if isCustomDuration {
                    VStack(spacing: MADTheme.Spacing.md) {
                        Text("Enter custom duration")
                            .font(MADTheme.Typography.caption)
                            .foregroundColor(.white.opacity(0.6))

                        HStack(spacing: MADTheme.Spacing.xl) {
                            // Minus button
                            Button {
                                if customDurationDays > 1 {
                                    customDurationDays -= 1
                                    durationHours = customDurationDays * 24
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

                            // Days display
                            VStack(spacing: 4) {
                                Text("\(customDurationDays)")
                                    .font(.system(size: 48, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .fixedSize()

                                Text(customDurationDays == 1 ? "day" : "days")
                                    .font(MADTheme.Typography.callout)
                                    .foregroundColor(.white.opacity(0.7))
                            }

                            Spacer()

                            // Plus button
                            Button {
                                if customDurationDays < 90 {
                                    customDurationDays += 1
                                    durationHours = customDurationDays * 24
                                }
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
                    }
                }
            }
            .padding(.horizontal, MADTheme.Spacing.xl)
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
            .padding(.horizontal, MADTheme.Spacing.xl)

            HStack(spacing: MADTheme.Spacing.md) {
                ForEach(CompetitionInterval.allCases, id: \.self) { intervalOption in
                    IntervalOptionButton(
                        interval: intervalOption,
                        isSelected: interval == intervalOption,
                        action: { interval = intervalOption }
                    )
                }
            }
            .padding(.horizontal, MADTheme.Spacing.xl)
        }
    }

    // MARK: - First To Section

    var firstToSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedType == .streaks ? "Breaks to Lose" : "Points to Win")
                    .font(MADTheme.Typography.subheadline)
                    .foregroundColor(.white.opacity(0.6))

                Text(selectedType == .streaks ? "First to break this many days loses" : "First to reach this score wins")
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, MADTheme.Spacing.xl)

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

                // Value display
                Text("\(firstTo)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .fixedSize()

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
            .padding(.horizontal, MADTheme.Spacing.xl)
        }
    }

    // MARK: - History Toggle Section

    var historyToggleSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            Toggle(isOn: $includeHistory) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Include Historical Data")
                        .font(MADTheme.Typography.callout)
                        .foregroundColor(.white)

                    Text("Start the competition with existing workout data from before the start date")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(MADTheme.Colors.primary)
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
        .padding(.horizontal, MADTheme.Spacing.xl)
    }

    // MARK: - Send Invite Button

    var sendInviteButton: some View {
        Button {
            createCompetition()
        } label: {
            HStack(spacing: MADTheme.Spacing.md) {
                Text("Send Invite to")
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(.black)

                if let friend = firstSelectedFriend {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(MADTheme.Colors.primary)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Text(friend.displayName.prefix(1).uppercased())
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            )

                        Text(friend.displayName)
                            .font(MADTheme.Typography.headline)
                            .foregroundColor(.black)
                    }
                } else {
                    Text("Select Friend")
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(.black.opacity(0.5))
                }

                Spacer()

                Image(systemName: "paperplane.fill")
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

        // Calculate end date based on duration
        let startDate = Date()
        let endDate = Calendar.current.date(byAdding: .hour, value: durationHours, to: startDate) ?? Date()

        Task {
            do {
                let competitionId = try await competitionService.createCompetition(
                    name: competitionName.isEmpty ? autoName : competitionName,
                    type: selectedType,
                    startDate: startDate,
                    endDate: endDate,
                    workouts: Array(selectedWorkouts),
                    goal: goal,
                    unit: unit,
                    firstTo: firstTo,
                    history: includeHistory,
                    interval: interval
                )

                // Invite all selected friends
                for friend in selectedFriends {
                    try? await competitionService.inviteUser(
                        competitionId: competitionId,
                        userId: friend.user_id
                    )
                }

                await MainActor.run {
                    isCreating = false
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

