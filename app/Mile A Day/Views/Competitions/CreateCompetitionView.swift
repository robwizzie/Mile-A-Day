import SwiftUI

struct CreateCompetitionView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var competitionService = CompetitionService()

    // Step management
    @State private var currentStep = 0

    // Form fields
    @State private var selectedType: CompetitionType?
    @State private var competitionName = ""
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var selectedWorkouts: Set<CompetitionActivity> = [.run]
    @State private var goal: String = "1"
    @State private var unit: CompetitionUnit = .miles
    @State private var firstTo: String = "5"
    @State private var interval: CompetitionInterval = .day
    @State private var includeHistory = false

    // UI state
    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false

    var canProceedStep1: Bool {
        selectedType != nil
    }

    var canProceedStep2: Bool {
        !competitionName.isEmpty &&
        endDate > startDate &&
        !selectedWorkouts.isEmpty &&
        !goal.isEmpty &&
        Double(goal) != nil &&
        !firstTo.isEmpty &&
        Int(firstTo) != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient
                    .ignoresSafeArea(.all)

                ScrollView {
                    VStack(spacing: MADTheme.Spacing.xl) {
                        // Progress indicator
                        HStack(spacing: MADTheme.Spacing.sm) {
                            ForEach(0..<2) { index in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(index <= currentStep ? MADTheme.Colors.primary : Color.white.opacity(0.3))
                                    .frame(height: 4)
                            }
                        }
                        .padding(.horizontal, MADTheme.Spacing.xl)
                        .padding(.top, MADTheme.Spacing.md)

                        // Step content
                        if currentStep == 0 {
                            step1SelectType
                        } else if currentStep == 1 {
                            step2ConfigureDetails
                        }

                        // Navigation buttons
                        navigationButtons
                    }
                    .padding(.bottom, MADTheme.Spacing.xl)
                }
            }
            .navigationTitle("Create Competition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackgroundVisibility(.automatic, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
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
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Your competition has been created successfully!")
            }
        }
    }

    // MARK: - Step 1: Select Type

    var step1SelectType: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
            Text("Choose Competition Type")
                .font(MADTheme.Typography.title2)
                .foregroundColor(.white)
                .padding(.horizontal, MADTheme.Spacing.xl)

            VStack(spacing: MADTheme.Spacing.md) {
                ForEach(CompetitionType.allCases, id: \.self) { type in
                    CompetitionTypeCard(
                        type: type,
                        isSelected: selectedType == type,
                        action: {
                            selectedType = type
                        }
                    )
                }
            }
            .padding(.horizontal, MADTheme.Spacing.xl)
        }
    }

    // MARK: - Step 2: Configure Details

    var step2ConfigureDetails: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
            Text("Competition Details")
                .font(MADTheme.Typography.title2)
                .foregroundColor(.white)
                .padding(.horizontal, MADTheme.Spacing.xl)

            VStack(spacing: MADTheme.Spacing.lg) {
                // Competition name
                VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                    Text("Name")
                        .font(MADTheme.Typography.subheadline)
                        .foregroundColor(.white.opacity(0.7))

                    TextField("Enter competition name", text: $competitionName)
                        .textFieldStyle(MADTextFieldStyle())
                }

                // Date range
                VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                    Text("Duration")
                        .font(MADTheme.Typography.subheadline)
                        .foregroundColor(.white.opacity(0.7))

                    HStack(spacing: MADTheme.Spacing.md) {
                        DatePicker("Start", selection: $startDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .accentColor(MADTheme.Colors.primary)
                            .frame(maxWidth: .infinity)
                            .padding(MADTheme.Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                    .fill(.ultraThinMaterial)
                            )

                        Image(systemName: "arrow.right")
                            .foregroundColor(.white.opacity(0.5))

                        DatePicker("End", selection: $endDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .accentColor(MADTheme.Colors.primary)
                            .frame(maxWidth: .infinity)
                            .padding(MADTheme.Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                    .fill(.ultraThinMaterial)
                            )
                    }
                }

                // Workout types
                VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                    Text("Allowed Activities")
                        .font(MADTheme.Typography.subheadline)
                        .foregroundColor(.white.opacity(0.7))

                    HStack(spacing: MADTheme.Spacing.md) {
                        ForEach(CompetitionActivity.allCases, id: \.self) { activity in
                            ActivityToggle(
                                activity: activity,
                                isSelected: selectedWorkouts.contains(activity),
                                action: {
                                    if selectedWorkouts.contains(activity) {
                                        selectedWorkouts.remove(activity)
                                    } else {
                                        selectedWorkouts.insert(activity)
                                    }
                                }
                            )
                        }
                    }
                }

                // Goal
                VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                    Text("Goal")
                        .font(MADTheme.Typography.subheadline)
                        .foregroundColor(.white.opacity(0.7))

                    HStack(spacing: MADTheme.Spacing.md) {
                        TextField("Amount", text: $goal)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(MADTextFieldStyle())
                            .frame(maxWidth: .infinity)

                        Picker("Unit", selection: $unit) {
                            ForEach(CompetitionUnit.allCases, id: \.self) { unit in
                                Text(unit.displayName).tag(unit)
                            }
                        }
                        .pickerStyle(.menu)
                        .accentColor(.white)
                        .padding(MADTheme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                .fill(.ultraThinMaterial)
                        )
                    }
                }

                // Interval (for apex, targets, clash)
                if selectedType == .apex || selectedType == .targets || selectedType == .clash {
                    VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                        Text("Scoring Interval")
                            .font(MADTheme.Typography.subheadline)
                            .foregroundColor(.white.opacity(0.7))

                        Picker("Interval", selection: $interval) {
                            ForEach(CompetitionInterval.allCases, id: \.self) { interval in
                                Text(interval.displayName).tag(interval)
                            }
                        }
                        .pickerStyle(.segmented)
                        .colorMultiply(MADTheme.Colors.primary)
                    }
                }

                // First to (for streaks, clash)
                if selectedType == .streaks || selectedType == .clash {
                    VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                        Text(selectedType == .streaks ? "First to Break Loses" : "First to Win")
                            .font(MADTheme.Typography.subheadline)
                            .foregroundColor(.white.opacity(0.7))

                        TextField("Number of wins", text: $firstTo)
                            .keyboardType(.numberPad)
                            .textFieldStyle(MADTextFieldStyle())
                    }
                }

                // Include history
                VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                    Toggle(isOn: $includeHistory) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Include Historical Data")
                                .font(MADTheme.Typography.subheadline)
                                .foregroundColor(.white)

                            Text("Start the competition with existing workout data")
                                .font(MADTheme.Typography.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .tint(MADTheme.Colors.primary)
                }
            }
            .padding(.horizontal, MADTheme.Spacing.xl)
        }
    }

    // MARK: - Navigation Buttons

    var navigationButtons: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            if currentStep > 0 {
                Button(action: {
                    withAnimation {
                        currentStep -= 1
                    }
                }) {
                    Text("Back")
                        .font(MADTheme.Typography.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MADTheme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                }
            }

            Button(action: {
                if currentStep == 0 {
                    withAnimation {
                        currentStep = 1
                    }
                } else {
                    createCompetition()
                }
            }) {
                HStack {
                    if isCreating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(currentStep == 0 ? "Next" : "Create Competition")
                            .font(MADTheme.Typography.callout)
                            .fontWeight(.semibold)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, MADTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .fill(
                            (currentStep == 0 ? canProceedStep1 : canProceedStep2)
                                ? MADTheme.Colors.primaryGradient
                                : LinearGradient(colors: [Color.gray], startPoint: .leading, endPoint: .trailing)
                        )
                )
            }
            .disabled(
                (currentStep == 0 && !canProceedStep1) ||
                (currentStep == 1 && !canProceedStep2) ||
                isCreating
            )
        }
        .padding(.horizontal, MADTheme.Spacing.xl)
    }

    // MARK: - Actions

    func createCompetition() {
        guard let type = selectedType,
              let goalValue = Double(goal),
              let firstToValue = Int(firstTo) else {
            return
        }

        isCreating = true

        Task {
            do {
                _ = try await competitionService.createCompetition(
                    name: competitionName,
                    type: type,
                    startDate: startDate,
                    endDate: endDate,
                    workouts: Array(selectedWorkouts),
                    goal: goalValue,
                    unit: unit,
                    firstTo: firstToValue,
                    history: includeHistory,
                    interval: interval
                )

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

#Preview {
    CreateCompetitionView()
}
