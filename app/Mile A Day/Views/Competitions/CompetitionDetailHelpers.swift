import SwiftUI

// MARK: - Info Row
struct InfoRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(MADTheme.Colors.madRed)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.white.opacity(0.7))

                Text(value)
                    .font(MADTheme.Typography.callout)
                    .foregroundColor(.white)
            }

            Spacer()
        }
    }
}

// MARK: - Invite Friend View
struct InviteFriendView: View {
    let competition: Competition
    @ObservedObject var competitionService: CompetitionService
    @ObservedObject var friendService: FriendService
    @Environment(\.dismiss) var dismiss

    @State private var searchText = ""
    @State private var isInviting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false

    var filteredFriends: [BackendUser] {
        if searchText.isEmpty {
            return friendService.friends.filter { friend in
                !competition.users.contains { $0.user_id == friend.user_id }
            }
        } else {
            return friendService.friends.filter { friend in
                !competition.users.contains { $0.user_id == friend.user_id } &&
                (friend.username?.lowercased().contains(searchText.lowercased()) ?? false ||
                 friend.displayName.lowercased().contains(searchText.lowercased()))
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient
                    .ignoresSafeArea(.all)

                VStack(spacing: 0) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.5))

                        TextField("Search friends...", text: $searchText)
                            .foregroundColor(.white)
                    }
                    .padding(MADTheme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .fill(.ultraThinMaterial)
                    )
                    .padding(MADTheme.Spacing.md)

                    // Friends list
                    if filteredFriends.isEmpty {
                        VStack(spacing: MADTheme.Spacing.md) {
                            Image(systemName: "person.2.slash")
                                .font(.system(size: 50))
                                .foregroundColor(.white.opacity(0.5))

                            Text(searchText.isEmpty ? "All friends are already invited" : "No friends found")
                                .font(MADTheme.Typography.body)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: MADTheme.Spacing.sm) {
                                ForEach(filteredFriends) { friend in
                                    FriendInviteRow(
                                        friend: friend,
                                        onInvite: {
                                            inviteFriend(friend)
                                        }
                                    )
                                }
                            }
                            .padding(MADTheme.Spacing.md)
                        }
                    }
                }
            }
            .navigationTitle("Invite Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("Success!", isPresented: $showSuccess) {
                Button("OK") { }
            } message: {
                Text("Friend invited successfully!")
            }
        }
    }

    private func inviteFriend(_ friend: BackendUser) {
        isInviting = true

        Task {
            do {
                try await competitionService.inviteUser(
                    competitionId: competition.competition_id,
                    userId: friend.user_id
                )

                await MainActor.run {
                    isInviting = false
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    isInviting = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

// MARK: - Friend Invite Row
struct FriendInviteRow: View {
    let friend: BackendUser
    let onInvite: () -> Void

    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            // Avatar
            Circle()
                .fill(MADTheme.Colors.primaryGradient)
                .frame(width: 50, height: 50)
                .overlay(
                    Text(friend.displayName.prefix(1).uppercased())
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName)
                    .font(MADTheme.Typography.callout)
                    .foregroundColor(.white)

                if let username = friend.username {
                    Text("@\(username)")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            Spacer()

            Button(action: onInvite) {
                Text("Invite")
                    .font(MADTheme.Typography.callout)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, MADTheme.Spacing.lg)
                    .padding(.vertical, MADTheme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.pill)
                            .fill(MADTheme.Colors.primaryGradient)
                    )
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Flex/Nudge Tracker
struct FlexNudgeTracker {
    private static let flexPrefix = "flex_sent_"
    private static let nudgePrefix = "nudge_sent_"

    static func hasSentFlexToday(competitionId: String) -> Bool {
        UserDefaults.standard.bool(forKey: flexPrefix + competitionId + "_" + todayKey())
    }

    static func markFlexSent(competitionId: String) {
        UserDefaults.standard.set(true, forKey: flexPrefix + competitionId + "_" + todayKey())
    }

    static func hasSentNudgeToday(competitionId: String, targetUserId: String) -> Bool {
        UserDefaults.standard.bool(forKey: nudgePrefix + competitionId + "_" + targetUserId + "_" + todayKey())
    }

    static func markNudgeSent(competitionId: String, targetUserId: String) {
        UserDefaults.standard.set(true, forKey: nudgePrefix + competitionId + "_" + targetUserId + "_" + todayKey())
    }

    private static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

// MARK: - Action Feedback
struct ActionFeedback: Equatable {
    let icon: String
    let message: String
    let isError: Bool
}

// MARK: - Counting Text (Animatable number display)
struct CountingText: View, Animatable {
    var value: Double
    let format: String
    let suffix: String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(String(format: format, value) + suffix)
    }
}

// MARK: - Edit Competition Settings View
struct EditCompetitionSettingsView: View {
    @Binding var competition: Competition
    @ObservedObject var competitionService: CompetitionService
    @Environment(\.dismiss) var dismiss

    // Editable fields initialized from competition
    @State private var name: String = ""
    @State private var goal: Double = 1.0
    @State private var unit: CompetitionUnit = .miles
    @State private var interval: CompetitionInterval = .day
    @State private var firstTo: Int = 5
    @State private var durationHours: Int? = nil
    @State private var selectedWorkouts: Set<CompetitionActivity> = [.run]

    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""

    private var needsGoal: Bool {
        competition.type != .clash && competition.type != .apex
    }

    private var needsInterval: Bool {
        competition.type == .apex || competition.type == .targets || competition.type == .clash
    }

    private var needsFirstTo: Bool {
        competition.type == .streaks || competition.type == .clash
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient
                    .ignoresSafeArea(.all)

                ScrollView {
                    VStack(spacing: MADTheme.Spacing.xl) {
                        // Competition Name
                        settingsGroup(title: "Competition Name") {
                            TextField("Competition name", text: $name)
                                .foregroundColor(.white)
                                .font(MADTheme.Typography.body)
                                .padding(MADTheme.Spacing.md)
                                .background(
                                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                        .fill(Color.white.opacity(0.08))
                                )
                        }

                        // Goal (not for Clash)
                        if needsGoal {
                            settingsGroup(title: "Goal") {
                                HStack(spacing: MADTheme.Spacing.lg) {
                                    Button {
                                        if goal > 1 { goal -= 1 }
                                    } label: {
                                        Image(systemName: "minus")
                                            .font(.title3)
                                            .foregroundColor(.white)
                                            .frame(width: 40, height: 40)
                                            .background(Circle().fill(Color.white.opacity(0.1)))
                                    }

                                    TextField("", value: $goal, format: .number)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.center)
                                        .font(.system(size: 36, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .frame(minWidth: 80)

                                    Button {
                                        goal += 1
                                    } label: {
                                        Image(systemName: "plus")
                                            .font(.title3)
                                            .foregroundColor(.white)
                                            .frame(width: 40, height: 40)
                                            .background(Circle().fill(Color.white.opacity(0.1)))
                                    }
                                }

                                // Unit selector
                                HStack(spacing: MADTheme.Spacing.sm) {
                                    ForEach([CompetitionUnit.miles, .kilometers, .steps], id: \.self) { u in
                                        Button {
                                            unit = u
                                        } label: {
                                            Text(u == .steps ? "Steps" : u.rawValue.capitalized)
                                                .font(MADTheme.Typography.callout)
                                                .fontWeight(unit == u ? .semibold : .regular)
                                                .foregroundColor(unit == u ? .white : .white.opacity(0.5))
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, MADTheme.Spacing.sm)
                                                .background(
                                                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                                        .fill(unit == u ? MADTheme.Colors.primary.opacity(0.3) : Color.white.opacity(0.05))
                                                )
                                        }
                                    }
                                }
                            }
                        } else {
                            // Unit only for Clash
                            settingsGroup(title: "Distance Unit") {
                                HStack(spacing: MADTheme.Spacing.sm) {
                                    ForEach([CompetitionUnit.miles, .kilometers, .steps], id: \.self) { u in
                                        Button {
                                            unit = u
                                        } label: {
                                            Text(u == .steps ? "Steps" : u.rawValue.capitalized)
                                                .font(MADTheme.Typography.callout)
                                                .fontWeight(unit == u ? .semibold : .regular)
                                                .foregroundColor(unit == u ? .white : .white.opacity(0.5))
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, MADTheme.Spacing.sm)
                                                .background(
                                                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                                        .fill(unit == u ? MADTheme.Colors.primary.opacity(0.3) : Color.white.opacity(0.05))
                                                )
                                        }
                                    }
                                }
                            }
                        }

                        // Interval
                        if needsInterval {
                            settingsGroup(title: "Scoring Interval") {
                                HStack(spacing: MADTheme.Spacing.sm) {
                                    ForEach(CompetitionInterval.allCases, id: \.self) { i in
                                        Button {
                                            interval = i
                                        } label: {
                                            Text(i.displayName)
                                                .font(MADTheme.Typography.callout)
                                                .fontWeight(interval == i ? .semibold : .regular)
                                                .foregroundColor(interval == i ? .white : .white.opacity(0.5))
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, MADTheme.Spacing.sm)
                                                .background(
                                                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                                        .fill(interval == i ? MADTheme.Colors.primary.opacity(0.3) : Color.white.opacity(0.05))
                                                )
                                        }
                                    }
                                }
                            }
                        }

                        // First To
                        if needsFirstTo {
                            settingsGroup(title: competition.type == .streaks ? "Breaks to Lose" : "Points to Win") {
                                HStack(spacing: MADTheme.Spacing.lg) {
                                    Button {
                                        if firstTo > 1 { firstTo -= 1 }
                                    } label: {
                                        Image(systemName: "minus")
                                            .font(.title3)
                                            .foregroundColor(.white)
                                            .frame(width: 40, height: 40)
                                            .background(Circle().fill(Color.white.opacity(0.1)))
                                    }

                                    Text("\(firstTo)")
                                        .font(.system(size: 36, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .frame(minWidth: 60)

                                    Button {
                                        firstTo += 1
                                    } label: {
                                        Image(systemName: "plus")
                                            .font(.title3)
                                            .foregroundColor(.white)
                                            .frame(width: 40, height: 40)
                                            .background(Circle().fill(Color.white.opacity(0.1)))
                                    }
                                }
                            }
                        }

                        // Activities
                        settingsGroup(title: "Allowed Activities") {
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
                        }

                        Spacer(minLength: MADTheme.Spacing.xxl)
                    }
                    .padding(MADTheme.Spacing.lg)
                }
            }
            .navigationTitle("Edit Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        saveSettings()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                                .foregroundColor(MADTheme.Colors.madRed)
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                // Initialize state from current competition
                name = competition.competition_name
                goal = competition.options.goal
                unit = competition.options.unit
                interval = competition.options.interval ?? .day
                firstTo = competition.options.first_to
                durationHours = competition.options.duration_hours
                selectedWorkouts = Set(competition.workouts)
            }
        }
    }

    private func settingsGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text(title)
                .font(MADTheme.Typography.subheadline)
                .foregroundColor(.white.opacity(0.6))

            content()
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

    private func saveSettings() {
        isSaving = true
        Task {
            do {
                let updated = try await competitionService.updateCompetition(
                    id: competition.competition_id,
                    name: name,
                    workouts: Array(selectedWorkouts),
                    goal: goal,
                    unit: unit,
                    firstTo: firstTo,
                    history: false,
                    interval: interval
                )
                await MainActor.run {
                    competition = updated
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

// MARK: - Competition Confetti View
struct CompetitionConfettiView: View {
    @State private var animate = false
    private let colors: [Color] = [.yellow, .orange, .red, .green, .blue, .purple, .white, .yellow, .orange]
    private let particleCount = 30

    var body: some View {
        ZStack {
            ForEach(0..<particleCount, id: \.self) { i in
                confettiPiece(index: i)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 2.5)) {
                animate = true
            }
        }
    }

    private func confettiPiece(index: Int) -> some View {
        let angle = Double(index) * (360.0 / Double(particleCount)) + Double(index * 37 % 40) - 20
        let distance: CGFloat = 80 + CGFloat(index * 17 % 140)
        let rotationAmount = Double(index * 73 % 720)
        let pieceWidth: CGFloat = 4 + CGFloat(index * 3 % 5)
        let delay = Double(index) * 0.03

        return RoundedRectangle(cornerRadius: 1)
            .fill(colors[index % colors.count])
            .frame(width: pieceWidth, height: pieceWidth * 2.5)
            .rotationEffect(.degrees(animate ? rotationAmount : 0))
            .offset(
                x: animate ? cos(angle * .pi / 180) * distance : 0,
                y: animate ? sin(angle * .pi / 180) * distance + 40 : -30
            )
            .opacity(animate ? 0 : 1)
            .scaleEffect(animate ? 0.3 : 1)
            .animation(.easeOut(duration: 2.0).delay(delay), value: animate)
    }
}

#Preview {
    NavigationStack {
        CompetitionDetailView(
            competition: Competition(
                competition_id: "test123",
                competition_name: "Summer Challenge",
                start_date: nil,
                end_date: nil,
                workouts: [.run],
                type: .streaks,
                options: CompetitionOptions(
                    goal: 1.0,
                    unit: .miles,
                    first_to: 5,
                    history: false,
                    interval: .day,
                    duration_hours: 168
                ),
                owner: "peter",
                users: [
                    CompetitionUser(
                        competition_id: "test123",
                        user_id: "peter",
                        invite_status: .accepted,
                        username: "peter",
                        score: nil,
                        intervals: nil
                    ),
                    CompetitionUser(
                        competition_id: "test123",
                        user_id: "mary",
                        invite_status: .pending,
                        username: "mj",
                        score: nil,
                        intervals: nil
                    )
                ]
            ),
            competitionService: CompetitionService()
        )
    }
}
