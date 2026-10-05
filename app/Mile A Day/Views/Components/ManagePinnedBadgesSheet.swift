import SwiftUI

/// Sheet that lets the user pick up to 3 earned badges to pin to their profile showcase.
/// The picks sit in a FIXED strip at the top — the showcase as it will read,
/// slot 1 → 3 — where tapping one removes it; the grid below picks. Selection
/// order is pin order. A full showcase dims the rest of the grid, and tapping
/// a dimmed medal says why (and shakes the strip) rather than doing nothing.
struct ManagePinnedBadgesSheet: View {
    @ObservedObject var userManager: UserManager
    @Environment(\.dismiss) private var dismiss

    @State private var selected: [String] = []
    @State private var isSaving = false
    @State private var sortOption: SortOption = .dateNewest
    @State private var saveError: String?
    /// Bumped when a pick is refused because the showcase is full — drives the
    /// strip's shake and the hint's flash.
    @State private var capacityNudges = 0
    @State private var hintFlash = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum SortOption: String, CaseIterable, Hashable {
        case dateNewest = "Newest"
        case dateOldest = "Oldest"
        case rarity = "Rarity"

        var icon: String {
            switch self {
            case .dateNewest: return "clock.arrow.circlepath"
            case .dateOldest: return "clock"
            case .rarity: return "sparkles"
            }
        }
    }

    /// Rarity weight for sort: higher = rarer, listed first.
    private func rarityWeight(_ rarity: BadgeRarity) -> Int {
        switch rarity {
        case .legendary: return 3
        case .rare: return 2
        case .common: return 1
        }
    }

    private var earnedBadges: [Badge] {
        let pool = userManager.currentUser.badges.filter { !$0.isLocked }
        return pool.sorted { lhs, rhs in
            switch sortOption {
            case .dateNewest:
                return lhs.dateAwarded > rhs.dateAwarded
            case .dateOldest:
                return lhs.dateAwarded < rhs.dateAwarded
            case .rarity:
                let lw = rarityWeight(lhs.rarity)
                let rw = rarityWeight(rhs.rarity)
                if lw != rw { return lw > rw }
                return lhs.dateAwarded > rhs.dateAwarded
            }
        }
    }

    private let maxPins = 3

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

                VStack(spacing: 0) {
                    if earnedBadges.isEmpty {
                        headerBanner
                    } else {
                        showcaseStrip
                        sortBar
                    }

                    ScrollView {
                        if earnedBadges.isEmpty {
                            emptyState
                                .padding(.top, 60)
                                .padding(.horizontal, MADTheme.Spacing.lg)
                        } else {
                            LazyVGrid(
                                columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                                spacing: 16
                            ) {
                                ForEach(earnedBadges) { badge in
                                    BadgePickerCard(
                                        badge: badge,
                                        selectionIndex: selectionIndex(for: badge.id),
                                        atCapacity: selected.count >= maxPins && !selected.contains(badge.id)
                                    ) {
                                        pick(badge.id)
                                    }
                                }
                            }
                            .padding(MADTheme.Spacing.md)
                            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: sortOption)
                        }
                    }
                }
            }
            .navigationTitle("Showcase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(MADTheme.Colors.madRed)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        save()
                    }
                    .foregroundColor(MADTheme.Colors.madRed)
                    .fontWeight(.semibold)
                    .disabled(isSaving || !isDirty)
                }
            }
        }
        .onAppear {
            selected = userManager.pinnedBadges.map { $0.id }
        }
        .alert("Couldn't save pins", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private var headerBanner: some View {
        VStack(spacing: 6) {
            Text("Pin up to \(maxPins) medals")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text("Tap a medal to add or remove. The order you tap is the order they'll appear.")
                .font(MADTheme.Typography.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, MADTheme.Spacing.lg)

            Text("\(selected.count) of \(maxPins) selected")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(selected.isEmpty ? .secondary : MADTheme.Colors.madRed)
                .padding(.top, 4)
        }
        .padding(.vertical, MADTheme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.04))
    }

    // MARK: - Showcase strip

    /// The selected medals resolved, in slot order.
    private var selectedBadges: [Badge] {
        let byId = Dictionary(
            userManager.currentUser.badges.filter { !$0.isLocked }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return selected.compactMap { byId[$0] }
    }

    private var isFull: Bool { selected.count >= maxPins }

    private var stripHint: String {
        if isFull { return "Showcase full · remove one to swap" }
        if selected.isEmpty { return "Tap medals below to pin them, in order" }
        return "Tap a pinned medal to remove it"
    }

    private var showcaseStrip: some View {
        let badges = selectedBadges
        return VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(MADTheme.Colors.redGradient)
                    .accessibilityHidden(true)
                Text("YOUR SHOWCASE")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(1.3)
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text("\(selected.count) of \(maxPins)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(selected.isEmpty ? .white.opacity(0.45) : MADTheme.Colors.madRed)
            }

            HStack(spacing: 10) {
                ForEach(0..<maxPins, id: \.self) { slot in
                    if slot < badges.count {
                        PinnedStripSlot(badge: badges[slot], slotNumber: slot + 1) {
                            remove(badges[slot].id)
                        }
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                        .id(badges[slot].id)
                    } else {
                        PinnedStripEmptySlot(slotNumber: slot + 1)
                    }
                }
            }
            .modifier(ShakeEffect(travel: reduceMotion ? 0 : 7, shakes: CGFloat(capacityNudges)))
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: selected)

            HStack(spacing: 5) {
                Image(systemName: isFull ? "exclamationmark.circle.fill" : "hand.tap.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .accessibilityHidden(true)
                Text(stripHint)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundColor(hintFlash ? MADTheme.Colors.madRed : .white.opacity(0.5))
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.top, MADTheme.Spacing.md)
        .padding(.bottom, 12)
        .background(Color.white.opacity(0.04))
    }

    private var sortBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10, weight: .heavy))
                Text("SORT")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(1.4)
            }
            .foregroundColor(.white.opacity(0.45))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        SortChip(
                            title: option.rawValue,
                            icon: option.icon,
                            isSelected: sortOption == option
                        ) {
                            withAnimation(.spring(response: 0.3)) {
                                sortOption = option
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.04), Color.white.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)
        }
    }

    private var emptyState: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: "trophy")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.3))
            Text("No medals yet")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text("Earn medals by running, then come back to pin your favorites.")
                .font(MADTheme.Typography.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var isDirty: Bool {
        selected != userManager.pinnedBadges.map { $0.id }
    }

    private func selectionIndex(for badgeId: String) -> Int? {
        if let idx = selected.firstIndex(of: badgeId) {
            return idx + 1
        }
        return nil
    }

    /// A grid tap: unpin if pinned, pin if there's room, otherwise say why.
    private func pick(_ badgeId: String) {
        if selected.contains(badgeId) {
            remove(badgeId)
        } else if selected.count < maxPins {
            MADHaptics.tap()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                selected.append(badgeId)
            }
        } else {
            MADHaptics.warning()
            withAnimation(.linear(duration: 0.4)) { capacityNudges += 1 }
            withAnimation(.easeOut(duration: 0.15)) { hintFlash = true }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 900_000_000)
                withAnimation(.easeOut(duration: 0.4)) { hintFlash = false }
            }
        }
    }

    private func remove(_ badgeId: String) {
        guard let idx = selected.firstIndex(of: badgeId) else { return }
        MADHaptics.tap()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            _ = selected.remove(at: idx)
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        saveError = nil
        let toSave = selected
        Task { @MainActor in
            let error = await userManager.setPinnedBadges(toSave)
            isSaving = false
            if let error {
                saveError = error
                // Keep the sheet open so the user sees the error and can retry.
            } else {
                dismiss()
            }
        }
    }
}

/// One pinned medal in the strip: tap anywhere to take it off.
private struct PinnedStripSlot: View {
    let badge: Badge
    let slotNumber: Int
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            VStack(spacing: 6) {
                MedalView(badge: badge, size: 50, showShimmer: false)
                    .frame(width: 62, height: 58)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.black.opacity(0.75)))
                            .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1))
                            .offset(x: 4, y: -2)
                    }

                Text(badge.name)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(height: 28, alignment: .top)
            }
            .padding(.top, 8)
            .padding(.bottom, 6)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .frame(height: PinnedStripMetrics.height)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(badge.rarity.color.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(badge.rarity.color.opacity(0.45), lineWidth: 1)
                    )
            )
            .overlay(alignment: .topLeading) {
                PinnedSlotNumber(number: slotNumber, filled: true)
            }
        }
        .buttonStyle(BadgeCardButtonStyle())
        .accessibilityLabel("Slot \(slotNumber): \(badge.name)")
        .accessibilityHint("Removes it from your showcase")
    }
}

private struct PinnedStripEmptySlot: View {
    let slotNumber: Int

    var body: some View {
        VStack(spacing: 6) {
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundColor(.white.opacity(0.22))
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.3))
                )
                .frame(width: 62, height: 58)
            Text("Pick a medal")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.38))
                .frame(height: 28, alignment: .top)
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .frame(height: PinnedStripMetrics.height)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
        .overlay(alignment: .topLeading) {
            PinnedSlotNumber(number: slotNumber, filled: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Slot \(slotNumber): empty")
    }
}

private enum PinnedStripMetrics {
    static let height: CGFloat = 112
}

private struct PinnedSlotNumber: View {
    let number: Int
    let filled: Bool

    var body: some View {
        Text("\(number)")
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundColor(filled ? .white : .white.opacity(0.35))
            .frame(width: 18, height: 18)
            .background(Circle().fill(filled ? MADTheme.Colors.madRed : Color.white.opacity(0.06)))
            .padding(6)
            .accessibilityHidden(true)
    }
}

/// Horizontal shake; `shakes` steps by one per refused pick.
private struct ShakeEffect: GeometryEffect {
    var travel: CGFloat
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(shakes * .pi * 4), y: 0))
    }
}

private struct BadgePickerCard: View {
    let badge: Badge
    let selectionIndex: Int?
    let atCapacity: Bool
    let onTap: () -> Void

    var isSelected: Bool { selectionIndex != nil }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 9) {
                MedalView(badge: badge, size: 64, showShimmer: false)
                    .frame(width: 90, height: 78)
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(MADTheme.Colors.madRed))
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                .transition(.scale.combined(with: .opacity))
                                .accessibilityHidden(true)
                        }
                    }

                Text(badge.name)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(height: 34, alignment: .top)

                Text(badge.rarity.rawValue.uppercased())
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(1.0)
                    .foregroundColor(badge.rarity.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(badge.rarity.color.opacity(0.15)))

                Text(badge.description)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44, alignment: .top)
                    .padding(.horizontal, 2)

                Group {
                    if let idx = selectionIndex {
                        Text("PINNED · SLOT \(idx)")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .tracking(0.6)
                            .foregroundColor(MADTheme.Colors.madRed)
                    } else if atCapacity {
                        Text("Remove one to swap")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 9, weight: .semibold))
                                .accessibilityHidden(true)
                            Text(MedalStory.shortDate(badge.dateAwarded))
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.white.opacity(0.55))
                    }
                }
                .frame(height: 14)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, MADTheme.Spacing.md)
            .padding(.horizontal, MADTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(isSelected ? MADTheme.Colors.madRed.opacity(0.12) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .stroke(
                                isSelected ? MADTheme.Colors.madRed.opacity(0.6) : Color.white.opacity(0.08),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
            )
            .opacity(atCapacity ? 0.42 : 1.0)
        }
        .buttonStyle(BadgeCardButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "Unpins it" : (atCapacity ? "Showcase full. Remove one to swap." : "Pins it to your showcase"))
    }
}

private struct SortChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.72))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(chipBackground)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var chipBackground: some View {
        if isSelected {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            MADTheme.Colors.madRed,
                            MADTheme.Colors.madRed.opacity(0.82)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                )
                .shadow(color: MADTheme.Colors.madRed.opacity(0.45), radius: 8, x: 0, y: 4)
        } else {
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
    }
}
