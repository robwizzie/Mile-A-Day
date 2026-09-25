import SwiftUI

// FLAMEY'S CLOSET — the pieces every Closet screen shares: the item's own
// picture, a tile, a medal, the item card and the undo toast. Pure (stub data
// renders them in the macOS harness).

// MARK: - Style

enum FlameyClosetStyle {
    static let ember = Color(red: 1.0, green: 0.72, blue: 0.35)
    static let newDot = Color(red: 1.0, green: 0.36, blue: 0.40)
    static let accent = Color(red: 0.86, green: 0.22, blue: 0.36)
    static let accentDeep = Color(red: 0.70, green: 0.13, blue: 0.28)
    static let worn = Color(red: 0.46, green: 0.93, blue: 0.62)
    static let tileFill = Color.white.opacity(0.06)
    static let tileStroke = Color.white.opacity(0.08)
    static let artFill = Color.white.opacity(0.045)
    static let ground = Color(red: 0.07, green: 0.03, blue: 0.04)

    static var primaryFill: LinearGradient {
        LinearGradient(colors: [accent, accentDeep], startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - The item's own picture

/// The ITEM, big and centred — the hat, the shoes, the companion — drawn by
/// the production outfit layer with no Flamey under it, so a tile is about
/// the thing you'd be choosing rather than a tiny version of him. Colours and
/// auras are about HIM, so those two show a small Flamey instead. A still: a
/// grid of forty never runs forty clocks.
struct FlameyItemArt: View {
    let item: FlameyItem
    /// The colour he burns in (arms on held items, the aura's figure).
    var color: FlameyItem = .classic
    var locked: Bool = false

    /// A day with no holiday, so the picture is the item and nothing else.
    static let neutralDate: Date = {
        var c = DateComponents(); c.year = 2026; c.month = 6; c.day = 10; c.hour = 12
        return Calendar(identifier: .gregorian).date(from: c) ?? Date()
    }()

    var body: some View {
        GeometryReader { geo in
            let box = min(geo.size.width, geo.size.height * 1.25)
            content(box: box)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .saturation(locked ? 0.05 : 1)
        .brightness(locked ? -0.12 : 0)
        .opacity(locked ? 0.55 : 1)
        .accessibilityHidden(true)
    }

    private func look(_ items: [FlameyItem]) -> FlameyLook {
        var choice = FlameyLookChoice.basic
        for item in items { choice[item.slot] = item }
        return FlameyLook.resolve(owned: Set(items), choice: choice, date: Self.neutralDate, detail: .full)
    }

    /// (figure size as a fraction of the box, item centre x/y in body units)
    /// — zoomed onto the part of him the item sits on.
    private var framing: (CGFloat, CGFloat, CGFloat) {
        switch item {
        case .victoryBanner: return (0.8, 0.30, -0.62)
        case .goldenWings, .turkeyFeathers: return (0.62, 0, -0.10)
        case .sweatband: return (1.5, 0, 0.02)
        case .laurelWreath: return (1.2, 0, -0.34)
        case .visor, .directorsBeret, .heartBopper: return (1.45, 0, -0.44)
        default: break
        }
        switch item.slot {
        case .head: return (1.12, 0, -0.52)
        case .eyes: return (1.55, 0, 0.14)
        case .chest: return (1.45, 0, 0.30)
        case .feet: return (1.45, 0, 0.46)
        case .back: return (0.66, -0.22, 0.0)
        case .costume: return (0.66, 0, -0.02)
        case .held: return FlameyArt.heldTileFraming(item)
        case .trail: return (0.60, -0.72, 0.14)
        case .companion:
            return FlameyOutfitLayer.floats(item) ? (0.95, 0.66, -0.02) : (0.95, 0.70, 0.36)
        case .color, .aura, .bubble: return (0.6, 0, 0)
        }
    }

    /// Items that only read ON him (a band round his head, a cape at his
    /// back, a hand at his side) stand on a faint, colourless outline of him —
    /// a mannequin, so the item stays the subject. Trails and companions are
    /// things in their own right and stand alone.
    private var usesMannequin: Bool {
        switch item.slot {
        case .trail, .companion: return false
        default: return true
        }
    }

    @ViewBuilder
    private func content(box: CGFloat) -> some View {
        switch item.slot {
        case .color:
            FlameyDressedFigure(look: look([item]), health: .healthy, size: box * 0.62, scale: 1)
                .frame(width: box * 0.62, height: box * 0.62)
                .offset(y: box * 0.02)
        case .aura:
            FlameyDressedFigure(look: look([color, item]), health: .healthy, size: box * 0.5, scale: 1)
                .frame(width: box * 0.5, height: box * 0.5)
                .offset(y: box * 0.04)
        case .bubble:
            bubble(box: box)
        default:
            let (k, cx, cy) = framing
            let size = box * k
            let one = look([color, item])
            ZStack {
                FlameyOutfitLayer(look: one, size: size, side: .behind, still: true)
                if usesMannequin {
                    FlameyDressedFigure(look: .plain, health: .healthy, size: size, scale: 1)
                        .saturation(0)
                        .opacity(0.16)
                }
                FlameyOutfitLayer(look: one, size: size, side: .front, still: true)
            }
            .frame(width: size, height: size)
            .offset(x: -cx * size, y: -cy * size)
        }
    }

    @ViewBuilder
    private func bubble(box: CGFloat) -> some View {
        if item == .classicBubble {
            Text("Let's go!")
                .font(.system(size: box * 0.15, weight: .bold, design: .rounded))
                .foregroundColor(.black.opacity(0.85))
                .padding(.horizontal, box * 0.12)
                .padding(.vertical, box * 0.07)
                .padding(.bottom, box * 0.07)
                .background(FlameyBubbleShape(cornerRadius: box * 0.12, tailHeight: box * 0.07, tailWidth: box * 0.12).fill(Color.white))
        } else {
            FlameyStyledBubble(text: "Let's go!", style: item, size: 140)
                .scaleEffect(box / 80)
        }
    }
}

// MARK: - A medal

/// A small medal: the badge's icon on its rarity's face — the same colours
/// the Badges screen uses. Greyed (with a lock) when not earned.
struct FlameyMedalDisc: View {
    let medal: FlameyMedalInfo
    var size: CGFloat = 40
    /// A tile already wears its own lock; its corner medal doesn't repeat it.
    var showsLock: Bool = true

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: medal.isEarned ? medal.rarity.colors : [Color(white: 0.34), Color(white: 0.2)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .strokeBorder(Color.white.opacity(medal.isEarned ? 0.55 : 0.18), lineWidth: max(1, size * 0.05))
                .padding(size * 0.06)
            Image(systemName: medal.icon)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundColor(.white.opacity(medal.isEarned ? 0.96 : 0.55))
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            if !medal.isEarned, showsLock {
                Image(systemName: "lock.fill")
                    .font(.system(size: size * 0.2, weight: .black))
                    .foregroundColor(.white)
                    .frame(width: size * 0.38, height: size * 0.38)
                    .background(Circle().fill(Color.black.opacity(0.7)))
                    .offset(x: size * 0.34, y: size * 0.34)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - The stage, shared

/// What every Closet stage agrees on: how much room his speech bubble takes
/// above him, and how he's described.
enum FlameyStage {
    /// Height a speech bubble reaches ABOVE his `size`×`size` frame — every
    /// style, two lines (measured in the harness: ~34pt at 104, ~29pt at 84).
    /// A stage reserves it whether or not he's talking, so a bubble never
    /// clips against what sits above him and choosing a voice moves nothing.
    /// Covers the tallest look too: tall hats and hover are fitted to one
    /// envelope (`FlameyLook.stageFit`), and the bubble now sits OVER the
    /// hat rather than on it (`FlameyLook.stageRoomAbove`).
    static func bubbleRoom(_ size: CGFloat) -> CGFloat { max(16 + size * 0.4, FlameyLook.stageRoomAbove(size) + 4) }

    static func accessibilityLabel(_ look: FlameyLook, name: String = FlameyNameRules.fallback) -> String {
        let worn = look.items.filter { !$0.isMoodProp && $0 != .classic && $0 != .classicBubble }
        guard !worn.isEmpty else { return "\(name), basic — wearing nothing" }
        return "\(name), wearing " + worn.map(\.displayName).joined(separator: ", ")
    }

    /// "From your Quick Runner medal" / "Locked · earn the Quick Runner medal".
    @MainActor
    static func medalLine(_ item: FlameyItem, model: FlameyClosetModel) -> String {
        guard let medal = model.medal(for: item) else { return "Always his — no medal needed" }
        guard let name = medal.name else {
            let how = FlameyClosetCopy.lowercasedFirst(item.unlockCopy)
            return model.owns(item) ? "Unlocked: \(how)" : "Locked · \(how)"
        }
        return model.owns(item) ? "From your \(name) medal" : "Locked · earn the \(name) medal"
    }
}

// MARK: - The medal on a tile

/// The medal behind an item, pinned to the corner of its picture — so the
/// link between a medal and what it unlocks is on every tile, not only in
/// the item's card.
struct FlameyTileMedal: View {
    let medal: FlameyMedalInfo
    var size: CGFloat = 19

    var body: some View {
        FlameyMedalDisc(medal: medal, size: size, showsLock: false)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.55), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
    }
}

// MARK: - A walkthrough tile

/// One choice in a walkthrough row: the item (or None), its medal on the
/// corner, and a clear SELECTED state — white ring, check, "SELECTED".
struct FlameyPickTile: View {
    /// nil = the row's "None".
    let item: FlameyItem?
    let slot: FlameySlot
    let selected: Bool
    let medal: FlameyMedalInfo?
    var color: FlameyItem = .classic
    var isNew: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let item {
                            FlameyItemArt(item: item, color: color)
                        } else {
                            Image(systemName: "circle.slash")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white.opacity(0.4))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(height: 50)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(FlameyClosetStyle.artFill))
                    if let medal {
                        FlameyTileMedal(medal: medal, size: 18)
                            .padding(3)
                    }
                }
                Text(item?.displayName ?? "None")
                    .madFont(size: 11, weight: .heavy, design: .rounded, maxScale: 1.3)
                    .foregroundColor(selected ? .white : .white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 26, alignment: .top)
                Text("SELECTED")
                    .madFont(size: 8, weight: .black, design: .rounded, maxScale: 1.2)
                    .tracking(0.6)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .opacity(selected ? 1 : 0)
                    .frame(height: 9)
            }
            .padding(5)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(selected ? Color.white.opacity(0.15) : FlameyClosetStyle.tileFill))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(selected ? Color.white : FlameyClosetStyle.tileStroke, lineWidth: selected ? 2 : 1))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(.black)
                        .frame(width: 19, height: 19)
                        .background(Circle().fill(Color.white))
                        .offset(x: 4, y: -4)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .topLeading) {
                if isNew && !selected {
                    Text("NEW")
                        .madFont(size: 8, weight: .black, design: .rounded, maxScale: 1.2)
                        .tracking(0.5)
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(FlameyClosetStyle.newDot))
                        .offset(x: -3, y: -4)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(FlameyTilePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(selected ? (item == nil || item == slot.basicItem ? "" : "Double-tap to take it off")
                                    : "Double-tap to put it on him")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    private var accessibilityLabel: String {
        guard let item else { return "No \(slot.pickLabel.lowercased())" }
        var parts = [item.displayName]
        if let name = medal?.name { parts.append("from the \(name) medal") }
        if isNew { parts.append("new") }
        return parts.joined(separator: ", ")
    }
}


// MARK: - A tile

/// One item in the Closet grid. Owned: the item in colour, tap to wear (tap
/// the worn one to take it off). Locked: greyed with a lock and, where the
/// app knows it, how close you are — tap to see how to earn it. Worn: a green
/// ring and a check. Long-press (or the VoiceOver action) opens the card.
struct FlameyClosetTile: View {
    let item: FlameyItem
    let model: FlameyClosetModel
    var action: () -> Void
    var onDetails: () -> Void

    private var owned: Bool { model.owns(item) }
    private var worn: Bool { model.isWorn(item) }
    private var isNew: Bool { model.newItems.contains(item) }
    private var progress: FlameyUnlockProgress? { model.progress(for: item) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack(alignment: .bottomTrailing) {
                    FlameyItemArt(item: item, color: model.stageLook.color, locked: !owned)
                        .frame(height: 56)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(FlameyClosetStyle.artFill))
                    // The medal that unlocks it, on every tile — owned or not.
                    if let medal = model.medal(for: item) {
                        FlameyTileMedal(medal: medal, size: 18)
                            .padding(3)
                    }
                }

                Text(item.displayName)
                    .madFont(size: 11.5, weight: .heavy, design: .rounded, maxScale: 1.35)
                    .foregroundColor(owned ? .white : .white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .top)

                footer
                    .frame(height: 10)
            }
            .padding(.horizontal, 5)
            .padding(.top, 5)
            .padding(.bottom, 5)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(worn ? Color.white.opacity(0.10) : FlameyClosetStyle.tileFill))
            .overlay(border)
            .overlay(alignment: .topTrailing) { badge.offset(x: 4, y: -4) }
            .overlay(alignment: .topLeading) {
                if isNew {
                    Text("NEW")
                        .madFont(size: 8, weight: .black, design: .rounded, maxScale: 1.2)
                        .tracking(0.5)
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(FlameyClosetStyle.newDot))
                        .offset(x: -3, y: -4)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(FlameyTilePressStyle())
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in onDetails() })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(owned ? (worn ? (item.slot.basicItem == item ? "" : "Double-tap to take it off") : "Double-tap to try it on")
                                 : "Double-tap to see how to earn it")
        .accessibilityAddTraits(worn ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction(named: "Details") { onDetails() }
    }

    /// On him in the draft but not saved yet.
    private var tryingOn: Bool { worn && model.isChanged(item.slot) }

    @ViewBuilder
    private var footer: some View {
        if worn {
            Text(tryingOn ? "TRYING ON" : "WEARING")
                .madFont(size: 8.5, weight: .black, design: .rounded, maxScale: 1.2)
                .tracking(0.6)
                .foregroundColor(tryingOn ? FlameyClosetStyle.ember : FlameyClosetStyle.worn)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } else if let progress {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(LinearGradient(colors: [FlameyClosetStyle.ember, FlameyClosetStyle.accent],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, geo.size.width * progress.fraction))
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, 8)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var border: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if worn {
            shape.strokeBorder(FlameyClosetStyle.worn, lineWidth: 2)
        } else {
            shape.strokeBorder(FlameyClosetStyle.tileStroke, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var badge: some View {
        if worn {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .black))
                .foregroundColor(.black)
                .frame(width: 19, height: 19)
                .background(Circle().fill(FlameyClosetStyle.worn))
                .accessibilityHidden(true)
        } else if !owned {
            Image(systemName: "lock.fill")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 19, height: 19)
                .background(Circle().fill(Color(white: 0.16)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .accessibilityHidden(true)
        }
    }

    private var accessibilityLabel: String {
        var parts = [item.displayName, item.slot.shortLabel]
        if let name = model.medal(for: item)?.name { parts.append("from the \(name) medal") }
        if !owned {
            parts.append("locked")
            parts.append(FlameyClosetCopy.lowercasedFirst(item.unlockCopy))
            if let progress { parts.append(progress.spoken) }
        } else if worn {
            parts.append(tryingOn ? "trying on, not saved" : "wearing")
        } else {
            parts.append("unlocked")
        }
        if isNew { parts.append("new") }
        return parts.joined(separator: ", ")
    }
}

/// A gentle press: tiles dip a touch, never flash.
struct FlameyTilePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - The item card

/// Everything about one item: him wearing it (a preview — nothing is saved
/// until "Wear it"), what it is, the MEDAL it comes from, and either when you
/// earned it or exactly how and where to earn it.
struct FlameyItemDetailView: View {
    let item: FlameyItem
    let model: FlameyClosetModel
    var still: Bool = false
    var onClose: () -> Void = {}

    /// "View workout": the medal's workout, on a sheet over this card.
    @State private var workout: FlameyWorkoutRef?

    private var owned: Bool { model.owns(item) }
    private var worn: Bool { model.isWorn(item) }
    private var medal: FlameyMedalInfo? { model.medal(for: item) }
    private var route: FlameyEarnRoute? { FlameyEarnRoute.route(for: item) }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 18)
            medalCard
                .padding(.horizontal, 16)
                .padding(.top, 16)
            if let holiday = FlameyClosetCopy.holidayLine(item), owned {
                note(icon: "calendar", text: holiday)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
            }
            Spacer(minLength: 16)
            actions
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(FlameyClosetStyle.ground.ignoresSafeArea())
        .madTypeCap(.madCardCap)
        .sheet(item: $workout) { ref in
            if let view = model.workoutView?(ref.id) { view }
        }
    }

    // MARK: Header — him wearing it + what it is

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            preview
            VStack(alignment: .leading, spacing: 6) {
                Text(item.slot.closetLabel.uppercased())
                    .madFont(size: 11, weight: .black, design: .rounded, maxScale: 1.3)
                    .tracking(1.2)
                    .foregroundColor(FlameyClosetStyle.ember)
                Text(item.displayName)
                    .madFont(size: 24, weight: .black, design: .rounded)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .accessibilityAddTraits(.isHeader)
                statusChip
            }
            Spacer(minLength: 0)
        }
    }

    private var preview: some View {
        let size: CGFloat = 104
        let look = model.preview(with: item)
        let glow = FlameyPalette.palette(for: look.color)?.glow ?? Color(red: 1, green: 0.55, blue: 0.2)
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(RadialGradient(colors: [glow.opacity(0.26), Color.white.opacity(0.03)],
                                     center: UnitPoint(x: 0.5, y: 0.62), startRadius: 2, endRadius: 90))
            Ellipse()
                .fill(Color.white.opacity(0.07))
                .frame(width: size * 0.9, height: 12)
                .padding(.bottom, 12)
            FlameBuddyView(health: .healthy, size: size * 0.66, still: still, look: look, wardrobeReach: 0.8)
                .frame(width: size * 0.66, height: size * 0.66)
                .padding(.bottom, 17)
            if !owned {
                Text("PREVIEW")
                    .madFont(size: 8, weight: .black, design: .rounded, maxScale: 1.2)
                    .tracking(0.8)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: size + 20, height: size + 26)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(owned ? "\(model.displayName) wearing \(item.displayName)" : "Preview of \(model.displayName) wearing \(item.displayName)")
    }

    private var statusChip: some View {
        let (text, icon, tint): (String, String, Color) = {
            if worn { return ("Wearing now", "checkmark.circle.fill", FlameyClosetStyle.worn) }
            if owned { return ("Unlocked", "lock.open.fill", .white.opacity(0.8)) }
            return ("Locked", "lock.fill", FlameyClosetStyle.ember)
        }()
        return HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold)).accessibilityHidden(true)
            Text(text).madFont(size: 12, weight: .heavy, design: .rounded, maxScale: 1.3).lineLimit(1)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.14)))
    }

    // MARK: The medal

    @ViewBuilder
    private var medalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let medal {
                HStack(spacing: 12) {
                    FlameyMedalDisc(medal: medal, size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(owned ? "FROM YOUR MEDAL" : "UNLOCKED BY THE MEDAL")
                            .madFont(size: 10, weight: .black, design: .rounded, maxScale: 1.3)
                            .tracking(1)
                            .foregroundColor(.white.opacity(0.45))
                        Text(medal.name ?? item.unlockCopy)
                            .madFont(size: 17, weight: .heavy, design: .rounded)
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        Text("\(medal.rarity.label) medal")
                            .madFont(size: 12, weight: .bold, design: .rounded)
                            .foregroundColor(medal.rarity.ink)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                if owned {
                    ownedLine(medal)
                } else {
                    lockedLines
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(FlameyClosetStyle.ember)
                        .accessibilityHidden(true)
                    Text("Always his — no medal needed.")
                        .madFont(size: 15, weight: .semibold, design: .rounded)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    /// HOW the medal was earned — the server's sentence ("You ran a 7:42
    /// mile") with its day and, when a workout did it, a way to that workout;
    /// else the medal's requirement and the day it was earned.
    private func ownedLine(_ medal: FlameyMedalInfo) -> some View {
        FlameyHowEarned(medal: medal, requirement: item.unlockCopy,
                        onViewWorkout: model.workoutView == nil ? nil : { id in
                            MADHaptics.tap()
                            workout = FlameyWorkoutRef(id: id)
                        })
    }

    @ViewBuilder
    private var lockedLines: some View {
        VStack(alignment: .leading, spacing: 10) {
            note(icon: "target", text: "How: " + FlameyClosetCopy.lowercasedFirst(item.unlockCopy), tint: .white)
            if let progress = model.progress(for: item) {
                VStack(alignment: .leading, spacing: 5) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.10))
                            Capsule()
                                .fill(LinearGradient(colors: [FlameyClosetStyle.ember, FlameyClosetStyle.accent],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(6, geo.size.width * progress.fraction))
                        }
                    }
                    .frame(height: 7)
                    Text(progress.short)
                        .madFont(size: 12, weight: .bold, design: .rounded, monospacedDigit: true)
                        .foregroundColor(.white.opacity(0.7))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(progress.spoken)
            }
            if let route {
                if case .holiday = route, let (key, day) = model.nextHoliday(for: item) {
                    note(icon: "calendar", text: "Next chance: \(FlameyClosetCopy.shortDay(day)). He wears it on \(key.holidayName) either way.",
                         tint: .white.opacity(0.75))
                } else {
                    note(icon: "mappin.and.ellipse", text: route.whereLine, tint: .white.opacity(0.75))
                }
            }
        }
    }

    private func note(icon: String, text: String, tint: Color = .white.opacity(0.7)) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(text)
                .madFont(size: 14, weight: .semibold, design: .rounded)
                .foregroundColor(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 6) {
            if owned {
                if worn, item.slot.basicItem != item {
                    primary("Take it off", icon: "minus.circle.fill", filled: false) {
                        MADHaptics.tap()
                        model.takeOff(item.slot)
                        onClose()
                    }
                } else if !worn {
                    primary("Try it on", icon: "checkmark", filled: true) {
                        MADHaptics.success()
                        model.wear(item)
                        onClose()
                    }
                }
            } else if model.onEarn != nil, let title = route?.buttonTitle, let route {
                primary(title, icon: route.icon, filled: true) {
                    MADHaptics.action()
                    model.earn(item)
                }
                .accessibilityHint("Closes the Closet and takes you there")
            }
            Button {
                MADHaptics.tap()
                onClose()
            } label: {
                Text(owned ? "Close" : "Not now")
                    .madFont(size: 16, weight: .bold, design: .rounded, maxScale: 1.4)
                    .foregroundColor(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func primary(_ title: String, icon: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .madFont(size: 15, weight: .bold, maxScale: 1.3)
                    .accessibilityHidden(true)
                Text(title)
                    .madFont(size: 17, weight: .heavy, design: .rounded, maxScale: 1.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background {
                let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                if filled {
                    shape.fill(FlameyClosetStyle.primaryFill)
                } else {
                    shape.fill(Color.white.opacity(0.10)).overlay(shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Undo toast

/// "Wearing Rocket Boots · Undo" — every change in the Closet can be taken
/// back in one tap.
struct FlameyUndoToast: View {
    let toast: FlameyClosetToast
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(FlameyClosetStyle.worn)
                .accessibilityHidden(true)
            Text(toast.text)
                .madFont(size: 14, weight: .bold, design: .rounded, maxScale: 1.4)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            if toast.undo != nil {
                Button(action: onUndo) {
                    Text("Undo")
                        .madFont(size: 14, weight: .heavy, design: .rounded, maxScale: 1.4)
                        .foregroundColor(FlameyClosetStyle.ember)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(minWidth: 44, minHeight: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(minHeight: 48)
        .background(Capsule().fill(Color(white: 0.13)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
    }
}
