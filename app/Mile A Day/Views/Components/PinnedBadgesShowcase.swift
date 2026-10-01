import SwiftUI
import UniformTypeIdentifiers

/// Profile showcase that displays up to 3 pinned badges side-by-side.
/// Used on both the local user's profile (with manage affordance) and friend profiles (read-only).
struct PinnedBadgesShowcase: View {
    /// Pinned badges, already ordered by pin slot ascending.
    let pinnedBadges: [Badge]
    /// When non-nil, an "Edit" pencil appears; tapping it invokes this closure.
    let onManageTapped: (() -> Void)?
    /// Tapping a filled slot.
    let onBadgeTapped: ((Badge) -> Void)?
    /// Display name for empty-state copy. Pass `nil` for the local user (we'll say "you").
    let ownerDisplayName: String?
    /// When non-nil, filled slots become drag-to-reorder. Receives source and
    /// destination indices into the current `pinnedBadges` array. Nil on friend
    /// profiles so visitors can't rearrange.
    let onReorder: ((Int, Int) -> Void)?
    /// "How earned" summaries by badge id. Nil = resolve them here: your own
    /// profile (the one with a manage affordance) reads this account's
    /// `BadgeEarnedDetails`; a friend's has none, so their medals say rarity
    /// and date — no per-medal fetch.
    let earnedSummaries: [String: String]?

    @State private var draggingSlot: Int? = nil
    @State private var hoveredSlot: Int? = nil

    init(
        pinnedBadges: [Badge],
        onManageTapped: (() -> Void)? = nil,
        onBadgeTapped: ((Badge) -> Void)? = nil,
        ownerDisplayName: String? = nil,
        onReorder: ((Int, Int) -> Void)? = nil,
        earnedSummaries: [String: String]? = nil
    ) {
        self.pinnedBadges = pinnedBadges
        self.onManageTapped = onManageTapped
        self.onBadgeTapped = onBadgeTapped
        self.ownerDisplayName = ownerDisplayName
        self.onReorder = onReorder
        self.earnedSummaries = earnedSummaries
    }

    private static let slotCount = 3

    var body: some View {
        VStack(alignment: .leading, spacing: pinnedBadges.isEmpty ? 10 : MADTheme.Spacing.md) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MADTheme.Colors.redGradient)
                Text("Showcase")
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(.primary)
                Spacer()
                if let onManageTapped {
                    Button(action: onManageTapped) {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .semibold))
                            Text(pinnedBadges.isEmpty ? "Add" : "Edit")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(MADTheme.Colors.madRed)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(MADTheme.Colors.madRed.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                }
            }

            Group {
                if pinnedBadges.isEmpty {
                    // Nothing pinned: one quiet row of dashed sockets.
                    HStack(spacing: MADTheme.Spacing.sm) {
                        ForEach(0..<Self.slotCount, id: \.self) { _ in
                            PinnedBadgeSlotEmpty(isInteractive: onManageTapped != nil, compact: true) {
                                onManageTapped?()
                            }
                        }
                    }
                } else {
                    let summaries = resolvedSummaries
                    // Your own profile keeps its open sockets (each one is an Add);
                    // a friend's 1–2 pins sit centred at the same width instead of
                    // beside sockets they can't fill.
                    let slots = onManageTapped != nil ? Self.slotCount : pinnedBadges.count
                    HStack(spacing: MADTheme.Spacing.sm) {
                        ForEach(0..<slots, id: \.self) { slot in
                            Group {
                                if slot < pinnedBadges.count {
                                    filledSlot(at: slot, badge: pinnedBadges[slot], summaries: summaries)
                                } else {
                                    PinnedBadgeSlotEmpty(isInteractive: true, compact: false) {
                                        onManageTapped?()
                                    }
                                }
                            }
                            .frame(maxWidth: ShowcaseSlotMetrics.maxWidth)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            // Smoothly swap badges when the pinned list reorders.
            .animation(.spring(response: 0.4, dampingFraction: 0.82), value: pinnedBadges.map(\.id))

            if pinnedBadges.isEmpty {
                Text(emptyStateText)
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else if onReorder != nil && pinnedBadges.count > 1 {
                // Subtle hint so users discover the drag gesture without clutter.
                HStack(spacing: 5) {
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Hold and drag to reorder")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.4))
                .frame(maxWidth: .infinity)
            }
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    /// A single filled slot. Tappable for detail; long-press-and-drag for reorder
    /// when `onReorder` is provided (i.e., on the local user's own profile).
    @ViewBuilder
    private func filledSlot(at slot: Int, badge: Badge, summaries: [String: String]) -> some View {
        let canReorder = onReorder != nil && pinnedBadges.count > 1
        let isDragging = draggingSlot == slot
        let isDropTarget = canReorder && hoveredSlot == slot && draggingSlot != nil && draggingSlot != slot

        Group {
            if isDragging {
                // Skeleton placeholder where the dragged badge came from —
                // dashed outline tinted with the badge's rarity color, ghost
                // icon in the center, faded name underneath.
                PinnedBadgeSlotSkeleton(badge: badge)
            } else {
                Button {
                    onBadgeTapped?(badge)
                } label: {
                    PinnedBadgeSlotFilled(
                        badge: badge,
                        story: MedalStory.measuredLine(for: badge, summaries: summaries)
                    )
                }
                .buttonStyle(BadgeCardButtonStyle())
                .disabled(onBadgeTapped == nil)
            }
        }
        .scaleEffect(isDropTarget ? 1.08 : 1.0)
        .shadow(
            color: isDropTarget ? badge.rarity.color.opacity(0.55) : .clear,
            radius: 14,
            x: 0,
            y: 0
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isDragging)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isDropTarget)
        .modifier(
            ReorderableSlotModifier(
                slot: slot,
                isEnabled: canReorder,
                badge: badge,
                draggingSlot: $draggingSlot,
                hoveredSlot: $hoveredSlot,
                onReorder: onReorder
            )
        )
    }

    private var resolvedSummaries: [String: String] {
        if let earnedSummaries { return earnedSummaries }
        return onManageTapped != nil ? MedalStory.summaries() : [:]
    }

    private var emptyStateText: String {
        if onManageTapped != nil {
            return "Pin up to 3 of your favorite medals to show off on your profile."
        }
        if let name = ownerDisplayName {
            return "\(name) hasn't pinned any medals yet."
        }
        return "No pinned medals yet."
    }
}

/// Shared geometry so a filled slot, its drag skeleton and an open socket are
/// exactly the same size — the row never reflows while you drag.
enum ShowcaseSlotMetrics {
    static let height: CGFloat = 204
    static let maxWidth: CGFloat = 124
    static let medalSize: CGFloat = 60
    /// Height of the hanging medal (ribbon + loop + disc) at `medalSize`.
    static let medalBox: CGFloat = 104
}

/// A pinned medal as it hangs on the profile: ribbon and disc on a small
/// rarity-lit plinth, the name, then its story — "Legendary · Sep 30", plus
/// the measured line when the medal has one ("You ran a 7:42 mile").
struct PinnedBadgeSlotFilled: View {
    let badge: Badge
    var story: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            HangingMedal(badge: badge, size: ShowcaseSlotMetrics.medalSize, showShimmer: false)
                .frame(height: ShowcaseSlotMetrics.medalBox, alignment: .bottom)

            Text(badge.name)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(height: 30, alignment: .top)

            Text(MedalStory.rarityAndDate(badge))
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundColor(badge.rarity.color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(story ?? " ")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .frame(height: ShowcaseSlotMetrics.height)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [badge.rarity.color.opacity(0.03), badge.rarity.color.opacity(0.16)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(badge.rarity.color.opacity(0.22), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
    }
}

/// Placeholder shown in a filled slot while its badge is being dragged. Same
/// frame as a filled slot so the rest of the row doesn't reflow. Dashed
/// outline in the badge's rarity colour + a pulsing scale so the "this slot
/// is in motion" signal is loud.
private struct PinnedBadgeSlotSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let badge: Badge
    @State private var pulse: Bool = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [badge.rarity.color.opacity(0.22), .clear],
                            center: .center,
                            startRadius: 6,
                            endRadius: 42
                        )
                    )
                    .frame(width: 90, height: 90)

                Circle()
                    .strokeBorder(
                        badge.rarity.color.opacity(0.95),
                        style: StrokeStyle(lineWidth: 2, dash: [5, 4])
                    )
                    .frame(width: 60, height: 60)
                    .scaleEffect(pulse ? 1.08 : 0.96)
                    .opacity(pulse ? 1.0 : 0.7)

                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(badge.rarity.color.opacity(0.85))
            }
            .frame(height: ShowcaseSlotMetrics.medalBox, alignment: .bottom)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }

            Text("MOVING")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.4)
                .foregroundColor(badge.rarity.color.opacity(0.9))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: ShowcaseSlotMetrics.height)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(badge.rarity.color.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
    }
}

/// An open socket. `compact` is the all-empty state (a short row with the
/// explainer under it); otherwise it matches a filled slot's frame.
private struct PinnedBadgeSlotEmpty: View {
    let isInteractive: Bool
    let compact: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .foregroundColor(.white.opacity(0.25))
                        .frame(width: 60, height: 60)

                    Image(systemName: isInteractive ? "plus" : "pin")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white.opacity(0.35))
                }
                .frame(height: compact ? 76 : ShowcaseSlotMetrics.medalBox, alignment: .bottom)

                if !compact {
                    Text("Add a medal")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 84 : ShowcaseSlotMetrics.height)
            .background {
                if !compact {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive)
        .accessibilityLabel(isInteractive ? "Add a medal to your showcase" : "Empty showcase slot")
    }
}

// MARK: - Visual helpers (mirrors PremiumBadgeCard styling so the showcase looks consistent)

func iconName(for badge: Badge) -> String {
    if let holiday = HolidayKey(badgeId: badge.id) {
        return holiday.medalIcon
    }
    if badge.id.starts(with: "streak_") || badge.id.starts(with: "consistency_") {
        return "flame.fill"
    } else if badge.id.starts(with: "miles_") {
        return "figure.run"
    } else if badge.id.starts(with: "pace_") {
        return "bolt.fill"
    } else if badge.id.starts(with: "daily_") {
        return "figure.run.circle.fill"
    } else if badge.id.starts(with: "challenge_") {
        return "trophy.fill"
    } else if badge.id.starts(with: "story_") {
        return "camera.fill"
    } else if badge.id.starts(with: "hype_") {
        return "hands.clap.fill"
    } else if badge.id.starts(with: "nudge_") {
        return "hand.wave.fill"
    } else if badge.id.starts(with: "comp_won_") {
        return "crown.fill"
    } else if badge.id.starts(with: "comp_started_") {
        return "flag.checkered"
    } else if badge.id.starts(with: "comp_entered_") || badge.id.starts(with: "comp_") {
        return "trophy.fill"
    } else if badge.id.starts(with: "hidden_") || badge.id.starts(with: "secret_") || badge.id.starts(with: "special_") {
        return "sparkles"
    }
    return "star.fill"
}

func medalGradientColors(for badge: Badge) -> [Color] {
    switch badge.rarity {
    case .legendary:
        return [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 0.85, green: 0.45, blue: 0.0)]
    case .rare:
        return [Color(red: 0.7, green: 0.4, blue: 1.0), Color(red: 0.5, green: 0.15, blue: 0.85)]
    case .common:
        return [Color(red: 0.4, green: 0.7, blue: 1.0), Color(red: 0.15, green: 0.45, blue: 0.85)]
    }
}

// MARK: - Reorderable slot modifier
// Wraps a pinned-slot view with `.draggable` + `.dropDestination`. The dragged
// payload is the source slot index encoded as a String; the drop handler decodes
// it and invokes `onReorder(from:to:)`. Conditional on `isEnabled` so friend
// profiles (read-only) get no drag affordance.

private struct ReorderableSlotModifier: ViewModifier {
    let slot: Int
    let isEnabled: Bool
    /// The badge that lives in this slot — used to render an unambiguous drag
    /// preview (the actual medal) regardless of the source slot's current
    /// rendering. Without this we'd accidentally snapshot the skeleton view.
    let badge: Badge
    @Binding var draggingSlot: Int?
    @Binding var hoveredSlot: Int?
    let onReorder: ((Int, Int) -> Void)?

    func body(content: Content) -> some View {
        if isEnabled {
            // Drag side: `.draggable` with the @autoclosure form so the
            // payload-producing call fires at drag start (sets `draggingSlot`).
            // The preview renders the medal explicitly — *not* `content`, because
            // by the time iOS snapshots the preview, the source slot has already
            // flipped to its `PinnedBadgeSlotSkeleton` (`isDragging` is true).
            //
            // Drop side: `.onDrop(of:delegate:)` instead of `.dropDestination`.
            // The custom `DropDelegate` returns `DropProposal(operation: .move)`
            // which tells the system to render a "move" cursor instead of the
            // green-plus "copy" badge.
            content
                .draggable(beginDrag()) {
                    PinnedBadgeSlotFilled(badge: badge)
                        .frame(width: ShowcaseSlotMetrics.maxWidth)
                        .scaleEffect(1.05)
                        .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 6)
                }
                .onDrop(
                    of: [.text],
                    delegate: ReorderDropDelegate(
                        slot: slot,
                        onReorder: onReorder,
                        draggingSlot: $draggingSlot,
                        hoveredSlot: $hoveredSlot
                    )
                )
                // Safety: if the user picks up a badge and drops outside any
                // valid destination, the drop handler never fires. Reset the
                // source-skeleton state after a short idle window.
                .onChange(of: draggingSlot) { _, newValue in
                    guard newValue == slot else { return }
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(8))
                        if draggingSlot == slot && hoveredSlot == nil {
                            draggingSlot = nil
                        }
                    }
                }
        } else {
            content
        }
    }

    /// Side-effect payload: marks this slot as the active drag source the
    /// moment iOS asks for the drag payload, so the row immediately replaces
    /// this slot's view with the `PinnedBadgeSlotSkeleton`.
    private func beginDrag() -> String {
        Task { @MainActor in
            draggingSlot = slot
        }
        return String(slot)
    }
}

/// Drop delegate for the reorder slots. Exists primarily so we can override
/// `dropUpdated` to return `DropProposal(operation: .move)` — without it the
/// system shows the green "+" copy badge over the drag preview.
private struct ReorderDropDelegate: DropDelegate {
    let slot: Int
    let onReorder: ((Int, Int) -> Void)?
    @Binding var draggingSlot: Int?
    @Binding var hoveredSlot: Int?

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }

    /// Tell the system this is a move (no green "+"). Returning .move here
    /// causes UIKit to render the standard reorder-style cursor instead.
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        hoveredSlot = slot
    }

    func dropExited(info: DropInfo) {
        if hoveredSlot == slot {
            hoveredSlot = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.text])
        guard let provider = providers.first else {
            Task { @MainActor in
                draggingSlot = nil
                hoveredSlot = nil
            }
            return false
        }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            Task { @MainActor in
                if let str = (object as? NSString) as String?,
                   let from = Int(str),
                   from != slot {
                    onReorder?(from, slot)
                }
                draggingSlot = nil
                hoveredSlot = nil
            }
        }
        return true
    }
}
