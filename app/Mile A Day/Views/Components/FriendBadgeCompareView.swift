import SwiftUI

/// Friend-profile badge surface:
/// - Shows the friend's pinned showcase (3 slots).
/// - Lists the full catalog with each entry shown as owned (vivid) or locked (greyed) for the friend,
///   so the viewer can see at a glance what they share and what's left to earn.
struct FriendBadgeCompareView: View {
    let ownerDisplayName: String
    /// Friend's earned badges (already converted with pinSlot populated).
    let earnedBadges: [Badge]
    /// Public catalog (excludes hidden badges the viewer hasn't seen).
    let catalogBadges: [Badge]
    /// Optional: badges the local viewer has earned. Used to compute the "you don't have" highlight.
    let viewerEarnedBadgeIds: Set<String>

    @State private var selectedFilter: CompareFilter = .all
    @State private var selectedBadge: Badge?
    @State private var isShowingDetail = false

    enum CompareFilter: String, CaseIterable, Hashable {
        case all = "All"
        case theyHave = "They have"
        case youMissing = "You're missing"

        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .theyHave: return "checkmark.seal.fill"
            case .youMissing: return "questionmark.circle"
            }
        }
    }

    private var earnedById: [String: Badge] {
        Dictionary(uniqueKeysWithValues: earnedBadges.map { ($0.id, $0) })
    }

    private var pinned: [Badge] {
        earnedBadges
            .filter { $0.pinSlot != nil }
            .sorted { ($0.pinSlot ?? 0) < ($1.pinSlot ?? 0) }
    }

    private var ownedCount: Int { earnedBadges.filter { !$0.isHidden }.count }
    private var totalVisibleCount: Int { catalogBadges.count }

    /// Friend's earned hidden badges that aren't in the public catalog. Appended so the friend
    /// gets credit for them, without leaking the existence of unearned hidden badges.
    private var earnedHidden: [Badge] {
        earnedBadges.filter { $0.isHidden && !catalogBadges.contains(where: { c in c.id == $0.id }) }
    }

    /// Merged display list for the grid: catalog entries (resolved as owned or locked) + any earned-only hidden.
    private var allDisplayBadges: [Badge] {
        var list: [Badge] = []
        for cat in catalogBadges {
            if let earned = earnedById[cat.id] {
                list.append(earned)
            } else {
                var locked = cat
                locked.isLocked = true
                locked.isNew = false
                list.append(locked)
            }
        }
        list.append(contentsOf: earnedHidden)
        return list
    }

    private var filteredBadges: [Badge] {
        switch selectedFilter {
        case .all:
            return allDisplayBadges
        case .theyHave:
            return allDisplayBadges.filter { !$0.isLocked }
        case .youMissing:
            // Friend has it, viewer doesn't.
            return allDisplayBadges.filter { !$0.isLocked && !viewerEarnedBadgeIds.contains($0.id) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            PinnedBadgesShowcase(
                pinnedBadges: pinned,
                onManageTapped: nil,
                onBadgeTapped: { badge in
                    selectedBadge = badge
                    isShowingDetail = true
                },
                ownerDisplayName: ownerDisplayName
            )

            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                HStack(spacing: MADTheme.Spacing.sm) {
                    Image(systemName: "rosette")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MADTheme.Colors.redGradient)
                    Text("Medals")
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(ownedCount) / \(totalVisibleCount)")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(CompareFilter.allCases, id: \.self) { filter in
                            CompareFilterChip(
                                title: filter.rawValue,
                                icon: filter.icon,
                                isSelected: selectedFilter == filter
                            ) {
                                withAnimation(.spring(response: 0.3)) {
                                    selectedFilter = filter
                                }
                            }
                        }
                    }
                }

                if filteredBadges.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                        spacing: 16
                    ) {
                        ForEach(filteredBadges, id: \.id) { badge in
                            Button {
                                selectedBadge = badge
                                isShowingDetail = true
                            } label: {
                                ZStack(alignment: .topLeading) {
                                    PremiumBadgeCard(badge: badge)
                                    if !badge.isLocked && !viewerEarnedBadgeIds.contains(badge.id) {
                                        youDontHaveTag
                                    }
                                }
                            }
                            .buttonStyle(BadgeCardButtonStyle())
                        }
                    }
                }
            }
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass()
        }
        .navigationDestination(isPresented: $isShowingDetail) {
            if let badge = selectedBadge {
                FriendBadgeDetailView(badge: badge, ownerDisplayName: ownerDisplayName)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: selectedFilter == .youMissing ? "checkmark.circle" : "trophy")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.3))
            Text(emptyStateText)
                .font(MADTheme.Typography.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MADTheme.Spacing.xl)
    }

    private var emptyStateText: String {
        switch selectedFilter {
        case .all: return "No medals yet."
        case .theyHave: return "\(ownerDisplayName) hasn't earned any medals yet."
        case .youMissing: return "You're all caught up — no medals here that you haven't earned."
        }
    }

    private var youDontHaveTag: some View {
        Text("YOU'RE MISSING")
            .font(.system(size: 8, weight: .black, design: .rounded))
            .tracking(0.6)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(MADTheme.Colors.madRed)
            )
            .padding(6)
    }
}

private struct CompareFilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.6))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isSelected ? MADTheme.Colors.madRed : Color.white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }
}

/// Lightweight read-only badge detail for friend profiles (the existing `BadgeDetailView`
/// is tightly coupled to the local user's `UserManager`).
private struct FriendBadgeDetailView: View {
    let badge: Badge
    let ownerDisplayName: String

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: MADTheme.Spacing.lg) {
                    ZStack {
                        if !badge.isLocked {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [badge.rarity.color.opacity(0.4), badge.rarity.color.opacity(0)],
                                        center: .center,
                                        startRadius: 30,
                                        endRadius: 100
                                    )
                                )
                                .frame(width: 200, height: 200)
                        }

                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: badge.isLocked
                                        ? [Color(white: 0.25), Color(white: 0.15)]
                                        : medalGradientColors(for: badge),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 140, height: 140)
                            .overlay(
                                Circle()
                                    .stroke(
                                        badge.isLocked ? Color.white.opacity(0.1) : Color.white.opacity(0.5),
                                        lineWidth: 3
                                    )
                            )
                            .shadow(color: badge.isLocked ? .clear : badge.rarity.color.opacity(0.4), radius: 18, x: 0, y: 8)

                        Image(systemName: badge.isLocked ? "lock.fill" : iconName(for: badge))
                            .font(.system(size: 50, weight: .semibold))
                            .foregroundColor(badge.isLocked ? .white.opacity(0.35) : .white)
                    }
                    .padding(.top, MADTheme.Spacing.lg)

                    VStack(spacing: 6) {
                        Text(badge.name)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)

                        Text(badge.rarity.rawValue.uppercased())
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .tracking(1.5)
                            .foregroundColor(badge.rarity.color)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(badge.rarity.color.opacity(0.15)))
                    }

                    Text(badge.description)
                        .font(MADTheme.Typography.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, MADTheme.Spacing.lg)

                    if !badge.isLocked {
                        VStack(spacing: 4) {
                            Text("EARNED BY \(ownerDisplayName.uppercased())")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .tracking(1.2)
                                .foregroundColor(.secondary)
                            Text(badge.dateAwarded.formattedShortDate)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        .padding(.top, MADTheme.Spacing.sm)
                    } else {
                        Text("\(ownerDisplayName) hasn't earned this yet.")
                            .font(MADTheme.Typography.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, MADTheme.Spacing.sm)
                    }

                    Spacer(minLength: 60)
                }
                .padding(.horizontal, MADTheme.Spacing.md)
            }
        }
        .navigationTitle(badge.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
