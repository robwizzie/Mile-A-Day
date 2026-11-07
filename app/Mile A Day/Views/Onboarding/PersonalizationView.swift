import SwiftUI

/// The "about you" onboarding step, one question per screen, right after
/// username setup. How someone found us is required, so every new account has
/// a source; "Somewhere else" and "They're not on the app yet" mean nobody is
/// ever stuck or has to give anything personal (App Store 5.1.1). The rest can
/// be skipped.
struct PersonalizationView: View {
    @Environment(\.appStateManager) var appStateManager
    @EnvironmentObject var userManager: UserManager

    private enum Step: Int, CaseIterable { case source, goal, experience, units }

    @State private var step: Step = .source
    @State private var selectedReferral: String?
    @State private var referralDetail: String = ""
    /// Only ever a real account chosen from search, never typed text.
    @State private var referrer: BackendUser?
    @State private var friendNotOnApp = false
    @State private var selectedGoal: String?
    @State private var selectedExperience: String?
    // Preselected from the device's measurement system, so a plain Continue
    // keeps following the device; only a CHANGE here pins a preference.
    @State private var selectedUnit: String? = DisplayDistanceUnit.systemDefault.rawValue
    @State private var isSubmitting = false
    @FocusState private var detailFieldFocused: Bool
    /// Goes up with each answer, which makes Flamey react.
    @State private var reaction = 0

    /// A skin for Flamey and his line, per answer.
    private static let reactions: [String: (item: String, line: String)] = [
        "app_store": ("star_glasses", "Nice find!"),
        "friend": ("flamey_jr", "Better together!"),
        "developer": ("star_hat", "You know us!"),
        "instagram": ("polaroid", "Say cheese!"),
        "tiktok": ("spotlight", "Lights on!"),
        "reddit": ("round_specs", "Well researched."),
        "google": ("aviators", "Good search!"),
        "youtube": ("directors_beret", "And action!"),
        "ai_chat": ("cyber_visor", "Beep boop!"),
        "social_ad": ("megaphone", "It worked!"),
        "flyer": ("foam_finger", "Poster fan!"),
        "other": ("safari_hat", "An explorer!"),
        "habit": ("stopwatch", "Every single day."),
        "active": ("lightning_kicks", "Let's move!"),
        "race": ("checkered_flag", "Race day!"),
        "weight": ("heart_bopper", "Feeling good!"),
        "fun": ("confetti_cannon", "Party walk!"),
        "beginner": ("canvas_sneakers", "Everyone starts here."),
        "casual": ("trainers", "Nice pace."),
        "regular": ("racing_flats", "Speedy!"),
        DisplayDistanceUnit.miles.rawValue: ("dust_puffs", "Miles it is."),
        DisplayDistanceUnit.kilometers.rawValue: ("speed_lines", "Kilometers it is.")
    ]

    private var selectionForStep: String? {
        switch step {
        case .source: return selectedReferral
        case .goal: return selectedGoal
        case .experience: return selectedExperience
        case .units: return selectedUnit
        }
    }

    /// He starts each step with something new and keeps what you chose.
    private var flameyItems: [String] {
        // A new skin each step, picked to stand out against that step's hero.
        let base: [String]
        switch step {
        case .source: base = ["ocean", "bandana"]
        case .goal: base = ["teal", "sweatband"]
        case .experience: base = ["sunflower", "star_badge"]
        case .units: base = ["rose_gold", "visor"]
        }
        var items = base
        items += [selectedReferral, selectedGoal, selectedExperience].compactMap { $0 }.compactMap { Self.reactions[$0]?.item }
        if step == .units, let selectedUnit, let unit = Self.reactions[selectedUnit]?.item { items.append(unit) }
        if referrer != nil { items.append("heart_glasses") }
        return items
    }

    private var flameyLine: String? {
        if step == .source {
            if let referrer { return "Thanks, \(referrer.first_name ?? referrer.username ?? "friend")!" }
            if friendNotOnApp { return "We'll save them a spot!" }
        }
        return selectionForStep.flatMap { Self.reactions[$0]?.line }
    }

    /// The first step can't be passed without an answer, and picking "Friend
    /// or family" needs their account or a clear "they're not on it yet".
    private var canContinue: Bool {
        guard step == .source else { return true }
        guard let selectedReferral else { return false }
        return selectedReferral != "friend" || referrer != nil || friendNotOnApp
    }

    private var isLastStep: Bool { step == Step.allCases.last }

    var body: some View {
        OnboardingFormScaffold(
            colors: colors,
            step: (step.rawValue, Step.allCases.count),
            headline: headline,
            message: message,
            art: { height in
                OnboardingFlamey(items: flameyItems, size: min(height * 0.82, 130), line: flameyLine, reaction: reaction)
                    .introPop(0.05)
            },
            content: { questions },
            actions: {
                OnboardingPrimaryButton(
                    title: isLastStep ? "Continue" : "Next",
                    isLoading: isSubmitting,
                    isEnabled: canContinue,
                    action: advance
                )
                if step == .goal || step == .experience {
                    OnboardingSecondaryButton(title: "Skip", action: advance)
                }
            }
        )
        .animation(.easeInOut(duration: 0.25), value: selectedReferral)
        .animation(.easeInOut(duration: 0.25), value: step)
        .onChange(of: referrer?.user_id) { _, picked in
            if picked != nil { reaction += 1 }
        }
    }

    private var colors: [Color] {
        switch step {
        case .source: return [Color(red: 0.97, green: 0.40, blue: 0.64), Color(red: 0.60, green: 0.12, blue: 0.44)]
        case .goal: return [Color(red: 0.98, green: 0.62, blue: 0.24), Color(red: 0.80, green: 0.28, blue: 0.20)]
        case .experience: return [Color(red: 0.30, green: 0.66, blue: 0.86), Color(red: 0.16, green: 0.30, blue: 0.62)]
        case .units: return [Color(red: 0.36, green: 0.74, blue: 0.56), Color(red: 0.12, green: 0.42, blue: 0.40)]
        }
    }

    private var headline: String {
        switch step {
        case .source: return "How did you find us?"
        case .goal: return "What's your main goal?"
        case .experience: return "How would you describe your running?"
        case .units: return "Show distances in"
        }
    }

    private var message: String {
        switch step {
        case .source: return "This helps us grow, and friends get credit for bringing you."
        case .goal: return "We'll keep this in mind."
        case .experience: return "No wrong answers. Walkers very welcome."
        case .units: return "You can change this anytime in Settings."
        }
    }

    @ViewBuilder
    private var questions: some View {
        switch step {
        case .source:
            // One choice made, the rest fold away so search clears the keyboard.
            // Tapping it again brings them back.
            chips(selectedReferral == "friend" ? Self.referralOptions.filter { $0.code == "friend" } : Self.referralOptions,
                  selection: $selectedReferral)
            if selectedReferral == "friend" {
                friendPicker.transition(.opacity.combined(with: .move(edge: .top)))
            } else if Self.detailPromptingSources.contains(selectedReferral ?? "") {
                detailField.transition(.opacity.combined(with: .move(edge: .top)))
            }
        case .goal:
            chips(Self.goalOptions, selection: $selectedGoal)
        case .experience:
            chips(Self.experienceOptions, selection: $selectedExperience)
        case .units:
            chips(Self.unitOptions, selection: $selectedUnit)
        }
    }

    private var friendPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Who sent you? Pick their account so they get credit.")
                .madFont(size: 14, weight: .semibold, design: .rounded, maxScale: 1.3)
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            ReferrerPicker(selection: $referrer)
            if referrer == nil {
                Button {
                    friendNotOnApp.toggle()
                    if friendNotOnApp { reaction += 1 }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: friendNotOnApp ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(friendNotOnApp ? MADTheme.Colors.madRed : .white.opacity(0.5))
                            .accessibilityHidden(true)
                        Text("They're not on Mile A Day yet")
                            .madFont(size: 14, weight: .semibold, design: .rounded, maxScale: 1.3)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(friendNotOnApp ? .isSelected : [])
            }
        }
    }

    private func chips(_ options: [PersonalizationOption], selection: Binding<String?>) -> some View {
        FlowLayout(spacing: 10) {
            ForEach(options) { option in
                ChipView(option: option, isSelected: selection.wrappedValue == option.code) {
                    let wasSelected = selection.wrappedValue == option.code
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selection.wrappedValue = wasSelected ? nil : option.code
                    }
                    if !wasSelected { reaction += 1 }
                }
            }
        }
    }

    private func advance() {
        detailFieldFocused = false
        if isLastStep {
            submitAndContinue()
        } else if let next = Step(rawValue: step.rawValue + 1) {
            MADHaptics.tap()
            step = next
        }
    }

    // MARK: - Conditional referral detail field

    /// Sources that ask a follow-up. `friend` and `developer` both resolve the
    /// answer against real usernames server-side, so they take handle-style
    /// input; `other` is free text about a channel.
    static let detailPromptingSources: Set<String> = ["developer", "other"]

    private var detailField: some View {
        let wantsHandle = selectedReferral == "friend" || selectedReferral == "developer"
        let prompt: String
        switch selectedReferral {
        case "friend": prompt = "Friend's username (optional)"
        case "developer": prompt = "Who sent you? (optional)"
        default: prompt = "Where'd you find us? (optional)"
        }
        return VStack(alignment: .leading, spacing: 8) {
            TextField(
                "",
                text: $referralDetail,
                prompt: Text(prompt)
                    .foregroundColor(.white.opacity(0.4))
            )
            .textInputAutocapitalization(wantsHandle ? .never : .sentences)
            .autocorrectionDisabled(wantsHandle)
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

    // MARK: - Submit

    private func submitAndContinue() {
        guard !isSubmitting else { return }
        detailFieldFocused = false
        isSubmitting = true

        // Only send the referral detail when it's relevant to the selected source.
        let showsDetail = selectedReferral == "other"
        let trimmedDetail = referralDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        let referrerUsername = selectedReferral == "friend" ? referrer?.username : nil
        let typedDetail: String? = (showsDetail && !trimmedDetail.isEmpty)
            ? (trimmedDetail.hasPrefix("@") ? String(trimmedDetail.dropFirst()) : trimmedDetail)
            : nil
        let detailToSend = referrerUsername ?? typedDetail

        let userId = userManager.currentUser.backendUserId

        // Local only — display units never reach the server (storage is
        // miles everywhere). Pin a preference only when it differs from the
        // device; otherwise keep following the device's setting.
        if let raw = selectedUnit, let unit = DisplayDistanceUnit(rawValue: raw),
           unit != DisplayDistanceUnit.systemDefault {
            DistanceUnits.current = unit
        }

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

            // Best-effort too: Invite friends lets them add it for 14 days.
            if let referrerUsername {
                try? await ReferralService.shared.setReferrer(username: referrerUsername)
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
        // Kept separate from "friend" on purpose: a founder handing someone the
        // app is our own outreach, and folding it into word-of-mouth would
        // overstate organic growth by exactly the amount of work we did.
        PersonalizationOption(code: "developer", label: "Someone from the team", icon: "checkmark.seal.fill"),
        PersonalizationOption(code: "instagram", label: "Instagram", icon: "camera.fill"),
        PersonalizationOption(code: "tiktok", label: "TikTok", icon: "music.note"),
        PersonalizationOption(code: "reddit", label: "Reddit", icon: "bubble.left.and.bubble.right.fill"),
        PersonalizationOption(code: "google", label: "Google / search", icon: "globe"),
        PersonalizationOption(code: "youtube", label: "YouTube", icon: "play.rectangle.fill"),
        // People genuinely arrive from an assistant recommending us, and until
        // this chip existed every one of them landed in "Somewhere else" —
        // indistinguishable from a channel we can't act on.
        PersonalizationOption(code: "ai_chat", label: "ChatGPT / AI", icon: "sparkles"),
        // PAID reach, distinct from the organic platform chips above it: an
        // Instagram ad and an Instagram post are the same app and completely
        // different questions about where to spend next.
        PersonalizationOption(code: "social_ad", label: "Saw an ad", icon: "megaphone.fill"),
        PersonalizationOption(code: "flyer", label: "Flyer or poster", icon: "doc.text.fill"),
        PersonalizationOption(code: "other", label: "Somewhere else", icon: "ellipsis")
    ]

    static let goalOptions: [PersonalizationOption] = [
        PersonalizationOption(code: "habit", label: "Build a daily habit", icon: "calendar"),
        PersonalizationOption(code: "active", label: "Get more active", icon: "figure.run"),
        PersonalizationOption(code: "race", label: "Train for a race", icon: "flag.checkered"),
        PersonalizationOption(code: "weight", label: "Get healthier", icon: "heart.fill"),
        PersonalizationOption(code: "fun", label: "Just for fun", icon: "sparkles")
    ]

    static let unitOptions: [PersonalizationOption] = [
        PersonalizationOption(code: DisplayDistanceUnit.miles.rawValue, label: "Miles", icon: "road.lanes"),
        PersonalizationOption(code: DisplayDistanceUnit.kilometers.rawValue, label: "Kilometers", icon: "globe.europe.africa.fill")
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
                // The label is data (a catalog entry), so it's looked up as a
                // key explicitly — `Text(String)` never localizes.
                Text(LocalizedStringKey(option.label))
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
