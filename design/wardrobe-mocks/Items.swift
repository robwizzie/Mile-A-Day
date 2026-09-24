import SwiftUI

// MOCK — the proposed wardrobe catalog and its drawings.

enum Slot: String { case head = "Head", face = "Face", neck = "Neck", back = "Back", feet = "Feet", held = "Held",
                    trail = "Trail", companion = "Companion", costume = "Costume", effect = "Effect", colour = "Flame" }

enum MockItem: String, CaseIterable {
    // Pace → shoes
    case canvasSneakers, trainers, racingFlats, neonSoles, trackSpikes, rocketBoots, lightningKicks, wingedSandals
    // Lifetime miles → hats
    case ballCap, visor, beanie, bucketHat, safariHat, cowboyHat, aviatorCap, headlampHelmet, crown, laurel, vikingHelmet, astronautHelmet
    // Distance in a day → trails
    case emberSparks, dustPuffs, speedLines, cometTail, smokeRings, starTrail, rainbowStreak, lightningTrail, fireworks, phoenixFeathers, auroraRibbon, meteorShower
    // Daily challenges → eyewear
    case starStickers, roundSpecs, classicShades, aviators, heartGlasses, cyberVisor
    // Weekly challenges → neck
    case bandana, knitScarf, bowTie, finisherMedal, sweatTowel, goldChain
    // Competitions → back / organiser held
    case redCape, blueCape, royalCape, championCape, victoryBanner, goldenWings, whistle, clipboard
    // Buddy walks → companions
    case spark, firefly, flameyJr, sparkTrio, lantern, phoenixChick, cometPup
    // Ghost races
    case friendlyGhost, ghostSheet, spectralGlow, vanishingAct
    // Hypes → held
    case pomPoms, foamFinger, megaphone, confettiCannon
    // Stories → camera gear
    case cameraStrap, beret, spotlight, paparazzi

    var slot: Slot {
        switch self {
        case .canvasSneakers, .trainers, .racingFlats, .neonSoles, .trackSpikes, .rocketBoots, .lightningKicks, .wingedSandals: return .feet
        case .ballCap, .visor, .beanie, .bucketHat, .safariHat, .cowboyHat, .aviatorCap, .headlampHelmet, .crown, .laurel, .vikingHelmet, .astronautHelmet, .beret: return .head
        case .emberSparks, .dustPuffs, .speedLines, .cometTail, .smokeRings, .starTrail, .rainbowStreak, .lightningTrail, .fireworks, .phoenixFeathers, .auroraRibbon, .meteorShower: return .trail
        case .starStickers, .roundSpecs, .classicShades, .aviators, .heartGlasses, .cyberVisor: return .face
        case .bandana, .knitScarf, .bowTie, .finisherMedal, .sweatTowel, .goldChain, .cameraStrap: return .neck
        case .redCape, .blueCape, .royalCape, .championCape, .victoryBanner, .goldenWings: return .back
        case .whistle, .clipboard, .pomPoms, .foamFinger, .megaphone, .confettiCannon: return .held
        case .spark, .firefly, .flameyJr, .sparkTrio, .lantern, .phoenixChick, .cometPup, .friendlyGhost: return .companion
        case .ghostSheet: return .costume
        case .spectralGlow, .vanishingAct, .spotlight, .paparazzi: return .effect
        }
    }

    var name: String {
        switch self {
        case .canvasSneakers: return "Canvas Sneakers"
        case .trainers: return "Trainers"
        case .racingFlats: return "Racing Flats"
        case .neonSoles: return "Neon Glow Soles"
        case .trackSpikes: return "Track Spikes"
        case .rocketBoots: return "Rocket Boots"
        case .lightningKicks: return "Lightning Kicks"
        case .wingedSandals: return "Winged Sandals"
        case .ballCap: return "Ball Cap"
        case .visor: return "Visor"
        case .beanie: return "Beanie"
        case .bucketHat: return "Bucket Hat"
        case .safariHat: return "Safari Hat"
        case .cowboyHat: return "Cowboy Hat"
        case .aviatorCap: return "Aviator Cap"
        case .headlampHelmet: return "Headlamp Helmet"
        case .crown: return "Crown"
        case .laurel: return "Laurel Wreath"
        case .vikingHelmet: return "Viking Helmet"
        case .astronautHelmet: return "Astronaut Helmet"
        case .emberSparks: return "Ember Sparks"
        case .dustPuffs: return "Dust Puffs"
        case .speedLines: return "Speed Lines"
        case .cometTail: return "Comet Tail"
        case .smokeRings: return "Smoke Rings"
        case .starTrail: return "Star Trail"
        case .rainbowStreak: return "Rainbow Streak"
        case .lightningTrail: return "Lightning Trail"
        case .fireworks: return "Fireworks"
        case .phoenixFeathers: return "Phoenix Feathers"
        case .auroraRibbon: return "Aurora Ribbon"
        case .meteorShower: return "Meteor Shower"
        case .starStickers: return "Star Stickers"
        case .roundSpecs: return "Round Specs"
        case .classicShades: return "Classic Shades"
        case .aviators: return "Aviators"
        case .heartGlasses: return "Heart Glasses"
        case .cyberVisor: return "Cyber Visor"
        case .bandana: return "Bandana"
        case .knitScarf: return "Knit Scarf"
        case .bowTie: return "Bow Tie"
        case .finisherMedal: return "Finisher Medal"
        case .sweatTowel: return "Sweat Towel"
        case .goldChain: return "Gold Chain"
        case .redCape: return "Red Cape"
        case .blueCape: return "Blue Cape"
        case .royalCape: return "Royal Cape"
        case .championCape: return "Champion Cape"
        case .victoryBanner: return "Victory Banner"
        case .goldenWings: return "Golden Wings"
        case .whistle: return "Whistle"
        case .clipboard: return "Clipboard"
        case .spark: return "Spark"
        case .firefly: return "Firefly"
        case .flameyJr: return "Flamey Jr."
        case .sparkTrio: return "Spark Trio"
        case .lantern: return "Lantern"
        case .phoenixChick: return "Phoenix Chick"
        case .cometPup: return "Comet Pup"
        case .friendlyGhost: return "Friendly Ghost"
        case .ghostSheet: return "Ghost Sheet"
        case .spectralGlow: return "Spectral Glow"
        case .vanishingAct: return "Vanishing Act"
        case .pomPoms: return "Pom-Poms"
        case .foamFinger: return "Foam Finger"
        case .megaphone: return "Megaphone"
        case .confettiCannon: return "Confetti Cannon"
        case .cameraStrap: return "Camera Strap"
        case .beret: return "Director's Beret"
        case .spotlight: return "Spotlight"
        case .paparazzi: return "Paparazzi Flashes"
        }
    }

    /// The medal that unlocks it, in words.
    var medal: String {
        switch self {
        case .canvasSneakers: return "Sub-12 mile"
        case .trainers: return "Sub-11 mile"
        case .racingFlats: return "Sub-10 mile"
        case .neonSoles: return "Sub-9 mile"
        case .trackSpikes: return "Sub-8 mile"
        case .rocketBoots: return "Sub-7 mile"
        case .lightningKicks: return "Sub-6 mile"
        case .wingedSandals: return "Sub-5 mile"
        case .ballCap: return "25 lifetime mi"
        case .visor: return "50 lifetime mi"
        case .beanie: return "100 lifetime mi"
        case .bucketHat: return "150 lifetime mi"
        case .safariHat: return "200 lifetime mi"
        case .cowboyHat: return "250 lifetime mi"
        case .aviatorCap: return "500 lifetime mi"
        case .headlampHelmet: return "750 lifetime mi"
        case .crown: return "1,000 lifetime mi"
        case .laurel: return "1,500 lifetime mi"
        case .vikingHelmet: return "2,000 lifetime mi"
        case .astronautHelmet: return "2,500 lifetime mi"
        case .emberSparks: return "2 mi in a day"
        case .dustPuffs: return "5K in a day"
        case .speedLines: return "5 mi in a day"
        case .cometTail: return "10K in a day"
        case .smokeRings: return "8 mi in a day"
        case .starTrail: return "10 mi in a day"
        case .rainbowStreak: return "Half marathon"
        case .lightningTrail: return "15 mi in a day"
        case .fireworks: return "20 mi in a day"
        case .phoenixFeathers: return "Marathon"
        case .auroraRibbon: return "50K in a day"
        case .meteorShower: return "Ultra"
        case .starStickers: return "1 daily challenge"
        case .roundSpecs: return "5 daily challenges"
        case .classicShades: return "10 daily challenges"
        case .aviators: return "25 daily challenges"
        case .heartGlasses: return "50 daily challenges"
        case .cyberVisor: return "100 daily challenges"
        case .bandana: return "1 weekly challenge"
        case .knitScarf: return "5 weekly challenges"
        case .bowTie: return "10 weekly challenges"
        case .finisherMedal: return "25 weekly challenges"
        case .sweatTowel: return "4-week weekly streak"
        case .goldChain: return "12-week weekly streak"
        case .redCape: return "Enter a competition"
        case .blueCape: return "Enter 10 competitions"
        case .royalCape: return "Enter 50 competitions"
        case .championCape: return "Win a competition"
        case .victoryBanner: return "Win 5 competitions"
        case .goldenWings: return "Win 25 competitions"
        case .whistle: return "Start a competition"
        case .clipboard: return "Start 10 competitions"
        case .spark: return "1 buddy walk"
        case .firefly: return "10 buddy walks"
        case .flameyJr: return "50 buddy walks"
        case .sparkTrio: return "Walk in a crew of 3"
        case .lantern: return "Walk in a crew of 10"
        case .phoenixChick: return "Win a buddy race"
        case .cometPup: return "Win 10 buddy races"
        case .friendlyGhost: return "Beat a ghost"
        case .ghostSheet: return "Beat 10 ghosts"
        case .spectralGlow: return "Beat a ghost by 15s"
        case .vanishingAct: return "Beat a ghost by 45s"
        case .pomPoms: return "Give a hype"
        case .foamFinger: return "Give 25 hypes"
        case .megaphone: return "Give 100 hypes"
        case .confettiCannon: return "Give 500 hypes"
        case .cameraStrap: return "Post a story"
        case .beret: return "Post 5 stories"
        case .spotlight: return "Post 25 stories"
        case .paparazzi: return "Post 100 stories"
        }
    }

    var lifts: CGFloat {
        switch self {
        case .wingedSandals: return 0.08
        case .rocketBoots: return 0.07
        default: return 0
        }
    }
}

enum BubbleStyle: String, CaseIterable { case classic = "Classic", comic = "Comic", neon = "Neon", pixel = "Pixel", gold = "Gold" }

// MARK: - Composite

/// The whole dressed Flamey in a `size` square (overflowing it, like the
/// figure's glow). Companion stands to his LEFT; held items in his RIGHT hand;
/// a trail streams off to the left behind a mid-hop pose.
struct Flamey: View {
    var skin: FlameSkin? = nil
    var items: [MockItem] = []
    var holiday: [FlameyItem] = []
    var size: CGFloat = 200
    var health: FlameHealth = .blazing
    var hop: Bool = false
    var showsTrail: Bool = true
    var showsCompanion: Bool = true
    var bubble: String? = nil
    var bubbleStyle: BubbleStyle = .classic
    var showsBubble: Bool = true
    var showsBody: Bool = true

    private var k: CGFloat { health.bodyScale }
    private var u: CGFloat { size * k }
    private var lift: CGFloat {
        let base = items.map(\.lifts).max() ?? 0
        return (hop ? 0.20 : 0) * u + base * u
    }
    private var worn: [MockItem] {
        items.filter { item in
            if item.slot == .trail { return showsTrail }
            if item.slot == .companion { return showsCompanion }
            return true
        }
    }
    private var tilt: Double { hop ? 8 : 0 }

    var body: some View {
        let lift = self.lift
        let items = worn
        let skin = self.skin
        ZStack {
            // Ground: the shadow stays on the floor while he's in the air.
            Ellipse()
                .fill(Color.black.opacity(0.30))
                .frame(width: size * 0.74 * (1 - lift / size * 0.9), height: size * 0.13 * (1 - lift / size * 0.9))
                .blur(radius: 3)
                .offset(y: size * 0.5 + size * 0.01)
                .opacity(showsBody ? 1 : 0)

            if items.contains(.spotlight) { SpotlightFX(size: size) }
            if items.contains(.spectralGlow) {
                FlameBuddyOuterShape(wobble: 0)
                    .fill(hex(0x5CFFC8))
                    .frame(width: size * 0.82 * 1.22, height: size * 1.14)
                    .scaleEffect(k, anchor: .bottom)
                    .blur(radius: size * 0.07)
                    .opacity(0.85)
                    .offset(y: -lift - size * 0.02)
            }
            if let skin, skin.fx.contains(.halo) { HaloFX(size: size, color: skin.glow).offset(y: -lift) }

            // Trail + behind-the-body props.
            Canvas { ctx, c in
                ctx.translateBy(x: c.width / 2, y: c.height / 2)
                let a = FlameyArt.anchors(size: size, scale: k)
                for item in items where item.slot == .trail {
                    Art.trail(item, &ctx, a, u, lift: lift, size: size)
                }
                var body = ctx
                body.translateBy(x: 0, y: -lift)
                for item in items where item.slot == .back {
                    Art.back(item, &body, a, u)
                }
            }
            .frame(width: size * 3.2, height: size * 2.6)

            if !holiday.isEmpty {
                FlameyOutfitLayer(look: holidayLook, size: size, scale: k, side: .behind, still: true)
                    .offset(y: -lift)
            }

            figureGroup(lift: lift, items: items, skin: skin)
                .rotationEffect(.degrees(tilt), anchor: .bottom)

            if items.contains(.paparazzi) { PaparazziFX(size: size) }

            if items.contains(.flameyJr) {
                ZStack {
                    Ellipse().fill(Color.black.opacity(0.28)).frame(width: size * 0.36, height: size * 0.07).blur(radius: 2).offset(y: size * 0.25)
                    FlameBuddyFigure(health: .healthy, size: size * 0.5, showsFace: true, skin: skin, showsGround: false)
                }
                .offset(x: -size * 0.74, y: size * 0.25)
            }

            if showsBubble, let bubble {
                SpeechBubble(text: bubble, style: bubbleStyle, size: size)
                    .offset(x: size * 0.12, y: size * 0.5 - u * 0.98 - size * 0.20 - lift)
            }
        }
        .frame(width: size, height: size)
    }

    private var holidayLook: FlameyLook {
        var l = FlameyLook()
        for h in holiday { l.wear(h) }
        return l
    }

    @ViewBuilder
    private func figureGroup(lift: CGFloat, items: [MockItem], skin: FlameSkin?) -> some View {
        let vanishing = items.contains(.vanishingAct)
        ZStack {
            if vanishing {
                FlameBuddyFigure(health: health, size: size, showsFace: false, skin: skin, showsGround: false)
                    .opacity(0.22).offset(x: -size * 0.16)
                FlameBuddyFigure(health: health, size: size, showsFace: false, skin: skin, showsGround: false)
                    .opacity(0.12).offset(x: -size * 0.30)
            }
            ZStack {
                if showsBody { FlameBuddyFigure(health: health, size: size, showsFace: true, skin: skin, showsGround: false) }
                if !holiday.isEmpty {
                    FlameyOutfitLayer(look: holidayLook, size: size, scale: k, side: .front, still: true)
                }
                Canvas { ctx, c in
                    ctx.translateBy(x: c.width / 2, y: c.height / 2)
                    let a = FlameyArt.anchors(size: size, scale: k)
                    let arm = skin?.outer[min(1, (skin?.outer.count ?? 1) - 1)] ?? Color.orange
                    for slot in [Slot.feet, .costume, .neck, .face, .head, .held] {
                        for item in items where item.slot == slot {
                            Art.front(item, &ctx, a, u, size: size, arm: arm)
                        }
                    }
                    for item in items where item.slot == .companion && item != .flameyJr {
                        var cc = ctx
                        let gx = -0.80 * u
                        cc.translateBy(x: gx, y: a.bottom); cc.scaleBy(x: 1.55, y: 1.55); cc.translateBy(x: -gx, y: -a.bottom)
                        Art.companion(item, &cc, a, u, size: size)
                    }
                }
                .frame(width: size * 3.2, height: size * 2.6)
            }
            .mask(vanishing ? AnyView(VanishMask(size: size)) : AnyView(Rectangle().frame(width: size * 3.2, height: size * 2.6)))
            .opacity(vanishing ? 0.9 : 1)
        }
        .offset(y: -lift)
    }
}

/// Horizontal slices knocked out — a flicker frozen mid-glitch.
struct VanishMask: View {
    let size: CGFloat
    var body: some View {
        Canvas { ctx, c in
            ctx.fill(Path(CGRect(origin: .zero, size: c)), with: .color(.white))
            let bands: [(CGFloat, CGFloat, CGFloat)] = [(0.40, 0.012, 0.0), (0.47, 0.02, 0.2), (0.58, 0.008, 0.0), (0.62, 0.016, 0.3), (0.70, 0.01, 0.1), (0.36, 0.008, 0)]
            for (y, h, _) in bands {
                ctx.blendMode = .clear
                ctx.fill(Path(CGRect(x: 0, y: y * c.height, width: c.width, height: h * c.height)), with: .color(.black))
            }
        }
        .frame(width: size * 3.2, height: size * 2.6)
    }
}

struct HaloFX: View {
    let size: CGFloat
    let color: Color
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [color.opacity(0.38), color.opacity(0.0)], center: .center, startRadius: size * 0.25, endRadius: size * 0.66))
                .frame(width: size * 1.5, height: size * 1.5)
            Circle().strokeBorder(
                AngularGradient(colors: [color.opacity(0.7), .white.opacity(0.7), color.opacity(0.15), .white.opacity(0.8), color.opacity(0.7)], center: .center),
                lineWidth: max(1.5, size * 0.009))
                .frame(width: size * 1.12, height: size * 1.12)
                .blur(radius: 0.6)
        }
        .offset(y: -size * 0.02)
    }
}

struct SpotlightFX: View {
    let size: CGFloat
    var body: some View {
        Canvas { ctx, c in
            ctx.translateBy(x: c.width / 2, y: c.height / 2)
            var cone = Path()
            cone.move(to: CGPoint(x: -size * 0.16, y: -size * 1.25))
            cone.addLine(to: CGPoint(x: size * 0.02, y: -size * 1.25))
            cone.addLine(to: CGPoint(x: size * 0.62, y: size * 0.52))
            cone.addLine(to: CGPoint(x: -size * 0.66, y: size * 0.52))
            cone.closeSubpath()
            ctx.fill(cone, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.02), hex(0xFFF3C4, 0.34)]),
                                                 startPoint: CGPoint(x: 0, y: -size * 1.2), endPoint: CGPoint(x: 0, y: size * 0.5)))
            var g = ctx
            g.addFilter(.blur(radius: size * 0.02))
            g.fill(Path(ellipseIn: CGRect(x: -size * 0.66, y: size * 0.44, width: size * 1.28, height: size * 0.16)), with: .color(hex(0xFFF3C4, 0.45)))
        }
        .frame(width: size * 2, height: size * 3)
        .allowsHitTesting(false)
    }
}

struct PaparazziFX: View {
    let size: CGFloat
    var body: some View {
        Canvas { ctx, c in
            ctx.translateBy(x: c.width / 2, y: c.height / 2)
            let flashes: [(CGFloat, CGFloat, CGFloat)] = [(-0.62, -0.18, 1.0), (0.60, -0.42, 0.8), (0.70, 0.18, 0.6), (-0.52, -0.62, 0.55), (0.30, -0.78, 0.45)]
            for (x, y, r) in flashes {
                let cx = x * size, cy = y * size, R = r * size * 0.16
                var g = ctx
                g.addFilter(.blur(radius: R * 0.25))
                g.fill(Path(ellipseIn: CGRect(x: cx - R * 0.7, y: cy - R * 0.7, width: R * 1.4, height: R * 1.4)), with: .color(Color.white.opacity(0.55)))
                ctx.fill(FlameyArt.star(cx, cy, R, inner: 0.14), with: .color(.white))
                var s2 = ctx
                s2.translateBy(x: cx, y: cy)
                s2.rotate(by: .degrees(45))
                s2.fill(FlameyArt.star(0, 0, R * 0.55, inner: 0.16), with: .color(hex(0xFFF6C8)))
            }
        }
        .frame(width: size * 2.4, height: size * 2.4)
        .allowsHitTesting(false)
    }
}

// MARK: - Speech bubbles

struct SpeechBubble: View {
    let text: String
    let style: BubbleStyle
    let size: CGFloat

    var body: some View {
        let fs = max(10, size * 0.11)
        switch style {
        case .classic:
            label(fs, ink: hex(0x3D1A14), font: .system(size: fs, weight: .heavy, design: .rounded))
                .background(BubbleShape(r: size * 0.065, tail: size * 0.05).fill(hex(0xFFF8E8)).shadow(color: .black.opacity(0.3), radius: 3, y: 2))
                .rotationEffect(.degrees(-2))
        case .comic:
            label(fs * 1.05, ink: .black, font: .system(size: fs * 1.05, weight: .black, design: .default).italic())
                .background(
                    ZStack {
                        BubbleShape(r: size * 0.09, tail: size * 0.06).fill(Color.white)
                        HalftoneDots().clipShape(BubbleShape(r: size * 0.09, tail: size * 0.06)).opacity(0.18)
                        BubbleShape(r: size * 0.09, tail: size * 0.06).stroke(Color.black, lineWidth: max(2, size * 0.014))
                    }
                    .shadow(color: hex(0xFFD21F), radius: 0, x: size * 0.018, y: size * 0.018))
                .rotationEffect(.degrees(-4))
        case .neon:
            label(fs, ink: hex(0xB9FFFB), font: .system(size: fs, weight: .bold, design: .rounded))
                .shadow(color: hex(0x3DF5FF), radius: 4)
                .background(
                    ZStack {
                        BubbleShape(r: size * 0.07, tail: size * 0.05).fill(hex(0x140A24, 0.92))
                        BubbleShape(r: size * 0.07, tail: size * 0.05).stroke(hex(0xFF4FD8), lineWidth: max(1.5, size * 0.011))
                            .shadow(color: hex(0xFF4FD8), radius: 5).shadow(color: hex(0xFF4FD8), radius: 2)
                    })
        case .pixel:
            label(fs * 0.92, ink: hex(0x1A1A1A), font: .system(size: fs * 0.92, weight: .heavy, design: .monospaced))
                .textCase(.uppercase)
                .background(
                    ZStack {
                        PixelBubbleShape(step: max(3, size * 0.022)).fill(hex(0xF4F1E6))
                        PixelBubbleShape(step: max(3, size * 0.022)).stroke(hex(0x1A1A1A), lineWidth: max(2, size * 0.016))
                    })
        case .gold:
            label(fs, ink: hex(0x4A2A00), font: .system(size: fs, weight: .heavy, design: .serif))
                .background(
                    ZStack {
                        BubbleShape(r: size * 0.08, tail: size * 0.05)
                            .fill(LinearGradient(colors: [hex(0xFFF3B0), hex(0xFFD24A), hex(0xE0A512)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        BubbleShape(r: size * 0.08, tail: size * 0.05).stroke(hex(0xA86F00), lineWidth: max(1.5, size * 0.01))
                    }
                    .shadow(color: hex(0xFFC83A, 0.7), radius: 6))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "sparkle").font(.system(size: fs * 0.9, weight: .bold)).foregroundColor(.white).offset(x: fs * 0.4, y: -fs * 0.5)
                }
                .rotationEffect(.degrees(-2))
        }
    }

    private func label(_ fs: CGFloat, ink: Color, font: Font) -> some View {
        Text(text)
            .font(font)
            .foregroundColor(ink)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .fixedSize()
            .padding(.horizontal, size * 0.06)
            .padding(.vertical, size * 0.032)
            .padding(.bottom, size * 0.05)
    }
}

struct HalftoneDots: View {
    var body: some View {
        Canvas { ctx, c in
            let step: CGFloat = 5
            var y: CGFloat = 0
            var row = 0
            while y < c.height {
                var x: CGFloat = row % 2 == 0 ? 0 : step / 2
                while x < c.width {
                    let r = 1.3 * (x / c.width)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.black))
                    x += step
                }
                y += step * 0.86; row += 1
            }
        }
    }
}

struct BubbleShape: Shape {
    let r: CGFloat
    let tail: CGFloat
    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tail)
        var p = Path(roundedRect: body, cornerRadius: min(r, body.height / 2), style: .continuous)
        let tx = body.minX + body.width * 0.42
        var t = Path()
        t.move(to: CGPoint(x: tx - tail * 0.8, y: body.maxY - 1))
        t.addLine(to: CGPoint(x: tx + tail * 0.6, y: body.maxY - 1))
        t.addLine(to: CGPoint(x: tx - tail * 0.2, y: rect.maxY))
        t.closeSubpath()
        p.addPath(t)
        return p
    }
}

struct PixelBubbleShape: Shape {
    let step: CGFloat
    func path(in rect: CGRect) -> Path {
        let s = step
        let b = rect.maxY - s * 3
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + s * 2, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - s * 2, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - s * 2, y: rect.minY + s))
        p.addLine(to: CGPoint(x: rect.maxX - s, y: rect.minY + s))
        p.addLine(to: CGPoint(x: rect.maxX - s, y: rect.minY + s * 2))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + s * 2))
        p.addLine(to: CGPoint(x: rect.maxX, y: b - s * 2))
        p.addLine(to: CGPoint(x: rect.maxX - s, y: b - s * 2))
        p.addLine(to: CGPoint(x: rect.maxX - s, y: b - s))
        p.addLine(to: CGPoint(x: rect.maxX - s * 2, y: b - s))
        p.addLine(to: CGPoint(x: rect.maxX - s * 2, y: b))
        let tx = rect.minX + rect.width * 0.42
        p.addLine(to: CGPoint(x: tx + s * 2, y: b))
        p.addLine(to: CGPoint(x: tx + s * 2, y: b + s))
        p.addLine(to: CGPoint(x: tx + s, y: b + s))
        p.addLine(to: CGPoint(x: tx + s, y: b + s * 2))
        p.addLine(to: CGPoint(x: tx, y: b + s * 2))
        p.addLine(to: CGPoint(x: tx, y: b + s * 3))
        p.addLine(to: CGPoint(x: tx - s, y: b + s * 3))
        p.addLine(to: CGPoint(x: tx - s, y: b))
        p.addLine(to: CGPoint(x: rect.minX + s * 2, y: b))
        p.addLine(to: CGPoint(x: rect.minX + s * 2, y: b - s))
        p.addLine(to: CGPoint(x: rect.minX + s, y: b - s))
        p.addLine(to: CGPoint(x: rect.minX + s, y: b - s * 2))
        p.addLine(to: CGPoint(x: rect.minX, y: b - s * 2))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + s * 2))
        p.addLine(to: CGPoint(x: rect.minX + s, y: rect.minY + s * 2))
        p.addLine(to: CGPoint(x: rect.minX + s, y: rect.minY + s))
        p.addLine(to: CGPoint(x: rect.minX + s * 2, y: rect.minY + s))
        p.closeSubpath()
        return p
    }
}
