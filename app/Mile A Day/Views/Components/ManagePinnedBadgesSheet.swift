import SwiftUI

/// Sheet that lets the user pick up to 3 earned badges to pin to their profile showcase.
/// Tap to select/deselect; selection order determines pin order (1, 2, 3).
struct ManagePinnedBadgesSheet: View {
    @ObservedObject var userManager: UserManager
    @Environment(\.dismiss) private var dismiss

    @State private var selected: [String] = []
    @State private var isSaving = false
    @State private var sortOption: SortOption = .dateNewest
    @State private var saveError: String?

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
                    headerBanner

                    if !earnedBadges.isEmpty {
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
                                        toggle(badge.id)
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

    private func toggle(_ badgeId: String) {
        if let idx = selected.firstIndex(of: badgeId) {
            selected.remove(at: idx)
        } else if selected.count < maxPins {
            selected.append(badgeId)
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

private struct BadgePickerCard: View {
    let badge: Badge
    let selectionIndex: Int?
    let atCapacity: Bool
    let onTap: () -> Void

    var isSelected: Bool { selectionIndex != nil }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: medalGradientColors(for: badge),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.4), lineWidth: 1.5)
                        )
                        .shadow(color: badge.rarity.color.opacity(0.35), radius: 8, x: 0, y: 4)

                    Image(systemName: iconName(for: badge))
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.85)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    if let idx = selectionIndex {
                        ZStack {
                            Circle()
                                .fill(MADTheme.Colors.madRed)
                                .frame(width: 26, height: 26)
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            Text("\(idx)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .offset(x: 26, y: -26)
                    }
                }
                .frame(width: 90, height: 90)

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

                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 9, weight: .semibold))
                    Text(badge.dateAwarded.formattedShortDate)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.55))
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
            .opacity(atCapacity ? 0.45 : 1.0)
        }
        .buttonStyle(BadgeCardButtonStyle())
        .disabled(atCapacity)
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
