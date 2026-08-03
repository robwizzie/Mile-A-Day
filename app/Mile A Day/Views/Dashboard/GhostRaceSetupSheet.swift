import SwiftUI

/// Choose what to race this session.
///
/// The rule this screen exists to guarantee: there is ALWAYS something to race.
/// Before it, a walk with no recorded history had no ghost at all and the card
/// just explained why you couldn't play. Now the custom target is always
/// offered, so "race a time I pick" works on the very first walk.
///
/// Everything is on one screen, in the order the question actually gets asked:
/// what am I chasing → how fast is it → what happens when I start.
struct GhostRaceSetupSheet: View {
    let activityKey: String
    /// Backend fastest-mile PR in seconds, when there is one.
    let seedPaceSeconds: Double?
    /// Currently armed target, so re-opening shows what's already set.
    let current: BestEffortStore.GhostTarget?
    /// Non-nil = race this. Nil = don't race this session.
    let onDone: (BestEffortStore.GhostTarget?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selection: BestEffortStore.GhostTarget = .recordedBest
    /// Custom target, held split so the wheels are independent.
    @State private var customMinutes: Int = 9
    @State private var customSeconds: Int = 0

    private var accent: Color { MADTheme.workoutColor(activityKey) }
    private var isRun: Bool { activityKey == "running" }

    private var targets: [BestEffortStore.GhostTarget] {
        BestEffortStore.availableTargets(
            for: activityKey, seedPaceSecondsPerMile: seedPaceSeconds)
    }

    private var customTotalSeconds: Double {
        Double(customMinutes * 60 + customSeconds)
    }

    private var isCustomSelected: Bool {
        if case .custom = selection { return true }
        return false
    }

    /// The selection as it would be armed — custom picks up the live wheels.
    private var armedTarget: BestEffortStore.GhostTarget {
        isCustomSelected ? .custom(seconds: customTotalSeconds) : selection
    }

    private var armedIsValid: Bool {
        !isCustomSelected || BestEffortStore.GhostTarget.isPlausible(customTotalSeconds)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: MADTheme.Spacing.lg) {
                        header
                        targetList
                        if isCustomSelected { customPicker }
                        howItWorks
                        Color.clear.frame(height: 120)
                    }
                    .padding(.horizontal, MADTheme.Spacing.md)
                    .padding(.top, MADTheme.Spacing.sm)
                }

                footer
            }
            .navigationTitle("Ghost Race")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: primeSelection)
        }
    }

    /// One-shot: seed the wheels and the selected row from what's already
    /// armed, falling back to the best available target.
    private func primeSelection() {
        let seconds = BestEffortStore.customSeconds(for: activityKey)
        customMinutes = Int(seconds) / 60
        customSeconds = Int(seconds) % 60

        if let current, targetsContain(current) {
            selection = current
            if case .custom(let s) = current {
                customMinutes = Int(s) / 60
                customSeconds = Int(s) % 60
            }
        } else {
            selection = BestEffortStore.defaultTarget(
                for: activityKey, seedPaceSecondsPerMile: seedPaceSeconds)
        }
    }

    /// Custom matches on KIND, not on seconds — the wheels own the value.
    private func targetsContain(_ target: BestEffortStore.GhostTarget) -> Bool {
        targets.contains {
            switch ($0, target) {
            case (.recordedBest, .recordedBest), (.personalRecord, .personalRecord):
                return true
            case (.custom, .custom):
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            ZStack {
                Circle().fill(accent.opacity(0.18)).frame(width: 72, height: 72)
                Image(systemName: "flag.checkered")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(accent)
            }
            Text("Race a ghost for one mile")
                .font(MADTheme.Typography.title3)
                .foregroundStyle(MADTheme.Colors.madWhite)
            Text(
                "Pick a time to chase. You'll see how far ahead or behind you are the whole way."
            )
            .font(MADTheme.Typography.subheadline)
            .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.65))
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MADTheme.Spacing.lg)
        .padding(.horizontal, MADTheme.Spacing.md)
        .madLiquidGlass(cornerRadius: MADTheme.CornerRadius.extraLarge)
    }

    // MARK: - Targets

    private var targetList: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            Text("What are you chasing?")
                .font(MADTheme.Typography.headline)
                .foregroundStyle(MADTheme.Colors.madWhite)

            ForEach(Array(targets.enumerated()), id: \.offset) { _, target in
                targetRow(target)
            }
        }
    }

    private func targetRow(_ target: BestEffortStore.GhostTarget) -> some View {
        let info = rowInfo(target)
        let isOn = matchesSelection(target)
        return Button {
            MADHaptics.tap()
            withAnimation(MADTheme.Animation.quick) { selection = target }
        } label: {
            HStack(spacing: MADTheme.Spacing.md) {
                Image(systemName: info.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isOn ? accent : MADTheme.Colors.madWhite.opacity(0.5))
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(info.title)
                        .font(MADTheme.Typography.bodyBold)
                        .foregroundStyle(MADTheme.Colors.madWhite)
                    Text(info.detail)
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: MADTheme.Spacing.sm)

                Text(info.time)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(isOn ? accent : MADTheme.Colors.madWhite.opacity(0.8))
                    .monospacedDigit()
            }
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass(cornerRadius: MADTheme.CornerRadius.large)
            .overlay(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .stroke(isOn ? accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func matchesSelection(_ target: BestEffortStore.GhostTarget) -> Bool {
        switch (target, selection) {
        case (.recordedBest, .recordedBest), (.personalRecord, .personalRecord):
            return true
        case (.custom, .custom):
            return true
        default:
            return false
        }
    }

    private func rowInfo(
        _ target: BestEffortStore.GhostTarget
    ) -> (icon: String, title: String, detail: String, time: String) {
        switch target {
        case .recordedBest:
            let seconds = BestEffortStore.best(for: activityKey)?.seconds ?? 0
            return (
                "trophy.fill",
                "Your best mile",
                "The real thing — paced exactly the way you actually ran it.",
                BestEffortStore.formatSeconds(seconds)
            )
        case .personalRecord:
            return (
                "bolt.fill",
                "Your PR pace",
                "Your fastest recorded mile, held at an even pace the whole way.",
                BestEffortStore.formatSeconds(seedPaceSeconds ?? 0)
            )
        case .custom:
            return (
                "slider.horizontal.3",
                "A time you set",
                isRun
                    ? "Pick any target — a goal pace, or a rival's time."
                    : "Pick any target. Works from your very first walk.",
                BestEffortStore.formatSeconds(customTotalSeconds)
            )
        }
    }

    // MARK: - Custom picker

    private var customPicker: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            HStack(spacing: 0) {
                wheel(value: $customMinutes, range: 2...40, unit: "min")
                Text(":")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.5))
                wheel(value: $customSeconds, range: 0...59, unit: "sec")
            }
            .frame(height: 130)

            Text(paceHint)
                .font(MADTheme.Typography.caption)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(MADTheme.Spacing.md)
        .frame(maxWidth: .infinity)
        .madLiquidGlass(cornerRadius: MADTheme.CornerRadius.large)
    }

    private func wheel(value: Binding<Int>, range: ClosedRange<Int>, unit: String) -> some View {
        VStack(spacing: 2) {
            Picker(unit, selection: value) {
                ForEach(Array(range), id: \.self) { n in
                    Text(String(format: "%02d", n))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(MADTheme.Colors.madWhite)
                        .tag(n)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            Text(unit.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.45))
        }
    }

    /// Grounds the abstract number in something the user recognises. A target
    /// they can't picture is a target they can't pick well.
    private var paceHint: String {
        guard let reference = referenceSeconds else {
            return "That's a \(BestEffortStore.formatSeconds(customTotalSeconds)) mile pace."
        }
        let delta = Int((reference - customTotalSeconds).rounded())
        if abs(delta) < 3 { return "Just about dead even with your best mile." }
        return delta > 0
            ? "\(delta)s faster than your best mile — a real push."
            : "\(-delta)s easier than your best mile — a comfortable target."
    }

    private var referenceSeconds: Double? {
        BestEffortStore.best(for: activityKey)?.seconds
            ?? (isRun ? seedPaceSeconds : nil)
    }

    // MARK: - Explainer

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            Text("How it works")
                .font(MADTheme.Typography.headline)
                .foregroundStyle(MADTheme.Colors.madWhite)

            explainerRow(
                "gauge.with.needle",
                "A live chip under your clock shows +/- seconds against the ghost."
            )
            explainerRow(
                "flag.checkered",
                "It locks in the moment you hit 1.00 mi — the rest of the walk is yours."
            )
            explainerRow(
                "stopwatch",
                isRun
                    ? "Only moving time counts, so stopping at a light can't cheat the race."
                    : "Only moving time counts, so pausing to wait can't cheat the race."
            )
            explainerRow(
                "arrow.clockwise",
                "Every finished mile updates your best, whether you raced it or not."
            )
        }
        .padding(MADTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .madLiquidGlass(cornerRadius: MADTheme.CornerRadius.large)
    }

    private func explainerRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: MADTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 20)
            Text(text)
                .font(MADTheme.Typography.footnote)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            Button {
                MADHaptics.action()
                commit()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "flag.checkered")
                    Text("Race \(BestEffortStore.formatSeconds(armedSeconds))")
                }
                .font(MADTheme.Typography.bodyBold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, MADTheme.Spacing.md)
                .background(Capsule().fill(accent))
                .foregroundStyle(MADTheme.Colors.madWhite)
            }
            .buttonStyle(.plain)
            .disabled(!armedIsValid)
            .opacity(armedIsValid ? 1 : 0.5)

            Button {
                MADHaptics.tap()
                onDone(nil)
                dismiss()
            } label: {
                Text(current == nil ? "Not this time" : "Turn off racing")
                    .font(MADTheme.Typography.small)
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.65))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.top, MADTheme.Spacing.sm)
        .padding(.bottom, MADTheme.Spacing.sm)
        .background(MADTheme.Colors.madBlack.opacity(0.9))
    }

    private var armedSeconds: Double {
        switch armedTarget {
        case .recordedBest: return BestEffortStore.best(for: activityKey)?.seconds ?? 0
        case .personalRecord: return seedPaceSeconds ?? 0
        case .custom(let seconds): return seconds
        }
    }

    private func commit() {
        guard armedIsValid else { return }
        if case .custom(let seconds) = armedTarget {
            BestEffortStore.saveCustomSeconds(seconds, for: activityKey)
        }
        onDone(armedTarget)
        dismiss()
    }
}
