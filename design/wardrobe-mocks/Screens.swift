import SwiftUI

// MARK: - Phone chrome

struct Phone<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.15, green: 0.08, blue: 0.1), Color(red: 0.12, green: 0.06, blue: 0.08), Color(red: 0.08, green: 0.04, blue: 0.06), Color(red: 0.05, green: 0.02, blue: 0.04)],
                           startPoint: .top, endPoint: .bottom)
            content().frame(width: 393, height: 852, alignment: .top)
            StatusBar()
            Capsule().fill(Color.black).frame(width: 124, height: 36).padding(.top, 11)
        }
        .frame(width: 393, height: 852)
        .clipShape(RoundedRectangle(cornerRadius: 55, style: .continuous))
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 64, style: .continuous).fill(Color(white: 0.08))
            .overlay(RoundedRectangle(cornerRadius: 64, style: .continuous).strokeBorder(Color(white: 0.25), lineWidth: 1.5)))
    }
}

struct StatusBar: View {
    var body: some View {
        HStack {
            Text("9:41").font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "cellularbars"); Image(systemName: "wifi"); Image(systemName: "battery.100")
            }
            .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
        }
        .padding(.horizontal, 32).padding(.top, 18)
    }
}

// MARK: - 08 closet

enum TileState { case equipped, owned, locked(progress: Double, line: String), trying(progress: Double, line: String), none }

struct ClosetTile: View {
    let title: String
    let state: TileState
    let thumb: AnyView

    var isLocked: Bool {
        switch state { case .locked, .trying: return true; default: return false }
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                thumb
                    .frame(width: 107, height: 74)
                    .saturation(lockedDim ? 0 : 1)
                    .opacity(lockedDim ? 0.35 : 1)
                    .clipped()
                badge.padding(6)
            }
            Text(title).font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundColor(.white.opacity(isLocked ? 0.6 : 0.95))
                .lineLimit(1).minimumScaleFactor(0.8)
            footer
        }
        .padding(.vertical, 8)
        .frame(width: 113, height: 150, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(bgOpacity)))
        .overlay(border)
    }

    private var lockedDim: Bool {
        if case .locked = state { return true }
        return false
    }
    private var bgOpacity: Double {
        switch state { case .equipped: return 0.09; case .trying: return 0.08; default: return 0.05 }
    }

    @ViewBuilder private var border: some View {
        switch state {
        case .equipped: RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
        case .trying: RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(ember, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
        default: RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    @ViewBuilder private var badge: some View {
        switch state {
        case .equipped:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(.black, .white)
        case .locked, .trying:
            Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold)).foregroundColor(.white.opacity(0.85))
                .frame(width: 20, height: 20).background(Circle().fill(Color.black.opacity(0.55)))
        default: EmptyView()
        }
    }

    @ViewBuilder private var footer: some View {
        switch state {
        case .locked(let p, let line), .trying(let p, let line):
            VStack(spacing: 4) {
                Text(line).font(.system(size: 9.5, weight: .bold, design: .rounded)).foregroundColor(isTrying ? ember : .white.opacity(0.5))
                    .lineLimit(1).minimumScaleFactor(0.75)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(LinearGradient(colors: [ember, madRed], startPoint: .leading, endPoint: .trailing)).frame(width: 88 * p)
                }
                .frame(width: 88, height: 4)
            }
            .padding(.horizontal, 6)
        case .equipped:
            Text("Wearing").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.7))
        case .owned:
            Text("Owned").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.35))
        case .none:
            Text("Bare feet").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.35))
        }
    }
    private var isTrying: Bool { if case .trying = state { return true }; return false }
}

struct SmallFeet: View {
    let item: MockItem?
    var skin: FlameSkin? = .sapphire
    var body: some View {
        ZStack {
            if item == nil {
                Image(systemName: "nosign").font(.system(size: 26, weight: .semibold)).foregroundColor(.white.opacity(0.3))
            } else {
                Flamey(skin: skin, items: item.map { [$0] } ?? [], size: 145, showsBody: false)
                    .offset(y: -145 * 0.5 + (item!.lifts > 0 ? 24 : 12))
            }
        }
            .frame(width: 107, height: 74)
            .clipped()
    }
}

struct Stage: View {
    let flamey: Flamey
    var height: CGFloat = 300
    var body: some View {
        ZStack {
            RadialGradient(colors: [(flamey.skin?.glow ?? .orange).opacity(0.28), .clear], center: UnitPoint(x: 0.5, y: 0.62), startRadius: 0, endRadius: 210)
            Ellipse().fill(RadialGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.02), .clear], center: .center, startRadius: 0, endRadius: 120))
                .frame(width: 250, height: 46).offset(y: 76)
            Ellipse().strokeBorder(Color.white.opacity(0.08), lineWidth: 1).frame(width: 230, height: 38).offset(y: 76)
            flamey.offset(y: 0)
        }
        .frame(width: 393, height: height)
    }
}

struct TabsBar: View {
    let selected: Int
    let tabs = ["Flame", "Outfit", "Extras", "Style"]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { i in
                Text(tabs[i])
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(i == selected ? .black : .white.opacity(0.65))
                    .frame(maxWidth: .infinity).frame(height: 34)
                    .background(Capsule().fill(i == selected ? Color.white : .clear))
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.white.opacity(0.07)).overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1)))
        .padding(.horizontal, 16)
    }
}

struct SubChips: View {
    let items: [String]
    let selected: Int
    var counts: [String] = []
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<items.count, id: \.self) { i in
                HStack(spacing: 4) {
                    Text(items[i]).font(.system(size: 13, weight: .bold, design: .rounded))
                    if i < counts.count { Text(counts[i]).font(.system(size: 10, weight: .bold, design: .rounded)).opacity(0.55) }
                }
                .foregroundColor(i == selected ? .white : .white.opacity(0.55))
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(Capsule().fill(i == selected ? madRed.opacity(0.9) : Color.white.opacity(0.05)))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }
}

struct NavTitle: View {
    var body: some View {
        HStack {
            Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
            Spacer()
            Text("Flamey's Closet").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundColor(.white)
            Spacer()
            Text("Done").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(ember)
        }
        .padding(.horizontal, 20)
        .padding(.top, 62)
    }
}

struct TryOnBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill").font(.system(size: 13, weight: .bold)).foregroundColor(.black)
                .frame(width: 30, height: 30).background(Circle().fill(ember))
            VStack(alignment: .leading, spacing: 1) {
                Text("Trying on Rocket Boots").font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundColor(.white)
                Text("Unlock: run a sub-7 mile · 24s to go").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.65))
            }
            Spacer(minLength: 0)
            Text("Take off").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundColor(.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.12)))
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.55))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(ember.opacity(0.5), lineWidth: 1)))
        .padding(.horizontal, 16)
    }
}

func tileGrid(_ tiles: [ClosetTile]) -> some View {
    VStack(spacing: 10) {
        ForEach(0..<((tiles.count + 2) / 3), id: \.self) { r in
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { c in
                    let i = r * 3 + c
                    if i < tiles.count { tiles[i] } else { Color.clear.frame(width: 113, height: 150) }
                }
            }
        }
    }
}

struct ClosetOutfitScreen: View {
    var body: some View {
        Phone {
            VStack(spacing: 12) {
                NavTitle()
                ZStack(alignment: .bottom) {
                    Stage(flamey: Flamey(skin: .sapphire, items: [.ballCap, .rocketBoots, .aviators], size: 140), height: 300)
                    TryOnBanner().offset(y: 10)
                }
                TabsBar(selected: 1)
                SubChips(items: ["Head", "Face", "Neck", "Back", "Feet"], selected: 4, counts: ["", "", "", "", "5/8"])
                tileGrid([
                    ClosetTile(title: "Trainers", state: .equipped, thumb: AnyView(SmallFeet(item: .trainers))),
                    ClosetTile(title: "Canvas Sneakers", state: .owned, thumb: AnyView(SmallFeet(item: .canvasSneakers))),
                    ClosetTile(title: "Racing Flats", state: .owned, thumb: AnyView(SmallFeet(item: .racingFlats))),
                    ClosetTile(title: "Neon Glow Soles", state: .owned, thumb: AnyView(SmallFeet(item: .neonSoles))),
                    ClosetTile(title: "Track Spikes", state: .owned, thumb: AnyView(SmallFeet(item: .trackSpikes))),
                    ClosetTile(title: "Rocket Boots", state: .trying(progress: 0.86, line: "Sub-7 mile · 24s to go"), thumb: AnyView(SmallFeet(item: .rocketBoots))),
                    ClosetTile(title: "Lightning Kicks", state: .locked(progress: 0.55, line: "Sub-6 · 1:24 to go"), thumb: AnyView(SmallFeet(item: .lightningKicks))),
                    ClosetTile(title: "Winged Sandals", state: .locked(progress: 0.2, line: "Sub-5 · 2:24 to go"), thumb: AnyView(SmallFeet(item: .wingedSandals))),
                    ClosetTile(title: "None", state: .none, thumb: AnyView(SmallFeet(item: nil))),
                ])
                Spacer()
            }
        }
    }
}

struct SkinThumb: View {
    let skin: FlameSkin?
    var body: some View {
        Flamey(skin: skin, size: 58).offset(y: 4).frame(width: 107, height: 74)
    }
}

struct ClosetFlameScreen: View {
    var body: some View {
        let owned: [FlameSkin?] = [nil, .ember, .tangerine, .ruby, .coral, .sunflower, .mint, .sapphire]
        let locked: [(FlameSkin, Double, String)] = [(.violet, 0.75, "45-day streak · 11 to go")]
        var tiles: [ClosetTile] = owned.map { s in
            ClosetTile(title: s?.name ?? "Classic", state: s?.id == "sapphire" ? .equipped : .owned, thumb: AnyView(SkinThumb(skin: s)))
        }
        tiles += locked.map { ClosetTile(title: $0.0.name, state: .locked(progress: $0.1, line: $0.2), thumb: AnyView(SkinThumb(skin: $0.0))) }
        return Phone {
            VStack(spacing: 12) {
                NavTitle()
                Stage(flamey: Flamey(skin: .sapphire, items: [.ballCap, .trainers, .bandana], size: 150, bubble: "Feeling blue!", bubbleStyle: .comic), height: 290)
                TabsBar(selected: 0)
                HStack {
                    Text("LONGEST STREAK 34 DAYS").font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(1).foregroundColor(ember)
                    Spacer()
                    Text("8 of 24").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.45))
                }
                .padding(.horizontal, 20).padding(.top, 2)
                tileGrid(tiles)
                Spacer()
            }
        }
    }
}

struct ClosetSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SheetHeader(eyebrow: "Screen mock · iPhone 15 Pro · 393 × 852",
                        title: "Flamey's Closet",
                        subtitle: "Big live Flamey on a stage. Four tabs — Flame · Outfit (Head/Face/Neck/Back/Feet) · Extras (Held/Trail/Companion) · Style (bubble). Tapping a locked tile TRIES IT ON: he wears it on stage with the unlock line, and nothing is saved.")
            HStack(alignment: .top, spacing: 36) {
                VStack(spacing: 10) {
                    ClosetOutfitScreen()
                    Text("Outfit ▸ Feet — trying on a locked item").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.6))
                }
                VStack(spacing: 10) {
                    ClosetFlameScreen()
                    Text("Flame tab — colours by longest streak").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .padding(36)
        .frame(width: 1000)
        .background(SheetBackground())
    }
}

// MARK: - 09 unlock

struct MedalBadge: View {
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [hex(0xFFD24A, 0.5), .clear], center: .center, startRadius: 30, endRadius: 90)).frame(width: 180, height: 180)
            Circle().fill(LinearGradient(colors: [hex(0xFFF3B0), hex(0xFFCF40), hex(0xC98A12)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 92, height: 92)
            Circle().strokeBorder(hex(0x8A5A00), lineWidth: 2).frame(width: 92, height: 92)
            Circle().fill(LinearGradient(colors: [madRed, hex(0x8A1030)], startPoint: .top, endPoint: .bottom)).frame(width: 72, height: 72)
            VStack(spacing: -2) {
                Image(systemName: "stopwatch.fill").font(.system(size: 18, weight: .bold))
                Text("SUB 7").font(.system(size: 16, weight: .black, design: .rounded))
            }
            .foregroundColor(.white)
        }
    }
}

struct Confetti: View {
    var body: some View {
        Canvas { ctx, c in
            let cols: [Color] = [hex(0xFF4F7B), hex(0xFFCF40), hex(0x3EE0A0), hex(0x4F8BFF), ember, .white]
            for i in 0..<70 {
                let x = CGFloat((i * 97) % 393)
                let y = CGFloat((i * 53) % 470) + 60
                var g = ctx
                g.translateBy(x: x, y: y); g.rotate(by: .degrees(Double(i * 37)))
                let col = cols[i % cols.count].opacity(0.85 - Double(y) / 900)
                if i % 3 == 0 { g.fill(Path(ellipseIn: CGRect(x: -2.5, y: -2.5, width: 5, height: 5)), with: .color(col)) }
                else { g.fill(Path(CGRect(x: -4, y: -1.8, width: 8, height: 3.6)), with: .color(col)) }
            }
        }
        .frame(width: 393, height: 852)
    }
}

struct UnlockScreen: View {
    var body: some View {
        Phone {
            ZStack {
                // Rays behind him.
                Canvas { ctx, c in
                    ctx.translateBy(x: c.width / 2, y: 520)
                    for i in 0..<16 {
                        var g = ctx; g.rotate(by: .degrees(Double(i) * 22.5))
                        var p = Path(); p.move(to: .zero); p.addLine(to: CGPoint(x: -40, y: -520)); p.addLine(to: CGPoint(x: 40, y: -520)); p.closeSubpath()
                        g.fill(p, with: .linearGradient(Gradient(colors: [ember.opacity(0.18), .clear]), startPoint: .zero, endPoint: CGPoint(x: 0, y: -420)))
                    }
                }
                .frame(width: 393, height: 852)
                Confetti()
                VStack(spacing: 0) {
                    Spacer().frame(height: 80)
                    MedalBadge().frame(height: 150)
                    Text("MEDAL EARNED").font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(1.6).foregroundColor(.white.opacity(0.55))
                    Text("Sub-7 Mile").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundColor(.white).padding(.top, 2)
                    Text("6:52 /mi · this morning").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.5)).padding(.top, 2)
                    ZStack {
                        Ellipse().fill(RadialGradient(colors: [hex(0xFF9A1F, 0.35), .clear], center: .center, startRadius: 0, endRadius: 150)).frame(width: 320, height: 90).offset(y: 118)
                        Flamey(skin: .sapphire, items: [.ballCap, .rocketBoots, .aviators], size: 190)
                    }
                    .frame(height: 300)
                    .padding(.top, 8)
                    Text("NEW FOR FLAMEY").font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(1.6).foregroundColor(ember)
                    Text("Rocket Boots").font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundColor(.white)
                    Text("Shoes · he hovers on jets now").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.55))
                    Spacer()
                    VStack(spacing: 10) {
                        Text("Wear it").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 54)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LinearGradient(colors: [madRed, hex(0xB0203F)], startPoint: .top, endPoint: .bottom)))
                        Text("Later").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.7))
                            .frame(maxWidth: .infinity).frame(height: 44)
                    }
                    .padding(.horizontal, 24).padding(.bottom, 40)
                }
            }
        }
    }
}

struct UnlockSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SheetHeader(eyebrow: "Screen mock · the payoff",
                        title: "Unlock Moment",
                        subtitle: "Fires after the medal celebration, once. The medal is the cause, the item is the reward — so the medal sits on top and the new gear is what he's WEARING. \"Wear it\" equips and closes; \"Later\" leaves it in the closet with a dot.")
            UnlockScreen()
        }
        .padding(36)
        .frame(width: 560)
        .background(SheetBackground())
    }
}

// MARK: - 10 widgets + friend card

let widgetItems: [MockItem] = [.crown, .finisherMedal, .aviators, .rocketBoots]
let champion: (FlameSkin, [MockItem]) = (.gold, [.crown, .championCape, .finisherMedal, .aviators, .rocketBoots, .cometTail, .firefly])

struct WidgetSmall: View {
    var body: some View {
        VStack(spacing: 0) {
            Flamey(skin: champion.0, items: widgetItems, size: 78, showsTrail: false, showsCompanion: false)
                .frame(height: 92)
            Text("412").font(.system(size: 30, weight: .black, design: .rounded)).foregroundColor(.white)
            Text("DAY STREAK").font(.system(size: 9, weight: .black, design: .rounded)).tracking(0.8).foregroundColor(.white.opacity(0.65))
        }
        .frame(width: 170, height: 170)
        .background(widgetBG)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

var widgetBG: some View {
    ZStack {
        LinearGradient(colors: [Color(red: 0.16, green: 0.07, blue: 0.08), Color(red: 0.06, green: 0.02, blue: 0.04)], startPoint: .top, endPoint: .bottom)
        RadialGradient(colors: [hex(0xFFC83A, 0.22), .clear], center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: 110)
    }
}

struct WidgetMedium: View {
    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 0) {
                Flamey(skin: champion.0, items: widgetItems, size: 92, showsTrail: false, showsCompanion: false)
                    .frame(width: 140, height: 104)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("412").font(.system(size: 26, weight: .black, design: .rounded)).foregroundColor(.white)
                    Text("DAYS").font(.system(size: 9, weight: .black, design: .rounded)).foregroundColor(.white.opacity(0.6))
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                stat("figure.walk", "1.24", "MI TODAY")
                stat("shoeprints.fill", "3,812", "STEPS")
                stat("checkmark.seal.fill", "Done", "STREAK SAFE")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(width: 364, height: 170)
        .background(widgetBG)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    func stat(_ icon: String, _ v: String, _ l: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundColor(ember).frame(width: 26, height: 26).background(Circle().fill(Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 0) {
                Text(v).font(.system(size: 17, weight: .black, design: .rounded)).foregroundColor(.white)
                Text(l).font(.system(size: 8.5, weight: .black, design: .rounded)).foregroundColor(.white.opacity(0.55))
            }
        }
    }
}

struct FriendCardMock: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 14) {
            ZStack(alignment: .bottom) {
                Ellipse().fill(RadialGradient(colors: [Color.white.opacity(0.10), .clear], center: .center, startRadius: 0, endRadius: 60)).frame(width: 130, height: 14).offset(y: 3)
                Flamey(skin: champion.0, items: champion.1, size: 118, showsTrail: false, showsCompanion: false, bubble: "412 days!", bubbleStyle: .gold)
                    .offset(x: 34)
                    .frame(width: 118, height: 118)
            }
            .frame(width: 170, height: 118 + 62, alignment: .bottom)
            .padding(.bottom, 10)
            VStack(alignment: .leading, spacing: 7) {
                Text("AARON’S FLAMEY").font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(1.2).foregroundColor(ember)
                Text("Mile done today").font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundColor(.white).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    Text("👑").font(.system(size: 12))
                    Text("Crown").font(.system(size: 12, weight: .bold, design: .rounded))
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .heavy)).foregroundColor(.white.opacity(0.4))
                }
                .foregroundColor(.white.opacity(0.92))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.07)).overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)))
                HStack(spacing: 5) {
                    Image(systemName: "hand.tap.fill").font(.system(size: 10, weight: .bold))
                    Text("Tap him to say hi").font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.45))
            }
            .padding(.bottom, 16)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.top, 6)
        .frame(width: 361)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05))
                RadialGradient(colors: [Color.orange.opacity(0.20), Color(red: 0.8, green: 0.2, blue: 0.1).opacity(0.06), .clear], center: UnitPoint(x: 0.2, y: 0.72), startRadius: 4, endRadius: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            })
    }
}

struct TinySizes: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 26) {
            ForEach([120, 72, 44, 28] as [CGFloat], id: \.self) { s in
                VStack(spacing: 8) {
                    Flamey(skin: champion.0, items: s < 50 ? [.crown, .aviators] : widgetItems, size: s, showsTrail: false, showsCompanion: false)
                        .frame(width: max(s, 44), height: s * 1.2, alignment: .bottom)
                        .padding(.bottom, s * 0.18)
                    Text("\(Int(s))pt").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.5))
                }
            }
        }
    }
}

struct SlotRow: View {
    let slot: String
    let widget: String
    let tiny: String
    var body: some View {
        HStack {
            Text(slot).font(.system(size: 12.5, weight: .bold, design: .rounded)).foregroundColor(.white).frame(width: 110, alignment: .leading)
            Text(widget).frame(width: 118, alignment: .leading)
            Text(tiny).frame(width: 118, alignment: .leading)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundColor(.white.opacity(0.65))
    }
}

struct WidgetSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SheetHeader(eyebrow: "Small-size check",
                        title: "Widget & Friend Card",
                        subtitle: "A maxed 'Champion' look (Gold · Crown · Champion Cape · Finisher Medal · Aviators · Rocket Boots + Comet Tail + Firefly) at the sizes it ships. Widgets keep colour + head + face + neck + feet. The friend card adds the back slot — but cape, trail and companion all live on his LEFT, so the card can only show one of them.")
            HStack(alignment: .top, spacing: 26) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "Home-screen widgets")
                    HStack(spacing: 20) { WidgetSmall(); WidgetMedium() }
                    SectionLabel(text: "Friend's profile card")
                    FriendCardMock()
                    SectionLabel(text: "Scale ladder", detail: "< 50pt keeps hat + eyewear only")
                    TinySizes()
                }
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "What each size keeps")
                    SlotRow(slot: "SLOT", widget: "Widget (≈80–95pt)", tiny: "Tiny (< 50pt)").opacity(0.6)
                    SlotRow(slot: "Flame colour", widget: "✓", tiny: "✓")
                    SlotRow(slot: "Head", widget: "✓", tiny: "✓ (reads best)")
                    SlotRow(slot: "Face", widget: "✓", tiny: "✓")
                    SlotRow(slot: "Neck", widget: "✓", tiny: "✗ mush")
                    SlotRow(slot: "Feet", widget: "✓", tiny: "✗ too small")
                    SlotRow(slot: "Back (capes)", widget: "✗ gets cropped", tiny: "✗")
                    SlotRow(slot: "Held", widget: "✗ widens frame", tiny: "✗")
                    SlotRow(slot: "Trail", widget: "✗ static = noise", tiny: "✗")
                    SlotRow(slot: "Companion", widget: "✗ no room", tiny: "✗")
                    SlotRow(slot: "Bubble", widget: "✗", tiny: "✗")
                    SlotRow(slot: "Halo / glow FX", widget: "✓", tiny: "glow only")
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.045)))
                .frame(width: 400)
            }
        }
        .padding(36)
        .frame(width: 1060)
        .background(SheetBackground())
    }
}

@MainActor func renderScreens(_ which: String) {
    func want(_ s: String) -> Bool { which == "all" || which == s }
    if want("08") { renderPNG(ClosetSheet(), OUT + "08_closet_screen.png") }
    if want("09") { renderPNG(UnlockSheet(), OUT + "09_unlock_moment.png") }
    if want("10") { renderPNG(WidgetSheet(), OUT + "10_widget_and_friend.png") }
}
