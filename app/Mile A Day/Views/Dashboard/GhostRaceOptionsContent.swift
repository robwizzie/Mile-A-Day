import SwiftUI

/// Choose what to race — the picker itself, with no presentation chrome.
///
/// The rule this screen exists to guarantee: there is ALWAYS something to race.
/// Before it, a walk with no recorded history had no ghost at all and the card
/// just explained why you couldn't play. Now the custom target is always
/// offered, so "race a time I pick" works on the very first walk.
///
/// Everything is on one screen, in the order the question actually gets asked:
/// what am I chasing → how fast is it → what happens when I start.
///
/// Deliberately chrome-free (no NavigationStack, no toolbar, no `dismiss`, no
/// background of its own) because it renders in two very different places: as a
/// step INSIDE the walk/run wizard, over that screen's red gradient, and as a
/// sheet from the buddy lobby (`GhostRaceSetupSheet`) over the app gradient.
/// The host owns the background, the way back, and what "done" means.
struct GhostRaceOptionsContent: View {
    let activityKey: String
    /// Backend fastest-mile PR in seconds, when there is one.
    let seedPaceSeconds: Double?
    /// Currently armed target, so re-opening shows what's already set.
    let current: BestEffortStore.GhostTarget?
    /// Tint for selection, glyphs and the primary button — supplied by the
    /// host because the right answer depends on what's BEHIND this view. The
    /// workout color is correct over the lobby's dark gradient, but
    /// `workoutColor("running")` is literally the tracker gradient's own top
    /// stop, so inline it would put a red button on a red screen.
    let accent: Color
    /// Label color on the primary button; must contrast with `accent`.
    let accentForeground: Color
    /// Wording for the secondary action — "carry on without a ghost" reads
    /// differently inside a wizard than it does in a modal over a lobby.
    let declineTitle: String
    /// Race this. The custom time is already persisted by the time this fires.
    let onRace: (BestEffortStore.GhostTarget) -> Void
    /// Don't race this session.
    let onDecline: () -> Void

    @State private var selection: BestEffortStore.GhostTarget = .recordedBest
    /// Custom target, held split so the wheels are independent.
    @State private var customMinutes: Int = 9
    @State private var customSeconds: Int = 0
    /// `onAppear` fires again when a host re-presents this view; priming twice
    /// would throw away wheel edits mid-decision.
    @State private var hasPrimed = false

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
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: MADTheme.Spacing.lg) {
                    header
                    targetList
                    if isCustomSelected { customPicker }
                    howItWorks
                    // Reserves scroll room under the pinned footer.
                    Color.clear.frame(height: 180)
                }
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.top, MADTheme.Spacing.sm)
            }
            .scrollIndicators(.hidden)

            footer
        }
        .onAppear {
            guard !hasPrimed else { return }
            hasPrimed = true
            primeSelection()
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

    /// Compact and scrolling, not a pinned card: this step has real content
    /// under it, and the host already renders a title bar above.
    private var header: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            ZStack {
                Circle().fill(accent.opacity(0.22)).frame(width: 56, height: 56)
                Image(systemName: "flag.checkered")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(accent)
            }
            Text("Race a ghost for one mile")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(MADTheme.Colors.madWhite)
                .multilineTextAlignment(.center)
            Text(
                "Pick a time to chase. You'll see how far ahead or behind you are the whole way."
            )
            .font(MADTheme.Typography.subheadline)
            .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.7))
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, MADTheme.Spacing.sm)
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

            if let targetFootnote {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11, weight: .semibold))
                    Text(targetFootnote)
                        .font(MADTheme.Typography.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.5))
                .padding(.top, 2)
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
                    .foregroundStyle(isOn ? MADTheme.Colors.madWhite : MADTheme.Colors.madWhite.opacity(0.8))
                    .monospacedDigit()
            }
            .padding(MADTheme.Spacing.md)
            .ghostRaceSurface(selected: isOn, accent: accent)
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
                "figure.run.circle.fill",
                "Best tracked in-app",
                "Your fastest mile tracked with Start Mile, replayed at the real pace you ran it — surges and all.",
                BestEffortStore.formatSeconds(seconds)
            )
        case .personalRecord:
            return (
                "bolt.fill",
                "All-time PR",
                "Your fastest mile from ANY workout, Apple Watch included. Held at one even pace.",
                BestEffortStore.formatSeconds(seedPaceSeconds ?? 0)
            )
        case .custom:
            return (
                "slider.horizontal.3",
                "A time you set",
                isRun
                    ? "Any target you like — a goal pace, or a friend's time."
                    : "Any target you like. Works from your very first walk.",
                BestEffortStore.formatSeconds(customTotalSeconds)
            )
        }
    }

    /// The two "bests" routinely disagree — badly enough that the screen has to
    /// say why. The in-app best comes from this app's tracker only; the PR is
    /// the fastest mile SPLIT across every synced workout, so a quick mile
    /// inside a long Apple Watch run sets it. Someone whose fast running
    /// happens on the Watch sees 9:47 next to 6:41 and, without this line, has
    /// no way to know which number means what.
    private var targetFootnote: String? {
        guard targets.contains(where: { if case .recordedBest = $0 { return true }; return false }),
            targets.contains(where: { if case .personalRecord = $0 { return true }; return false })
        else { return nil }
        return
            "Your PR can be faster than your best tracked mile — it counts miles from Apple Watch and other apps, which this app's tracker never saw."
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
        .ghostRaceSurface(selected: false, accent: accent)
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
                isRun
                    ? "It locks in the moment you hit 1.00 mi — the rest of the run is yours."
                    : "It locks in the moment you hit 1.00 mi — the rest of the walk is yours."
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
        .ghostRaceSurface(selected: false, accent: accent)
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
                .foregroundStyle(accentForeground)
            }
            .buttonStyle(.plain)
            .disabled(!armedIsValid)
            .opacity(armedIsValid ? 1 : 0.5)

            Button {
                MADHaptics.tap()
                onDecline()
            } label: {
                Text(declineTitle)
                    .font(MADTheme.Typography.small)
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.7))
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        // The generous top padding is what gives the scrim room to fade in, so
        // content dissolves under the footer instead of hitting a hard edge.
        .padding(.top, MADTheme.Spacing.xl)
        .padding(.bottom, MADTheme.Spacing.sm)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        )
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
        onRace(armedTarget)
    }
}

// MARK: - Card surface

private extension View {
    /// The card treatment for this screen.
    ///
    /// Deliberately NOT `madLiquidGlass`: this content now renders over the
    /// tracker's red gradient as well as the lobby's dark one, and a
    /// translucent white card is the one treatment that reads correctly on
    /// both — and matches the Run/Walk option cards it now sits beside in the
    /// wizard. Selection is carried by a fill AND a stroke, since a stroke
    /// alone is easy to miss on a busy gradient.
    func ghostRaceSurface(selected: Bool, accent: Color) -> some View {
        background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(selected ? accent.opacity(0.22) : Color.white.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .strokeBorder(
                    selected ? accent : Color.white.opacity(0.18),
                    lineWidth: selected ? 2 : 1
                )
        )
    }
}
