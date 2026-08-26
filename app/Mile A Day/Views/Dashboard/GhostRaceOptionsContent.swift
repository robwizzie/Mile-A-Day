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

    /// Which number the wheels are holding. The two are the same thing over a
    /// mile, and only diverge once a longer distance is chosen — so the toggle
    /// only ever needs to exist for the custom target.
    private enum CustomEntryMode: Hashable {
        /// Wheels hold the time for the WHOLE distance ("24:48 for a 5K").
        case total
        /// Wheels hold seconds per mile ("8:00/mi").
        case perMile
    }

    @State private var selection: BestEffortStore.GhostTarget = .recordedBest
    /// Custom target, held split so the wheels are independent.
    @State private var customMinutes: Int = 9
    @State private var customSeconds: Int = 0
    /// How far the custom target races. Every other target is a measured mile.
    @State private var customDistance: Double = 1.0
    @State private var entryMode: CustomEntryMode = .perMile
    /// `onAppear` fires again when a host re-presents this view; priming twice
    /// would throw away wheel edits mid-decision.
    @State private var hasPrimed = false

    @ObservedObject private var friendGhosts = FriendGhostService.shared
    @AppStorage(GhostCoach.enabledKey) private var coachEnabled = true
    /// Mirrors `GhostCoach.intervalMiles`' own default, which reads the key
    /// with `object(forKey:)` so that 0 can mean OFF rather than "never set".
    @AppStorage(GhostCoach.intervalKey) private var coachInterval: Double = 0.5

    private var isRun: Bool { activityKey == "running" }

    /// Friends you can chase, fastest first (the server orders them), minus
    /// yourself — your own mile is already offered as "best tracked in-app".
    private var friends: [FriendGhost] {
        friendGhosts.ghosts(for: activityKey)
            .filter { $0.user_id != UserManager.shared.currentUser.backendUserId }
    }

    /// Friend rows: the ones the server returned, plus the friend already
    /// armed if they aren't in that list yet.
    ///
    /// That second part is load-bearing. `primeSelection` runs synchronously
    /// in `onAppear`, while the friend list arrives over the network from
    /// `.task` — so at prime time this list is EMPTY on a cold cache. Without
    /// the armed friend pinned in, `targetsContain(current)` returns false and
    /// the picker silently reverts an armed friend ghost to `defaultTarget`:
    /// you chose Alex last session, you re-open the picker, and it has quietly
    /// swapped you back to your own best. Same failure as matching friends by
    /// kind, reached through a different door.
    ///
    /// Pinning it is safe because a `.friend` target is self-contained — it
    /// carries its own seconds and name, so it stays raceable with no network
    /// at all, and it survives the friend dropping off the list entirely
    /// (unfriended, went private, switched activity).
    private var friendTargets: [BestEffortStore.GhostTarget] {
        var list = friends.map(\.target)
        if let current, let armedId = current.friendUserId,
            !list.contains(where: { $0.friendUserId == armedId })
        {
            list.insert(current, at: 0)
        }
        return list
    }

    /// Your own targets, then friends, then `.custom`.
    ///
    /// `.custom` MUST stay last — it's the always-available fallback, and the
    /// picker's promise is that there is always something to race.
    private var targets: [BestEffortStore.GhostTarget] {
        var base = BestEffortStore.availableTargets(
            for: activityKey, seedPaceSecondsPerMile: seedPaceSeconds)
        // `availableTargets` always ends with `.custom` — lift it off, insert
        // the friends, put it back last.
        let custom = base.removeLast()
        base.append(contentsOf: friendTargets)
        base.append(custom)
        return base
    }

    /// Whatever the wheels literally read, in the ACTIVE mode's unit.
    private var wheelSeconds: Double {
        Double(customMinutes * 60 + customSeconds)
    }

    /// Miles the custom target covers, never zero — everything below divides
    /// by it.
    private var customMiles: Double {
        customDistance.isFinite && customDistance > 0 ? customDistance : 1.0
    }

    /// Time for the WHOLE custom distance. This is what a `.custom` target
    /// carries, whichever way the user typed it in.
    private var customTotalSeconds: Double {
        entryMode == .total ? wheelSeconds : wheelSeconds * customMiles
    }

    /// Seconds per mile the custom target implies.
    private var customPerMileSeconds: Double {
        entryMode == .total ? wheelSeconds / customMiles : wheelSeconds
    }

    private var isCustomSelected: Bool {
        if case .custom = selection { return true }
        return false
    }

    /// The selection as it would be armed — custom picks up the live wheels.
    private var armedTarget: BestEffortStore.GhostTarget {
        isCustomSelected
            ? .custom(seconds: customTotalSeconds, distanceMiles: customMiles)
            : selection
    }

    /// The distance actually being raced. Only a custom target is ever
    /// anything but a mile.
    private var armedDistanceMiles: Double {
        armedTarget.distanceMiles
    }

    private var armedIsValid: Bool {
        !isCustomSelected
            || BestEffortStore.GhostTarget.isPlausible(
                customTotalSeconds, over: customMiles)
    }

    private var minutesRange: ClosedRange<Int> {
        wheelMinutesRange(for: entryMode, miles: customMiles)
    }

    /// Minutes the wheel may show. In total-time mode it has to stretch to
    /// cover the whole distance — a half marathon is two hours, not forty
    /// minutes. Identical to the shipped 4...40 for a mile.
    ///
    /// Takes the mode and distance rather than reading state, so a mode or
    /// distance change can compute the NEW range and re-seat the wheels in the
    /// same pass that changes them.
    private func wheelMinutesRange(
        for mode: CustomEntryMode, miles: Double
    ) -> ClosedRange<Int> {
        guard mode == .total, miles > 1.001 else { return 4...40 }
        let low = max(
            1, Int((BestEffortStore.GhostTarget.minPlausibleSeconds * miles) / 60))
        let raw = Int((BestEffortStore.GhostTarget.maxPlausibleSeconds * miles) / 60)
        let high = max(low + 1, min(600, raw))
        return low...high
    }

    /// Put `seconds` on the wheels, clamped into the range the given mode
    /// allows — a Picker whose selection isn't among its own rows shows as no
    /// selection at all, so the clamp is not cosmetic.
    private func setWheelSeconds(
        _ seconds: Double, mode: CustomEntryMode, miles: Double
    ) {
        let range = wheelMinutesRange(for: mode, miles: miles)
        let low = Double(range.lowerBound * 60)
        let high = Double(range.upperBound * 60 + 59)
        let rounded = seconds.isFinite ? seconds.rounded() : low
        let clamped = Int(min(max(rounded, low), high))
        customMinutes = min(max(clamped / 60, range.lowerBound), range.upperBound)
        customSeconds = min(max(clamped % 60, 0), 59)
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: MADTheme.Spacing.lg) {
                    header
                    targetList
                    if isCustomSelected { customPicker }
                    coachToggle
                    coachIntervalChooser
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
        // Friends load AFTER the first prime, so a stored friend target is
        // resolved from its own persisted seconds rather than waiting on the
        // network — the picker is never blank and never blocks.
        .task(id: activityKey) {
            await friendGhosts.refreshIfNeeded(activityKey: activityKey)
        }
    }

    /// One-shot: seed the wheels and the selected row from what's already
    /// armed, falling back to the best available target.
    private func primeSelection() {
        // The stored custom target is held as a per-mile PACE plus a distance,
        // so priming always starts from the pace and the wheels always open in
        // per-mile mode — the one reading that means the same thing at every
        // distance, and the one the seeding ("a shade under your best") is in.
        var perMile = BestEffortStore.customSeconds(for: activityKey)
        var miles = BestEffortStore.customDistanceMiles(for: activityKey)

        if let current, targetsContain(current) {
            selection = current
            if case .custom(let total, let distanceMiles) = current {
                miles = distanceMiles.isFinite && distanceMiles > 0 ? distanceMiles : 1.0
                perMile = total / miles
            }
        } else {
            selection = BestEffortStore.defaultTarget(
                for: activityKey, seedPaceSecondsPerMile: seedPaceSeconds)
        }

        entryMode = .perMile
        customDistance = miles
        setWheelSeconds(perMile, mode: .perMile, miles: miles)
    }

    /// Custom matches on KIND, not on seconds — the wheels own the value.
    /// A friend matches on ID: two friends are not interchangeable, and this
    /// is what lets a re-opened picker recognise the friend already armed
    /// instead of silently dropping the selection.
    private func targetsContain(_ target: BestEffortStore.GhostTarget) -> Bool {
        targets.contains {
            switch ($0, target) {
            case (.recordedBest, .recordedBest), (.personalRecord, .personalRecord):
                return true
            case (.custom, .custom):
                return true
            case (.friend(let a, _, _), .friend(let b, _, _)):
                return a == b
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
                Circle().fill(accent.opacity(0.22)).frame(width: 64, height: 64)
                GhostSprite(size: 34, color: accent, glancesBack: true)
            }
            Text(headerTitle)
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

    private var headerTitle: String {
        armedDistanceMiles > 1.001
            ? "Race a ghost over \(BestEffortStore.distanceLabel(armedDistanceMiles))"
            : "Race a ghost for one mile"
    }

    // MARK: - Targets

    private var targetList: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            Text("What are you chasing?")
                .font(MADTheme.Typography.headline)
                .foregroundStyle(MADTheme.Colors.madWhite)

            ForEach(Array(targets.enumerated()), id: \.offset) { index, target in
                // The friend block gets its own heading so the list reads as
                // two ideas — your times, then theirs — instead of one long
                // undifferentiated column.
                if case .friend = target, isFirstFriendRow(at: index) {
                    Text("Chase a friend")
                        .font(MADTheme.Typography.headline)
                        .foregroundStyle(MADTheme.Colors.madWhite)
                        .padding(.top, MADTheme.Spacing.sm)
                }
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

    /// True for the first friend in `targets` — drives the section heading.
    private func isFirstFriendRow(at index: Int) -> Bool {
        targets.firstIndex { if case .friend = $0 { return true }; return false } == index
    }

    private func targetRow(_ target: BestEffortStore.GhostTarget) -> some View {
        let info = rowInfo(target)
        let isOn = matchesSelection(target)
        return Button {
            MADHaptics.tap()
            withAnimation(MADTheme.Animation.quick) { selection = target }
        } label: {
            HStack(spacing: MADTheme.Spacing.md) {
                // A friend gets their face where the other targets get a
                // symbol — it's the whole reason this row reads differently.
                if case .friend(let id, _, _) = target,
                    let friend = friends.first(where: { $0.user_id == id })
                {
                    AvatarView(
                        name: friend.avatarName,
                        imageURL: friend.profile_image_url,
                        size: 30
                    )
                    .overlay(
                        Circle().strokeBorder(
                            isOn ? accent : Color.clear, lineWidth: 1.5)
                    )
                    .frame(width: 30)
                } else {
                    Image(systemName: info.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isOn ? accent : MADTheme.Colors.madWhite.opacity(0.5))
                        .frame(width: 30)
                }

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
        // By ID. Matching on kind here would highlight EVERY friend row at
        // once, since they're all `.friend`.
        case (.friend(let a, _, _), .friend(let b, _, _)):
            return a == b
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
        case .friend(_, let seconds, let name):
            return (
                "person.fill",
                name,
                // Same caveat the footnote gives for the user's own PR: this is
                // their fastest mile from ANY synced workout, so it can be
                // faster than anything they've tracked in this app.
                "Their fastest mile from any synced workout. Held at one even pace.",
                BestEffortStore.formatSeconds(seconds)
            )
        case .custom:
            let detail: String
            if customMiles > 1.001 {
                detail = "Any distance and pace you like — a 5K goal, a long-run pace."
            } else if isRun {
                detail = "Any distance and pace you like — a goal pace, or a friend's time."
            } else {
                detail = "Any distance and pace you like. Works from your very first walk."
            }
            return (
                "slider.horizontal.3",
                "A time you set",
                detail,
                BestEffortStore.formatClock(customTotalSeconds)
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
        VStack(spacing: MADTheme.Spacing.md) {
            distanceChooser
            entryModeToggle

            HStack(spacing: 0) {
                // In per-mile mode this starts at 4, not 2: everything below
                // 4:01 a mile is rejected as a drive, so offering those minutes
                // was offering a dead end. 4:00 exactly stays selectable and
                // simply disables the button, the same way the 40:01 corner
                // already does.
                wheel(value: $customMinutes, range: minutesRange, unit: "min")
                Text(":")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.5))
                wheel(value: $customSeconds, range: 0...59, unit: "sec")
            }
            .frame(height: 130)

            VStack(spacing: 4) {
                // The number they did NOT type. Both readings are the target,
                // and which one is useful depends entirely on whether they're
                // pacing the race or checking they can hold it.
                Text(derivedCaption)
                    .font(MADTheme.Typography.smallBold)
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.85))
                Text(paceHint)
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MADTheme.Spacing.md)
        .frame(maxWidth: .infinity)
        .ghostRaceSurface(selected: false, accent: accent)
    }

    // MARK: Distance

    private var distanceChooser: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            Text("How far?")
                .font(MADTheme.Typography.caption)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MADTheme.Spacing.sm) {
                    ForEach(BestEffortStore.targetDistanceChoices, id: \.self) { miles in
                        distanceChip(miles)
                    }
                }
                // Room for the selected chip's 2pt stroke, which would
                // otherwise be shaved off at either end of the scroll.
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func distanceChip(_ miles: Double) -> some View {
        let isOn = abs(miles - customDistance) < 0.005
        return Button {
            guard !isOn else { return }
            MADHaptics.tap()
            // Changing the DISTANCE holds the PACE, so 8:00/mi over a mile
            // becomes 8:00/mi over a 5K rather than an 8:00 5K. In per-mile
            // mode the wheels already say that and must not move.
            let raw = Double(customMinutes * 60 + customSeconds)
            let previousMiles = customMiles
            withAnimation(MADTheme.Animation.quick) { customDistance = miles }
            if entryMode == .total, previousMiles > 0 {
                setWheelSeconds(
                    raw / previousMiles * miles, mode: .total, miles: miles)
            }
        } label: {
            Text(BestEffortStore.distanceLabel(miles))
                .font(MADTheme.Typography.smallBold)
                .foregroundStyle(
                    isOn ? MADTheme.Colors.madWhite : MADTheme.Colors.madWhite.opacity(0.7)
                )
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.vertical, MADTheme.Spacing.sm)
                .background(
                    Capsule().fill(isOn ? accent.opacity(0.28) : Color.white.opacity(0.10))
                )
                .overlay(
                    Capsule().strokeBorder(
                        isOn ? accent : Color.white.opacity(0.18),
                        lineWidth: isOn ? 2 : 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Total vs per-mile

    /// Built from the same capsule vocabulary as the distance chips rather
    /// than `.pickerStyle(.segmented)` — a UIKit segmented control renders
    /// light-on-light over both gradients this screen is hosted on.
    private var entryModeToggle: some View {
        HStack(spacing: 4) {
            entryModeSegment(.total, title: "Total time")
            entryModeSegment(.perMile, title: "Per mile")
        }
        .padding(4)
        .background(Capsule().fill(Color.white.opacity(0.10)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
    }

    private func entryModeSegment(_ mode: CustomEntryMode, title: String) -> some View {
        let isOn = entryMode == mode
        return Button {
            guard !isOn else { return }
            MADHaptics.tap()
            // Switching how the target is STATED must carry the value over,
            // not clear it: someone who has dialled in 8:00/mi and then wants
            // to see it as a total is asking about the number they already
            // set, and handing them back a default would answer a different
            // question.
            let raw = Double(customMinutes * 60 + customSeconds)
            let carried = mode == .total ? raw * customMiles : raw / customMiles
            let miles = customMiles
            withAnimation(MADTheme.Animation.quick) { entryMode = mode }
            setWheelSeconds(carried, mode: mode, miles: miles)
        } label: {
            Text(title)
                .font(MADTheme.Typography.smallBold)
                .foregroundStyle(
                    isOn ? MADTheme.Colors.madWhite : MADTheme.Colors.madWhite.opacity(0.6)
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, MADTheme.Spacing.sm)
                .background(Capsule().fill(isOn ? accent.opacity(0.28) : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// The other reading of the same target: type a pace, see the total; type
    /// a total, see the pace.
    private var derivedCaption: String {
        if customMiles <= 1.001 {
            return "\(BestEffortStore.formatSeconds(customPerMileSeconds)) for the mile."
        }
        let label = BestEffortStore.distanceLabel(customMiles)
        if entryMode == .total {
            return "\(BestEffortStore.formatSeconds(customPerMileSeconds))/mi over \(label)."
        }
        return "\(BestEffortStore.formatClock(customTotalSeconds)) total for \(label)."
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
        // Compared PER MILE, always: a 5K total is a bigger number than a mile
        // best by construction, and holding the two side by side would call
        // every long target "easier" when it is nothing of the kind.
        let perMile = customPerMileSeconds
        guard let reference = referenceSeconds else {
            return "That's a \(BestEffortStore.formatSeconds(perMile)) mile pace."
        }
        let unit = customMiles > 1.001 ? "s/mi" : "s"
        let delta = Int((reference - perMile).rounded())
        if abs(delta) < 3 { return "Just about dead even with your best mile." }
        return delta > 0
            ? "\(delta)\(unit) faster than your best mile — a real push."
            : "\(-delta)\(unit) easier than your best mile — a comfortable target."
    }

    private var referenceSeconds: Double? {
        BestEffortStore.best(for: activityKey)?.seconds
            ?? (isRun ? seedPaceSeconds : nil)
    }

    // MARK: - Coach

    /// Lives HERE rather than in app settings because this is the screen where
    /// someone decides to race — the only moment the setting means anything,
    /// and the moment they'll look for it after hearing a voice they didn't
    /// expect. Default on; one tap off, and it stays off.
    private var coachToggle: some View {
        Toggle(isOn: $coachEnabled) {
            HStack(spacing: MADTheme.Spacing.md) {
                Image(systemName: coachEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(coachEnabled ? accent : MADTheme.Colors.madWhite.opacity(0.5))
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Coach")
                        .font(MADTheme.Typography.bodyBold)
                        .foregroundStyle(MADTheme.Colors.madWhite)
                    Text("Calls out your pace and splits as you run, the halfway turnaround, and — when you're racing — every lead change.")
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // Brand red, deliberately NOT `accent`. iOS draws a switch's knob white
        // no matter what, and this content is hosted on the tracker's red
        // gradient with `accent: .white` — so tinting with the accent produced a
        // white knob on a white track: a plain white pill that didn't read as a
        // switch at all. Any track colour here has to contrast with that knob.
        .tint(MADTheme.Colors.madRed)
        .padding(MADTheme.Spacing.md)
        .ghostRaceSurface(selected: false, accent: accent)
        .onChange(of: coachEnabled) { _, _ in MADHaptics.tap() }
    }

    /// How often the coach calls distance + pace. Hidden while the coach is
    /// off — a cadence for something silent is a setting that can only
    /// confuse. "Off" is a real choice here and keeps the splits, the
    /// milestones and the race lines, which are event-driven rather than
    /// metronomic.
    @ViewBuilder
    private var coachIntervalChooser: some View {
        if coachEnabled {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                Text("Call out my pace every")
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: MADTheme.Spacing.sm) {
                        ForEach(GhostCoach.intervalChoices, id: \.self) { miles in
                            coachIntervalChip(miles)
                        }
                    }
                    // Room for the selected chip's stroke, same as the
                    // distance row above.
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                }

                Text(
                    coachInterval > 0
                        ? "Every mile you'll also hear that mile's split and your overall average."
                        : "You'll still hear every mile split and your overall average."
                )
                .font(MADTheme.Typography.caption)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MADTheme.Spacing.md)
            .ghostRaceSurface(selected: false, accent: accent)
        }
    }

    private func coachIntervalChip(_ miles: Double) -> some View {
        let isOn = abs(miles - coachInterval) < 0.005
        return Button {
            guard !isOn else { return }
            MADHaptics.tap()
            withAnimation(MADTheme.Animation.quick) { coachInterval = miles }
        } label: {
            Text(Self.intervalLabel(miles))
                .font(MADTheme.Typography.smallBold)
                .foregroundStyle(
                    isOn ? MADTheme.Colors.madWhite : MADTheme.Colors.madWhite.opacity(0.7)
                )
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.vertical, MADTheme.Spacing.sm)
                .background(
                    Capsule().fill(isOn ? accent.opacity(0.28) : Color.white.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
    }

    private static func intervalLabel(_ miles: Double) -> String {
        if miles <= 0 { return "Off" }
        if abs(miles - 0.25) < 0.005 { return "¼ mi" }
        if abs(miles - 0.5) < 0.005 { return "½ mi" }
        if abs(miles - 1.0) < 0.005 { return "1 mi" }
        return String(format: "%.1f mi", miles)
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
            explainerRow("flag.checkered", lockInLine)
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

    /// Where the race ends — the mile unless a custom target moved it.
    private var finishLineText: String {
        armedDistanceMiles > 1.001
            ? BestEffortStore.distanceLabel(armedDistanceMiles)
            : "1.00 mi"
    }

    private var lockInLine: String {
        let line = finishLineText
        return isRun
            ? "It locks in the moment you hit \(line) — the rest of the run is yours."
            : "It locks in the moment you hit \(line) — the rest of the walk is yours."
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
                    Text(armedButtonTitle)
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
        case .custom(let seconds, _): return seconds
        case .friend(_, let seconds, _): return seconds
        }
    }

    /// "Race 8:42" for a mile; a longer target has to name the distance, or
    /// "Race 24:48" is a time with nothing attached to it.
    private var armedButtonTitle: String {
        guard armedDistanceMiles > 1.001 else {
            return "Race \(BestEffortStore.formatSeconds(armedSeconds))"
        }
        let label = BestEffortStore.distanceLabel(armedDistanceMiles)
        let clock = BestEffortStore.formatClock(armedSeconds)
        return "Race \(label) in \(clock)"
    }

    private func commit() {
        guard armedIsValid else { return }
        if case .custom(let seconds, let distanceMiles) = armedTarget {
            BestEffortStore.saveCustomTarget(
                seconds: seconds, distanceMiles: distanceMiles, for: activityKey)
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
