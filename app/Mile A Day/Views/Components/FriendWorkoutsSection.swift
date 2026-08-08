//
//  FriendWorkoutsSection.swift
//  Mile A Day
//
//  Component for displaying a friend's recent workouts
//

import SwiftUI

struct FriendWorkoutsSection: View {
    let workouts: [FriendWorkout]
    var onWorkoutTap: ((FriendWorkout) -> Void)? = nil
    /// The owner sees more than a visitor: which app wrote each workout, and
    /// whether one is being left out of their totals as a cross-app duplicate.
    /// A visitor gets the source chip only — someone else's duplicate is not
    /// theirs to resolve.
    var isOwnProfile: Bool = false
    /// Needed to write the owner's decision back. Nil disables the control.
    var ownerUserId: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            // Section Header
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.title3)
                    .foregroundColor(MADTheme.Colors.madRed)
                Text("Recent Workouts")
                    .font(MADTheme.Typography.title3)
                    .foregroundColor(MADTheme.Colors.primaryText)
                Spacer()
                Text("\(workouts.count)")
                    .font(MADTheme.Typography.smallBold)
                    .foregroundColor(MADTheme.Colors.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                    )
            }
            .padding(.top, MADTheme.Spacing.md)

            // Workouts List
            VStack(spacing: MADTheme.Spacing.sm) {
                ForEach(workouts) { workout in
                    if let onTap = onWorkoutTap {
                        Button {
                            onTap(workout)
                        } label: {
                            FriendWorkoutRow(workout: workout, showChevron: true,
                                             isOwnProfile: isOwnProfile, ownerUserId: ownerUserId)
                        }
                        .buttonStyle(ScaleButtonStyle())
                    } else {
                        FriendWorkoutRow(workout: workout,
                                         isOwnProfile: isOwnProfile, ownerUserId: ownerUserId)
                    }
                }
            }
            .padding(.bottom, MADTheme.Spacing.md)
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .madLiquidGlass()
    }
}

/// A friend's workout in the EXACT row grammar of the dashboard's own
/// WorkoutRow (accent icon chip, verb + hero distance, duration • pace,
/// date/time trailing) — a workout reads the same no matter whose it is.
struct FriendWorkoutRow: View {
    let workout: FriendWorkout
    var showChevron: Bool = false
    // Declared AFTER the existing properties on purpose. Swift's memberwise
    // init takes arguments in declaration order, so putting these first made
    // every existing call site a compile error ("argument 'isOwnProfile' must
    // precede argument 'workout'"). New optional parameters go last.
    var isOwnProfile: Bool = false
    var ownerUserId: String? = nil

    /// Local override so the row updates the instant the owner overrules the
    /// duplicate call, rather than waiting for the next profile refresh.
    @State private var overruled = false
    @State private var isDeciding = false

    var body: some View {
        VStack(spacing: 8) {
            rowBody
            // Stated, never silent. The exclusion is correct — the same walk
            // written by two apps is one walk — but a workout is the user's own
            // record of something they did, so taking it out of their total
            // without saying so is worse than the wrong number. The reversal
            // sits in the same breath as the explanation, and it is durable:
            // the server stores the answer on the workout, so the recompute
            // that runs on every sync re-derives it instead of undoing it.
            if showsDuplicateNotice {
                DuplicateNoticeView(
                    attribution: WorkoutAttribution(bundleId: workout.sourceBundleId),
                    isBusy: isDeciding,
                    onCountAnyway: countAnyway
                )
            }
        }
    }

    private var rowBody: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(workoutColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: workoutIcon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(workoutColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                // fixedSize, not lineLimit alone. The verb had no layout
                // priority while the distance beside it had `.layoutPriority(1)`,
                // so on a tight row SwiftUI compressed "Walked" first — to a
                // single glyph plus an ellipsis, which rendered as a stray
                // apostrophe before the number. These are two short words that
                // must be whole or absent; there is nothing useful in half of
                // "Walked".
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(verb)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(MADTheme.Colors.secondaryText)
                        .lineLimit(1)
                    Text(workout.distance.milesFormatted)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(MADTheme.Colors.primaryText)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
                HStack(spacing: 5) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.orange)
                    // Scale, never clip. As one lineLimit(1) Text this cut its
                    // own tail when space ran short — and the tail is the pace,
                    // so "23:11 • 23:11 /mi" became "23:11 •…", which says less
                    // than showing nothing would. Tightening + a scale floor
                    // keeps the whole string on the narrowest phone.
                    Text(paceText == nil
                         ? workout.formattedDuration
                         : "\(workout.formattedDuration) \u{2022} \(paceText!)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(MADTheme.Colors.secondaryText)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .minimumScaleFactor(0.75)
                }

                // Identical chips to the owner's own WorkoutRow — a friend's run
                // reads the same as yours. Route/photo come from the server
                // (`has_route`/`has_photo`); older servers omit them and the
                // chips simply don't draw.
                // Same overflow trap as the owner's own row, and worse here:
                // Manual + Route + Photo + a named source is four fixed-size
                // chips on one line. Each publishes a width no ancestor can
                // shrink, so the row can end up demanding more than the screen
                // — which a ScrollView answers by centring and clipping,
                // silently eating the screen's side margins. Stack instead.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { rowChips(truncating: false) }
                    VStack(alignment: .leading, spacing: 4) { rowChips(truncating: true) }
                }
            }

            .layoutPriority(1)

            Spacer(minLength: MADTheme.Spacing.xs)

            VStack(alignment: .trailing, spacing: 2) {
                Text(dateLabel)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(MADTheme.Colors.primaryText)
                if let time = startTimeLabel {
                    Text(time)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(MADTheme.Colors.secondaryText)
                }
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MADTheme.Colors.secondaryText)
            }
        }
        .padding(MADTheme.Spacing.md)
        // Dimmed while it isn't counting, so the state is legible before you
        // read a word of it.
        .opacity(showsDuplicateNotice ? 0.55 : 1)
        .background(Color.white.opacity(0.05))
        .cornerRadius(MADTheme.CornerRadius.medium)
    }

    /// One definition behind both `ViewThatFits` candidates — they must differ
    /// in arrangement only, never in which chips they show.
    @ViewBuilder
    private func rowChips(truncating: Bool) -> some View {
        WorkoutRowTags(
            source: WorkoutSource(rawValue: workout.source ?? "") ?? .healthkit,
            hasRoute: workout.hasRoute == true,
            hasPhoto: workout.hasPhoto == true,
            routeColor: workoutColor
        )
        // Which app actually wrote this. Silent for Mile A Day and Apple —
        // badging the expected sources would make the chip wallpaper and hide
        // the one case that matters.
        WorkoutSourceChip(
            attribution: WorkoutAttribution(bundleId: workout.sourceBundleId),
            allowsTruncation: truncating
        )
    }

    /// Only on the OWNER's own list, only for the duplicate exclusion, and only
    /// while they haven't already overruled it. A visitor seeing "not counted"
    /// on someone else's workout would be told about a decision that isn't
    /// theirs to make.
    private var showsDuplicateNotice: Bool {
        isOwnProfile && !overruled
            && workout.exclusionReason == "duplicate_source"
            && workout.duplicateDecision != "count"
    }

    private func countAnyway() {
        guard let ownerUserId, !isDeciding else { return }
        isDeciding = true
        Task {
            do {
                try await DuplicateDecisionService.set(
                    userId: ownerUserId, workoutId: workout.id, decision: "count")
                MADHaptics.success()
                overruled = true
            } catch {
                MADHaptics.error()
            }
            isDeciding = false
        }
    }

    /// Feed-style verb, same as WorkoutRow's headline.
    private var verb: String {
        switch workout.workoutType.lowercased() {
        case "running": return "Ran"
        case "walking": return "Walked"
        case "hiking": return "Hiked"
        case "cycling": return "Cycled"
        default: return "Moved"
        }
    }

    /// "18:27 /mi" when distance + duration allow it — same as WorkoutRow.
    private var paceText: String? {
        guard workout.distance > 0, workout.totalDuration > 0 else { return nil }
        return "\(RunStatsStickerView.paceText(workout.totalDuration / workout.distance)) /mi"
    }

    /// Start time derived the same way WorkoutRow does it: end − duration.
    private var startDate: Date? {
        guard let end = workout.deviceEndDate, let d = RelativeTime.date(from: end) else { return nil }
        return d.addingTimeInterval(-workout.totalDuration)
    }

    private var dateLabel: String {
        if let d = startDate {
            if Calendar.current.isDateInToday(d) { return "Today" }
            if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
            return DateFormatter.workoutRowDate.string(from: d)
        }
        // No device timestamp — fall back to the server's local_date.
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: workout.date) else { return workout.formattedDate }
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        return DateFormatter.workoutRowDate.string(from: d)
    }

    private var startTimeLabel: String? {
        guard let d = startDate else { return nil }
        return DateFormatter.shortTime.string(from: d)
    }

    private var workoutIcon: String {
        switch workout.workoutType.lowercased() {
        case "running":
            return "figure.run"
        case "walking":
            return "figure.walk"
        case "cycling":
            return "bicycle"
        case "hiking":
            return "figure.hiking"
        default:
            return "figure.run"
        }
    }

    private var workoutColor: Color {
        MADTheme.workoutColor(workout.workoutType)
    }
}
