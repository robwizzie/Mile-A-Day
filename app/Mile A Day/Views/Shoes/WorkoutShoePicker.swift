import SwiftUI

/// Which pair a workout was done in, and the control to change it. Shared by
/// the workout detail card and the recap chip.
@MainActor
@Observable
final class WorkoutShoeChoice {
    let workoutId: String
    /// Which default the workout takes — nil when it isn't on foot.
    let activity: ShoeActivity?
    private(set) var shoeId: String?
    private(set) var loaded = false
    private(set) var isSaving = false
    private(set) var error: String?

    init(workoutId: String, activity: ShoeActivity?) {
        self.workoutId = workoutId
        self.activity = activity
    }

    /// The server's answer, which for a workout that hasn't synced yet is the
    /// default it WILL be stamped with for its activity — so the recap shows
    /// the right pair (or none) before HealthKit has handed it to the sync.
    func load() async {
        do {
            let assignment = try await ShoeService.assignment(forWorkout: workoutId, activity: activity)
            shoeId = assignment.shoe_id
        } catch {
            print("[WorkoutShoeChoice] load failed: \(error)")
            // Offline: the activity's default is still the best guess.
            if !loaded { shoeId = activity.flatMap { ShoeStore.shared.defaultShoe(for: $0)?.shoe_id } }
        }
        loaded = true
    }

    /// `nil` = "no shoes". Optimistic, rolled back if the save fails.
    func choose(_ newId: String?) {
        guard newId != shoeId || !loaded else { return }
        let previous = shoeId
        shoeId = newId
        loaded = true
        error = nil
        isSaving = true
        Task { @MainActor in
            do {
                let saved = try await ShoeService.setShoe(newId, forWorkout: workoutId)
                shoeId = saved.shoe_id
                ShoeStore.shared.workoutAssignmentChanged()
            } catch {
                shoeId = previous
                self.error = "Couldn't save — try again."
            }
            isSaving = false
        }
    }
}

/// The options menu: pairs in rotation, plus a retired pair if it's the one
/// on this workout (so a past run still shows what it was done in), plus
/// "No shoes".
private struct ShoeMenuItems: View {
    let store: ShoeStore
    let choice: WorkoutShoeChoice

    private var options: [Shoe] {
        var list = store.active
        if let current = store.shoe(id: choice.shoeId), current.isRetired {
            list.append(current)
        }
        return list
    }

    var body: some View {
        ForEach(options) { shoe in
            Button {
                choice.choose(shoe.shoe_id)
            } label: {
                if shoe.shoe_id == choice.shoeId {
                    Label(shoe.name, systemImage: "checkmark")
                } else {
                    Text(shoe.name)
                }
            }
        }
        Divider()
        Button {
            choice.choose(nil)
        } label: {
            if choice.shoeId == nil {
                Label("No shoes", systemImage: "checkmark")
            } else {
                Text("No shoes")
            }
        }
    }
}

// MARK: - Workout detail

/// The "Shoes" card on a workout's detail sheet.
struct WorkoutShoeCard: View {
    let workoutId: String
    let activity: ShoeActivity?
    /// Mirrors `WorkoutDetailView.isActive`: the swipe pager builds every
    /// page up front, so only the page on screen loads.
    var isActive: Bool = true

    @State private var store = ShoeStore.shared
    @State private var choice: WorkoutShoeChoice
    @State private var showAdd = false

    init(workoutId: String, activity: ShoeActivity?, isActive: Bool = true) {
        self.workoutId = workoutId
        self.activity = activity
        self.isActive = isActive
        _choice = State(initialValue: WorkoutShoeChoice(workoutId: workoutId, activity: activity))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            WorkoutDetailSectionHeader(icon: ShoeSymbol.filled, title: "Shoes")

            if !store.hasLoaded || (!choice.loaded && !store.shoes.isEmpty) {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if store.shoes.isEmpty {
                noShoes
            } else {
                Menu {
                    ShoeMenuItems(store: store, choice: choice)
                } label: {
                    selectedRow
                }
                .disabled(choice.isSaving)
                if let error = choice.error {
                    Text(error)
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(MADTheme.Colors.madRed)
                }
            }
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
        .sheet(isPresented: $showAdd) {
            // The pair you just added is the one you wore on this workout —
            // that's why you added it from here.
            ShoeFormView(onSaved: { shoe in choice.choose(shoe.shoe_id) })
        }
        .task(id: isActive) {
            guard isActive else { return }
            await store.refreshIfStale()
            if !store.shoes.isEmpty { await choice.load() }
        }
    }

    private var selectedRow: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            if let shoe = store.shoe(id: choice.shoeId) {
                ShoeThumbnail(url: shoe.imageURL, size: 44, cornerRadius: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(shoe.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text("\(ShoeUnits.whole(shoe.total_miles)) on this pair")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            } else {
                Image(systemName: ShoeSymbol.outline)
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
                Text("Choose shoes")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            Spacer()
            if choice.isSaving {
                ProgressView()
            } else {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityLabel(store.shoe(id: choice.shoeId).map { "Shoes: \($0.name)" } ?? "Choose shoes")
    }

    private var noShoes: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            Text("Add your shoes to track how many miles each pair has.")
                .font(MADTheme.Typography.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Add") { showAdd = true }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .buttonStyle(.bordered)
                .tint(MADTheme.Colors.madRed)
        }
    }
}

// MARK: - Recap

/// "Shoes: Pegasus 41 ⌄" on the post-workout recap, for whoever rotates
/// pairs. Draws nothing for someone who hasn't added any shoes — the recap
/// host loads the store, so this view needs no lifecycle of its own to
/// decide that.
struct RecapShoePicker: View {
    let workoutId: String
    let activity: ShoeActivity

    @State private var store = ShoeStore.shared
    @State private var choice: WorkoutShoeChoice

    init(workoutId: String, activity: ShoeActivity) {
        self.workoutId = workoutId
        self.activity = activity
        _choice = State(initialValue: WorkoutShoeChoice(workoutId: workoutId, activity: activity))
    }

    var body: some View {
        if !store.active.isEmpty {
            Menu {
                ShoeMenuItems(store: store, choice: choice)
            } label: {
                HStack(spacing: 10) {
                    ShoeThumbnail(url: store.shoe(id: choice.shoeId)?.imageURL, size: 34, cornerRadius: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("SHOES")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .tracking(0.8)
                            .foregroundColor(.white.opacity(0.6))
                        Text(store.shoe(id: choice.shoeId)?.name ?? (choice.loaded ? "No shoes" : "…"))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if choice.isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
                .contentShape(Rectangle())
            }
            .disabled(choice.isSaving)
            .task(id: workoutId) { await choice.load() }
        }
    }
}
