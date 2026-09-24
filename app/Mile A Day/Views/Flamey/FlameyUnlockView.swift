import SwiftUI

/// "New for Flamey": the moment a medal unlocks something he can wear.
///
/// ONE item: he's already WEARING it on the stage (the medal is the cause,
/// the item is the reward), with Wear it / Later. SEVERAL at once (a
/// retroactive sweep, a Recalibrate): ONE card — "Flamey unlocked 7 new
/// items" — showing him in the best of them and a strip of what's new, with
/// Open the Closet / Later; the Closet opens with those items marked New.
///
/// Pure: the live host (`FlameyUnlockCelebrationHost`) supplies the facts and
/// does the saving; this renders from stub data in the harness.
struct FlameyUnlockView: View {
    let items: [FlameyItem]
    let owned: Set<FlameyItem>
    let choice: FlameyLookChoice
    /// The medal behind a single unlock ("Sub-7 Mile"), when known.
    var medalName: String? = nil
    var date: Date = Date()
    /// A still frame (the harness; ImageRenderer drives no lifecycle).
    var still: Bool = false
    var onWear: (FlameyItem) -> Void = { _ in }
    var onOpenCloset: () -> Void = {}
    var onLater: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var spin = false

    private var single: FlameyItem? { items.count == 1 ? items[0] : nil }
    private var animated: Bool { !still && !reduceMotion }

    /// He wears the news: each new item in its slot (the best one when two
    /// share a slot), over what he already wears.
    private var look: FlameyLook {
        var choice = self.choice
        var bestPerSlot: [FlameySlot: FlameyItem] = [:]
        for item in items {
            if let current = bestPerSlot[item.slot], current.tier >= item.tier { continue }
            bestPerSlot[item.slot] = item
        }
        // A costume covers what's under it — show it only when it IS the news.
        if bestPerSlot.count > 1 { bestPerSlot[.costume] = nil }
        for (slot, item) in bestPerSlot { choice[slot] = .item(item) }
        return FlameyLook.resolve(owned: owned.union(items), choice: choice, date: date, detail: .full)
    }

    private var glow: Color {
        FlameyPalette.palette(for: look.color)?.glow ?? Color(red: 1, green: 0.6, blue: 0.25)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            header
                .padding(.horizontal, 28)
            Spacer(minLength: 12)
            stage
            Spacer(minLength: 12)
            titleBlock
                .padding(.horizontal, 28)
            if single == nil {
                newStrip
                    .padding(.top, 16)
            }
            Spacer(minLength: 20)
            buttons
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
        }
        .opacity(appeared || still ? 1 : 0)
        .scaleEffect(appeared || still || reduceMotion ? 1 : 0.94)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Behind, never beside: the rays are wider than the screen and must
        // not size the layout.
        .background(background)
        .madTypeCap(.madCardCap)
        .accessibilityElement(children: .contain)
        .onAppear {
            guard !still else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8)) { appeared = true }
            guard animated else { return }
            // Off the appear commit (see FlameBuddyView), or the loop
            // attaches to the first transaction.
            DispatchQueue.main.async {
                withAnimation(.linear(duration: 40).repeatForever(autoreverses: false)) { spin = true }
            }
        }
    }

    // MARK: Pieces

    private var background: some View {
        Color(red: 0.07, green: 0.03, blue: 0.04).opacity(0.97)
            .overlay {
                FlameyUnlockRays(color: glow)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .opacity(0.55)
                    .frame(width: 900, height: 900)
                    .offset(y: -40)
            }
            .overlay {
                RadialGradient(colors: [glow.opacity(0.28), .clear], center: .center, startRadius: 10, endRadius: 260)
                    .offset(y: -40)
            }
            .clipped()
            .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var header: some View {
        if let medalName {
            VStack(spacing: 4) {
                Text("Medal earned")
                    .madFont(size: 11, weight: .black, design: .rounded, maxScale: 1.4)
                    .tracking(1.6)
                    .textCase(.uppercase)
                    .foregroundColor(.white.opacity(0.55))
                Text(medalName)
                    .madFont(size: 17, weight: .heavy, design: .rounded)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        } else {
            Color.clear.frame(height: 1)
        }
    }

    private var stage: some View {
        let size: CGFloat = 190
        var mood = FlameMood(kind: .ready, streak: 0)
        mood.pokeQuip = single != nil ? "Ooh, new!" : "So much new stuff!"
        return ZStack(alignment: .bottom) {
            Ellipse()
                .fill(RadialGradient(colors: [glow.opacity(0.45), .clear], center: .center, startRadius: 1, endRadius: size * 0.8))
                .frame(width: size * 1.8, height: size * 0.26)
                .offset(y: size * 0.04)
            FlameBuddyView(health: .healthy, size: size, mood: mood, still: still, showsMoodBubble: true, look: look)
                .frame(width: size, height: size)
                .padding(.bottom, size * 0.12)
        }
        .frame(height: size * 1.55, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Flamey, wearing " + look.items.filter { items.contains($0) }.map(\.displayName).joined(separator: ", "))
    }

    private var titleBlock: some View {
        VStack(spacing: 6) {
            Text("New for Flamey")
                .madFont(size: 12, weight: .black, design: .rounded, maxScale: 1.4)
                .tracking(1.8)
                .textCase(.uppercase)
                .foregroundColor(FlameyClosetStyle.ember)
            Text(single?.displayName ?? "Flamey unlocked \(items.count) new items")
                .madFont(size: single != nil ? 34 : 26, weight: .black, design: .rounded)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .madFont(size: 15, weight: .semibold, design: .rounded)
                .foregroundColor(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var subtitle: String {
        if let item = single {
            if let holiday = FlameyClosetCopy.holidayLine(item) { return "\(item.slot.closetLabel) · \(holiday)" }
            return "\(item.slot.closetLabel) · " + Self.flavor(item.slot)
        }
        let slots = Set(items.map(\.slot)).count
        return slots == 1 ? "All ready in his closet" : "Across \(slots) parts of his closet"
    }

    static func flavor(_ slot: FlameySlot) -> String {
        switch slot {
        case .color: return "a whole new flame"
        case .head: return "fresh headwear"
        case .eyes: return "a new look"
        case .chest: return "something sharp"
        case .back: return "for the big entrances"
        case .feet: return "new kicks"
        case .costume: return "a full disguise"
        case .held: return "something to wave"
        case .trail: return "leave a mark behind you"
        case .companion: return "a new walking buddy"
        case .aura: return "a glow-up"
        case .bubble: return "a new way to talk"
        }
    }

    /// Batch: what's new, as small tiles (up to six, then "+N").
    private var newStrip: some View {
        let shown = Array(items.sorted { ($0.slot.sortIndex, -$0.tier) < ($1.slot.sortIndex, -$1.tier) }.prefix(6))
        return HStack(spacing: 8) {
            ForEach(shown, id: \.self) { item in
                FlameyClosetTileArt(kind: .item(item), slot: item.slot, color: look.color, scale: 0.55)
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            }
            if items.count > shown.count {
                Text("+\(items.count - shown.count)")
                    .madFont(size: 13, weight: .heavy, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white.opacity(0.75))
                    .frame(width: 46, height: 46)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.07)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("New: " + items.map(\.displayName).joined(separator: ", "))
    }

    private var buttons: some View {
        VStack(spacing: 6) {
            Button {
                MADHaptics.success()
                if let item = single { onWear(item) } else { onOpenCloset() }
            } label: {
                Text(single != nil ? "Wear it" : "Open the Closet")
                    .madFont(size: 17, weight: .heavy, design: .rounded, maxScale: 1.4)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.86, green: 0.22, blue: 0.36), Color(red: 0.70, green: 0.13, blue: 0.28)],
                                             startPoint: .top, endPoint: .bottom)))
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                MADHaptics.tap()
                onLater()
            } label: {
                Text("Later")
                    .madFont(size: 16, weight: .bold, design: .rounded, maxScale: 1.4)
                    .foregroundColor(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(single != nil ? "Keeps it in Flamey's Closet" : "They'll be marked New in Flamey's Closet")
        }
    }
}

/// Soft light rays behind the stage.
struct FlameyUnlockRays: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = max(size.width, size.height) / 2
            let count = 14
            for i in 0..<count {
                let a0 = Double(i) / Double(count) * 2 * .pi
                let a1 = a0 + .pi / Double(count) * 0.55
                var p = Path()
                p.move(to: c)
                p.addLine(to: CGPoint(x: c.x + CGFloat(cos(a0)) * r, y: c.y + CGFloat(sin(a0)) * r))
                p.addLine(to: CGPoint(x: c.x + CGFloat(cos(a1)) * r, y: c.y + CGFloat(sin(a1)) * r))
                p.closeSubpath()
                ctx.fill(p, with: .radialGradient(Gradient(colors: [color.opacity(0.22), color.opacity(0)]),
                                                  center: c, startRadius: 30, endRadius: r))
            }
        }
        .allowsHitTesting(false)
    }
}
