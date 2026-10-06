import SwiftUI
import UIKit

/// One pair: its picture, mileage against its replace-at target, the
/// workouts behind the number, and what you can do with it.
///
/// Reads the shoe out of `ShoeStore` by id rather than holding a copy, so an
/// edit, a new default or a workout re-assigned elsewhere shows here at once.
struct ShoeDetailView: View {
    let shoeId: String

    @Environment(\.dismiss) private var dismiss
    @State private var store = ShoeStore.shared
    @State private var workouts: [ShoeWorkout] = []
    @State private var workoutsLoaded = false
    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var isWorking = false
    @State private var actionError: String?
    @State private var cleanup: ShoeDefaultCleanup?
    /// A toggle's new position while its save is in flight, so it doesn't
    /// snap back until the server answers.
    @State private var pendingDefault: [ShoeActivity: Bool] = [:]

    private var shoe: Shoe? { store.shoe(id: shoeId) }

    var body: some View {
        ScrollView {
            if let shoe {
                VStack(spacing: MADTheme.Spacing.lg) {
                    hero(shoe)
                    mileageCard(shoe)
                    actionsCard(shoe)
                    workoutsCard(shoe)
                }
                .padding(MADTheme.Spacing.md)
                .lockedToScrollWidth()
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, MADTheme.Spacing.xl)
            }
        }
        .background(MADTheme.Colors.appBackgroundGradient.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showEdit = true }
                    .disabled(shoe == nil)
            }
        }
        .sheet(isPresented: $showEdit) {
            if let shoe {
                ShoeFormView(editing: shoe)
            }
        }
        .alert("Delete these shoes?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their mileage is deleted and the workouts they were on are left with no shoes. Retire them instead to keep the mileage.")
        }
        .alert(
            "Couldn't update your shoes",
            isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
        ) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .shoeDefaultCleanupPrompt($cleanup, onError: { actionError = $0 })
        .task { await store.refreshIfStale() }
        // Re-read the list whenever the count behind the mileage moves.
        .task(id: shoe?.workout_count) { await loadWorkouts() }
    }

    // MARK: - Hero

    private func hero(_ shoe: Shoe) -> some View {
        VStack(spacing: MADTheme.Spacing.md) {
            ShoeThumbnail(url: shoe.imageURL, size: 220, cornerRadius: 24)
                .shadow(color: .black.opacity(0.25), radius: 16, y: 8)

            VStack(spacing: 6) {
                Text(shoe.name)
                    .font(MADTheme.Typography.title2)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                if let detail = shoe.detailLine {
                    Text(detail)
                        .font(MADTheme.Typography.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                if !shoe.defaultActivities.isEmpty {
                    ShoeDefaultChip(activities: shoe.defaultActivities)
                } else if shoe.isRetired {
                    Text("RETIRED")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(0.6)
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, MADTheme.Spacing.sm)
    }

    // MARK: - Mileage

    private func mileageCard(_ shoe: Shoe) -> some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ShoeUnits.whole(shoe.total_miles))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                    Text("on these shoes")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.white.opacity(0.55))
                }
                Spacer()
                if let target = shoe.replace_at_miles {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(remainingText(shoe, target: target))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(shoe.total_miles >= target ? MADTheme.Colors.madRed : .white)
                        Text("replace at \(ShoeUnits.whole(target))")
                            .font(MADTheme.Typography.caption)
                            .foregroundColor(.white.opacity(0.55))
                    }
                }
            }

            if let wear = shoe.wearFraction {
                ShoeWearBar(fraction: wear)
            }

            HStack(spacing: 0) {
                stat("Workouts", "\(shoe.workout_count)")
                stat("First", Self.shortDate(shoe.first_used) ?? "—")
                stat("Latest", Self.shortDate(shoe.last_used) ?? "—")
            }

            if shoe.starting_miles > 0 {
                Text("Includes \(ShoeUnits.whole(shoe.starting_miles)) from before you tracked them.")
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    private func remainingText(_ shoe: Shoe, target: Double) -> String {
        let left = target - shoe.total_miles
        return left > 0 ? "\(ShoeUnits.whole(left)) left" : "Time for a new pair"
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(MADTheme.Typography.caption)
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private func actionsCard(_ shoe: Shoe) -> some View {
        VStack(spacing: 0) {
            if !shoe.isRetired {
                ForEach(ShoeActivity.allCases) { activity in
                    defaultToggleRow(shoe, activity: activity)
                    divider
                }
            }

            Button {
                update(["retired": !shoe.isRetired])
            } label: {
                actionRow(
                    icon: shoe.isRetired ? "arrow.uturn.backward.circle.fill" : "archivebox.circle.fill",
                    title: shoe.isRetired ? "Back in Rotation" : "Retire",
                    subtitle: shoe.isRetired
                        ? "Offer this pair on workouts again"
                        : "Keep the mileage, stop offering this pair",
                    tint: MADTheme.Colors.warning
                )
            }
            .buttonStyle(.plain)

            divider

            Button {
                confirmDelete = true
            } label: {
                actionRow(
                    icon: "trash.circle.fill",
                    title: "Delete",
                    subtitle: nil,
                    tint: MADTheme.Colors.madRed
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.vertical, MADTheme.Spacing.xs)
        .madLiquidGlass()
        .disabled(isWorking)
    }

    /// "Default for walks" — on: new walks get this pair; off: they get
    /// none (or whichever pair the subtitle names).
    private func defaultToggleRow(_ shoe: Shoe, activity: ShoeActivity) -> some View {
        let isOn = pendingDefault[activity] ?? shoe.isDefault(for: activity)
        let other = store.defaultShoe(for: activity)
        let subtitle = isOn
            ? "New \(activity.noun) get this pair"
            : other.map { "Now: \($0.name)" } ?? "Now: no shoes"
        return HStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: activity.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(MADTheme.workoutColor(activity.rawValue))
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Default for \(activity.noun)")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Toggle("Default for \(activity.noun)", isOn: Binding(
                get: { isOn },
                set: { setDefault($0, activity: activity) }
            ))
            .labelsHidden()
            .tint(MADTheme.Colors.success)
        }
        .padding(.vertical, 10)
    }

    private var divider: some View {
        Divider().overlay(Color.white.opacity(0.08))
    }

    private func actionRow(icon: String, title: String, subtitle: String?, tint: Color) -> some View {
        HStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    // MARK: - Workouts

    private func workoutsCard(_ shoe: Shoe) -> some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            WorkoutDetailSectionHeader(icon: "list.bullet", title: "Workouts")
            if !workoutsLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MADTheme.Spacing.sm)
            } else if workouts.isEmpty {
                Text(shoe.isRetired
                     ? "No workouts were logged in this pair."
                     : "None yet. Make it a default above, or choose this pair from any workout's details.")
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.white.opacity(0.55))
            } else {
                ForEach(workouts) { workout in
                    HStack {
                        Image(systemName: Self.icon(for: workout.workout_type))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(MADTheme.workoutColor(workout.workout_type))
                            .frame(width: 20)
                            .accessibilityHidden(true)
                        Text(Self.longDate(workout.local_date) ?? workout.local_date)
                            .font(MADTheme.Typography.small)
                            .foregroundColor(.white.opacity(0.85))
                        Spacer()
                        Text(workout.distance.distanceFormatted)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, 4)
                }
                if workouts.count >= 100 {
                    Text("Showing your latest 100.")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.white.opacity(0.45))
                }
            }
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    // MARK: - Work

    private func loadWorkouts() async {
        do {
            workouts = try await ShoeService.workouts(for: shoeId)
        } catch {
            print("[ShoeDetailView] workouts failed: \(error)")
        }
        workoutsLoaded = true
    }

    private func update(_ fields: [String: Any]) {
        isWorking = true
        Task { @MainActor in
            do {
                try await store.update(shoeId, fields: fields)
            } catch {
                actionError = error.localizedDescription
            }
            isWorking = false
        }
    }

    /// On: this pair becomes the activity's default (replacing any other).
    /// Off: the activity gets no default — the pair isn't swapped for another.
    private func setDefault(_ on: Bool, activity: ShoeActivity) {
        isWorking = true
        pendingDefault[activity] = on
        Task { @MainActor in
            do {
                cleanup = try await store.setDefault(on ? shoeId : nil, for: activity)
            } catch {
                actionError = error.localizedDescription
            }
            pendingDefault[activity] = nil
            isWorking = false
        }
    }

    private func delete() {
        isWorking = true
        Task { @MainActor in
            do {
                try await store.delete(shoeId)
                dismiss()
            } catch {
                actionError = error.localizedDescription
            }
            isWorking = false
        }
    }

    // MARK: - Formatting

    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func day(_ text: String?) -> Date? {
        guard let text else { return nil }
        return dayParser.date(from: String(text.prefix(10)))
    }

    /// "Sep 3" this year, "Sep 3, 2025" otherwise.
    static func shortDate(_ text: String?) -> String? {
        guard let date = day(text) else { return nil }
        let utc = TimeZone(identifier: "UTC") ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let sameYear = calendar.component(.year, from: date) == Calendar.current.component(.year, from: Date())
        let style = Date.FormatStyle(timeZone: utc).month(.abbreviated).day()
        return date.formatted(sameYear ? style : style.year())
    }

    /// "Fri, Sep 3, 2026".
    static func longDate(_ text: String?) -> String? {
        guard let date = day(text) else { return nil }
        let utc = TimeZone(identifier: "UTC") ?? .current
        return date.formatted(Date.FormatStyle(timeZone: utc).weekday(.abbreviated).month(.abbreviated).day().year())
    }

    private static func icon(for type: String) -> String {
        switch type {
        case "running": return "figure.run"
        case "hiking": return "figure.hiking"
        default: return "figure.walk"
        }
    }
}
