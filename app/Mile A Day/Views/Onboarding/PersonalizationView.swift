import SwiftUI

/// Optional "about you" onboarding step, shown once right after username setup
/// and before the welcome celebration. Captures light personalization —
/// how the user heard about us, their main goal, and running experience — to
/// power referral analytics and future tailoring.
///
/// Everything here is optional (App Store 5.1.1(i): don't require non-essential
/// personal info to use the app). "Skip" and "Continue" both advance; a pure
/// skip still records the step as complete on the backend so it never re-shows.
struct PersonalizationView: View {
    @Environment(\.appStateManager) var appStateManager
    @EnvironmentObject var userManager: UserManager

    @State private var selectedReferral: String?
    @State private var referralDetail: String = ""
    @State private var selectedGoal: String?
    @State private var selectedExperience: String?
    @State private var isSubmitting = false
    @FocusState private var detailFieldFocused: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.06, blue: 0.08),
                    Color(red: 0.06, green: 0.03, blue: 0.04)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: MADTheme.Spacing.xl) {
                    header

                    section(
                        title: "How did you hear about us?",
                        options: Self.referralOptions,
                        selection: $selectedReferral
                    )

                    if selectedReferral == "friend" || selectedReferral == "other" {
                        detailField
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    section(
                        title: "What's your main goal?",
                        options: Self.goalOptions,
                        selection: $selectedGoal
                    )

                    section(
                        title: "How would you describe your running?",
                        options: Self.experienceOptions,
                        selection: $selectedExperience
                    )

                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, MADTheme.Spacing.xl)
                .padding(.top, MADTheme.Spacing.xl)
                .padding(.bottom, MADTheme.Spacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .overlay(alignment: .topTrailing) { skipButton }
        .safeAreaInset(edge: .bottom) { continueButton }
        .animation(.easeInOut(duration: 0.25), value: selectedReferral)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            Text("A little about you")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Optional, but it helps us make Mile A Day yours.")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.trailing, 44) // clear the Skip button
    }

    // MARK: - Section

    private func section(title: String, options: [PersonalizationOption], selection: Binding<String?>) -> some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))

            FlowLayout(spacing: 10) {
                ForEach(options) { option in
                    ChipView(
                        option: option,
                        isSelected: selection.wrappedValue == option.code
                    ) {
                        let wasSelected = selection.wrappedValue == option.code
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selection.wrappedValue = wasSelected ? nil : option.code
                        }
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                }
            }
        }
    }

    // MARK: - Conditional referral detail field

    private var detailField: some View {
        let isFriend = selectedReferral == "friend"
        return VStack(alignment: .leading, spacing: 8) {
            TextField(
                "",
                text: $referralDetail,
                prompt: Text(isFriend ? "Friend's username (optional)" : "Where'd you find us? (optional)")
                    .foregroundColor(.white.opacity(0.4))
            )
            .textInputAutocapitalization(isFriend ? .never : .sentences)
            .autocorrectionDisabled(isFriend)
            .focused($detailFieldFocused)
            .submitLabel(.done)
            .onSubmit { detailFieldFocused = false }
            .foregroundColor(.white)
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Buttons

    private var skipButton: some View {
        Button {
            submitAndContinue()
        } label: {
            Text("Skip")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
                .padding(.horizontal, MADTheme.Spacing.lg)
                .padding(.vertical, MADTheme.Spacing.md)
        }
        .disabled(isSubmitting)
    }

    private var continueButton: some View {
        Button(action: submitAndContinue) {
            Group {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Continue")
                }
            }
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MADTheme.Colors.madRed)
            )
            .shadow(color: MADTheme.Colors.madRed.opacity(0.3), radius: 12, x: 0, y: 6)
        }
        .disabled(isSubmitting)
        .padding(.horizontal, MADTheme.Spacing.xl)
        .padding(.bottom, MADTheme.Spacing.md)
    }

    // MARK: - Submit

    private func submitAndContinue() {
        guard !isSubmitting else { return }
        detailFieldFocused = false
        isSubmitting = true

        // Only send the referral detail when it's relevant to the selected source.
        let showsDetail = selectedReferral == "friend" || selectedReferral == "other"
        let trimmedDetail = referralDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        let detailToSend: String? = (showsDetail && !trimmedDetail.isEmpty)
            ? trimmedDetail.hasPrefix("@") ? String(trimmedDetail.dropFirst()) : trimmedDetail
            : nil

        let userId = userManager.currentUser.backendUserId

        Task {
            // Best-effort: never block onboarding on this optional call.
            if let userId, !userId.isEmpty {
                do {
                    try await OnboardingService.submit(
                        userId: userId,
                        referralSource: selectedReferral,
                        referralDetail: detailToSend,
                        signupGoal: selectedGoal,
                        experienceLevel: selectedExperience
                    )
                } catch {
                    print("[PersonalizationView] onboarding submit failed (non-blocking): \(error)")
                }
            }

            await MainActor.run {
                isSubmitting = false
                withAnimation(MADTheme.Animation.standard) {
                    appStateManager.completePersonalization()
                }
            }
        }
    }

    // MARK: - Option catalogs
    // `code` values are the stable identifiers stored on the backend; keep them
    // in sync with REFERRAL_SOURCES in usersController.ts.

    static let referralOptions: [PersonalizationOption] = [
        PersonalizationOption(code: "app_store", label: "App Store", icon: "magnifyingglass"),
        PersonalizationOption(code: "friend", label: "Friend or family", icon: "person.2.fill"),
        PersonalizationOption(code: "instagram", label: "Instagram", icon: "camera.fill"),
        PersonalizationOption(code: "tiktok", label: "TikTok", icon: "music.note"),
        PersonalizationOption(code: "reddit", label: "Reddit", icon: "bubble.left.and.bubble.right.fill"),
        PersonalizationOption(code: "google", label: "Google / search", icon: "globe"),
        PersonalizationOption(code: "youtube", label: "YouTube", icon: "play.rectangle.fill"),
        PersonalizationOption(code: "other", label: "Somewhere else", icon: "ellipsis")
    ]

    static let goalOptions: [PersonalizationOption] = [
        PersonalizationOption(code: "habit", label: "Build a daily habit", icon: "calendar"),
        PersonalizationOption(code: "active", label: "Get more active", icon: "figure.run"),
        PersonalizationOption(code: "race", label: "Train for a race", icon: "flag.checkered"),
        PersonalizationOption(code: "weight", label: "Get healthier", icon: "heart.fill"),
        PersonalizationOption(code: "fun", label: "Just for fun", icon: "sparkles")
    ]

    static let experienceOptions: [PersonalizationOption] = [
        PersonalizationOption(code: "beginner", label: "Just starting out", icon: "figure.walk"),
        PersonalizationOption(code: "casual", label: "I run sometimes", icon: "figure.run"),
        PersonalizationOption(code: "regular", label: "I run regularly", icon: "bolt.fill")
    ]
}

// MARK: - Option model

struct PersonalizationOption: Identifiable, Equatable {
    let code: String
    let label: String
    let icon: String
    var id: String { code }
}

// MARK: - Chip

private struct ChipView: View {
    let option: PersonalizationOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: option.icon)
                    .font(.system(size: 13, weight: .bold))
                Text(option.label)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.8))
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .background(
                ZStack {
                    Capsule().fill(isSelected ? MADTheme.Colors.madRed : Color.white.opacity(0.06))
                    Capsule().strokeBorder(
                        isSelected ? Color.clear : Color.white.opacity(0.14),
                        lineWidth: 1
                    )
                }
            )
            .shadow(color: isSelected ? MADTheme.Colors.madRed.opacity(0.35) : .clear, radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow layout

/// Lightweight wrapping layout for chips — flows subviews left-to-right and
/// wraps to a new line when the proposed width runs out. (iOS 16+ `Layout`.)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                maxLineWidth = max(maxLineWidth, x - spacing)
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        maxLineWidth = max(maxLineWidth, x - spacing)
        let width = maxWidth == .infinity ? maxLineWidth : maxWidth
        return CGSize(width: max(0, width), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

#Preview {
    PersonalizationView()
        .environmentObject(UserManager())
        .environmentObject(AppStateManager())
        .preferredColorScheme(.dark)
}
