import SwiftUI

// MARK: 05 face / neck / back

let eyewear: [MockItem] = [.starStickers, .roundSpecs, .classicShades, .aviators, .heartGlasses, .cyberVisor]
let necks: [MockItem] = [.bandana, .knitScarf, .bowTie, .finisherMedal, .sweatTowel, .goldChain]
let backs: [MockItem] = [.redCape, .blueCape, .royalCape, .championCape, .victoryBanner, .goldenWings]

struct FaceNeckBackSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SheetHeader(eyebrow: "Daily · weekly · competitions",
                        title: "Face, Neck & Back",
                        subtitle: "Daily challenges dress his EYES, weekly challenges his NECK, competitions his BACK. Organisers get something to hold instead.")
            SectionLabel(text: "Eyewear", detail: "daily challenges")
            grid(eyewear, cols: 6) { i in
                FlameyCell(flamey: Flamey(items: [i], size: 122), title: i.name, sub: i.medal, width: 172, height: 214, flameyY: 4)
            }
            SectionLabel(text: "Neck", detail: "weekly challenges")
            grid(necks, cols: 6) { i in
                FlameyCell(flamey: Flamey(items: [i], size: 122), title: i.name, sub: i.medal, width: 172, height: 214, flameyY: 4)
            }
            SectionLabel(text: "Back", detail: "competitions entered & won · organisers get a held item")
            grid(backs + [.whistle, .clipboard], cols: 4) { i in
                FlameyCell(flamey: Flamey(items: [i], size: 118), title: i.name, sub: i.medal, width: 257, height: 250,
                           flameyY: 22, flameyX: [.goldenWings, .whistle, .clipboard].contains(i) ? 0 : (i == .victoryBanner ? -30 : 50))
            }
        }
        .padding(36)
        .frame(width: 1140)
        .background(SheetBackground())
    }
}

// MARK: 06 companions / held / bubbles

let companions: [MockItem] = [.spark, .firefly, .flameyJr, .sparkTrio, .lantern, .phoenixChick, .cometPup]
let hypeHeld: [MockItem] = [.pomPoms, .foamFinger, .megaphone, .confettiCannon]
let cameraGear: [MockItem] = [.cameraStrap, .beret, .spotlight, .paparazzi]

struct CompanionsSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SheetHeader(eyebrow: "Buddy walks · hypes · nudges · stories · ghosts",
                        title: "Friends, Props & Voice",
                        subtitle: "Walk with people and he gets company. Cheer people on and he gets something to wave. Nudge people and his speech bubble levels up.")
            SectionLabel(text: "Companions", detail: "buddy walks · stands to his left")
            grid(companions, cols: 4) { i in
                FlameyCell(flamey: Flamey(items: [i], size: 112), title: i.name, sub: i.medal, width: 257, height: 214, flameyY: 4, flameyX: 42)
            }
            SectionLabel(text: "Held", detail: "hypes given")
            grid(hypeHeld, cols: 4) { i in
                FlameyCell(flamey: Flamey(items: [i], size: 122), title: i.name, sub: i.medal, width: 257, height: 222, flameyY: 10)
            }
            SectionLabel(text: "Speech bubble", detail: "nudges sent · how he talks")
            HStack(spacing: 14) {
                ForEach(Array(zip(BubbleStyle.allCases, ["Starter", "1 nudge", "25 nudges", "100 nudges", "500 nudges"])), id: \.0) { style, sub in
                    FlameyCell(flamey: Flamey(size: 100, bubble: "Go walk!", bubbleStyle: style), title: style.rawValue, sub: sub, width: 202, height: 250, flameyY: 34)
                }
            }
            SectionLabel(text: "Ghost races", detail: "the spooky set")
            HStack(spacing: 14) {
                FlameyCell(flamey: Flamey(items: [.friendlyGhost], size: 112), title: "Friendly Ghost", sub: "Beat a ghost · companion", width: 257, height: 214, flameyY: 4, flameyX: 42)
                FlameyCell(flamey: Flamey(items: [.ghostSheet], size: 112), title: "Ghost Sheet", sub: "Beat 10 ghosts · costume", width: 190, height: 214, flameyY: 4)
                FlameyCell(flamey: Flamey(skin: .phantom, size: 112), title: "Phantom", sub: "Beat 50 ghosts · flame colour", width: 190, height: 214, glow: hex(0x9FFFE0), flameyY: 4)
                FlameyCell(flamey: Flamey(items: [.spectralGlow], size: 112), title: "Spectral Glow", sub: "Win by 15s · effect", width: 190, height: 214, glow: hex(0x5CFFC8), flameyY: 4)
                FlameyCell(flamey: Flamey(items: [.vanishingAct], size: 112), title: "Vanishing Act", sub: "Win by 45s · effect", width: 190, height: 214, flameyY: 4)
            }
            SectionLabel(text: "Camera gear", detail: "stories posted")
            grid(cameraGear, cols: 4) { i in
                FlameyCell(flamey: Flamey(items: [i], size: 118), title: i.name, sub: i.medal + " · " + i.slot.rawValue.lowercased(), width: 257, height: 222, flameyY: 10)
            }
        }
        .padding(36)
        .frame(width: 1140)
        .background(SheetBackground())
    }
}

// MARK: 07 hero looks

struct Look: Identifiable {
    let id: String
    let title: String
    let skin: FlameSkin?
    let items: [MockItem]
    var hop: Bool = false
    var note: String
}

let heroLooks: [Look] = [
    Look(id: "a", title: "30-day beginner", skin: .sapphire, items: [.ballCap, .trainers], note: "30-day streak · 25 mi · sub-11"),
    Look(id: "b", title: "Speed demon", skin: .arctic, items: [.lightningKicks, .aviators, .speedLines], hop: true, note: "75 days · sub-6 · 25 dailies · 5 mi day"),
    Look(id: "c", title: "Champion", skin: .gold, items: [.crown, .championCape, .finisherMedal], note: "365 days · 1,000 mi · comp won · 25 weeklies"),
    Look(id: "d", title: "Explorer", skin: .aurora, items: [.astronautHelmet, .cometTail, .firefly], hop: true, note: "120 days · 2,500 mi · 10K day · 10 buddy walks"),
    Look(id: "e", title: "Legend", skin: .eternal, items: [.wingedSandals, .goldenWings, .laurel, .phoenixFeathers], hop: true, note: "1,000 days · sub-5 · 25 comp wins · marathon"),
    Look(id: "f", title: "Spooky", skin: .phantom, items: [.ghostSheet, .friendlyGhost], note: "50 ghosts beaten"),
]

struct Chip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.07)).overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1)))
            .fixedSize()
    }
}

struct HeroLooksSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SheetHeader(eyebrow: "Combos",
                        title: "Dream Looks",
                        subtitle: "Six fully dressed Flameys — how the families stack on one character. Each look is a life story you can read at a glance.")
            grid(heroLooks, cols: 3) { l in
                Card(width: 347, height: 440, glow: l.skin?.glow ?? .orange) {
                    VStack(spacing: 8) {
                        Flamey(skin: l.skin, items: l.items, size: l.items.count > 3 || l.items.contains(.astronautHelmet) ? 150 : 176, hop: l.hop)
                            .offset(x: l.hop ? 34 : (l.items.contains(where: { $0.slot == .companion }) ? 40 : 0))
                            .frame(width: 347, height: 290)
                            .offset(y: 16)
                        Text(l.title).font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundColor(.white)
                        let names = [l.skin?.name ?? "Classic"] + l.items.map(\.name)
                        VStack(spacing: 5) {
                            HStack(spacing: 5) { ForEach(Array(names.prefix(3)), id: \.self) { Chip(text: $0) } }
                            if names.count > 3 { HStack(spacing: 5) { ForEach(Array(names.dropFirst(3)), id: \.self) { Chip(text: $0) } } }
                        }
                        Text(l.note).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.45))
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(36)
        .frame(width: 1140)
        .background(SheetBackground())
    }
}

@MainActor func renderMore(_ which: String) {
    func want(_ s: String) -> Bool { which == "all" || which == s }
    if want("05") { renderPNG(FaceNeckBackSheet(), OUT + "05_face_neck_back.png") }
    if want("06") { renderPNG(CompanionsSheet(), OUT + "06_companions_held_bubbles.png") }
    if want("07") { renderPNG(HeroLooksSheet(), OUT + "07_hero_looks.png") }
    renderScreens(which)
}
