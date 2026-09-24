import SwiftUI
import AppKit

let OUT = "/private/tmp/claude-501/-Users-robwiscount-Desktop-Mile-A-Day/16ae6841-b7a7-4720-b555-143103fe9c9a/scratchpad/wardrobe/"

func daysLabel(_ d: Int) -> String { d == 1 ? "1 day" : "\(d.formatted()) days" }

// MARK: 01 colours

struct ColoursSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SheetHeader(eyebrow: "Streak days  →  what his flame is made of",
                        title: "Flame Colours",
                        subtitle: "Your longest streak recolours Flamey himself. Solids early, gradients mid-ladder, glowing effects at legendary. The face always sits on a light core so it reads on every colour.")
            SectionLabel(text: "Solids", detail: "3 – 90 days")
            grid(FlameSkin.solids, cols: 6) { s in
                FlameyCell(flamey: Flamey(skin: s, size: 112), title: s.name, sub: daysLabel(s.days), width: 172, height: 200, glow: s.glow)
            }
            SectionLabel(text: "Gradients", detail: "100 – 300 days")
            grid(FlameSkin.gradients, cols: 7) { s in
                FlameyCell(flamey: Flamey(skin: s, size: 104), title: s.name, sub: daysLabel(s.days), width: 145, height: 194, glow: s.glow)
            }
            SectionLabel(text: "Legendary", detail: "365 – 1,000 days · glow + motion")
            grid(FlameSkin.legendaries, cols: 4) { s in
                FlameyCell(flamey: Flamey(skin: s, size: 150), title: s.name, sub: daysLabel(s.days), width: 257, height: 260, glow: s.glow)
            }
            HStack(spacing: 14) {
                FlameyCell(flamey: Flamey(skin: nil, size: 112), title: "Classic", sub: "Starter · always yours", width: 172, height: 200)
                Text("Starter look for everyone. Earned colours never go away — a broken streak can't take one back (they key on the LONGEST streak).")
                    .font(.system(size: 14, weight: .medium, design: .rounded)).foregroundColor(.white.opacity(0.55))
                    .frame(width: 520, alignment: .leading)
            }
        }
        .padding(36)
        .frame(width: 1140)
        .background(SheetBackground())
    }
}

// MARK: 02 shoes

let shoes: [MockItem] = [.canvasSneakers, .trainers, .racingFlats, .neonSoles, .trackSpikes, .rocketBoots, .lightningKicks, .wingedSandals]

struct FeetCrop: View {
    let item: MockItem
    var skin: FlameSkin? = nil
    var body: some View {
        // A big Flamey, cropped to his feet.
        let size: CGFloat = 330
        Flamey(skin: skin, items: [item], size: size)
            .offset(y: -size * 0.36)
            .frame(width: 250, height: 150)
            .clipped()
    }
}

struct ShoesSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SheetHeader(eyebrow: "Pace medals  →  shoes",
                        title: "Shoes",
                        subtitle: "Faster mile, cooler kicks. The last two lift him off the ground — Rocket Boots on jets, Winged Sandals hovering.")
            SectionLabel(text: "Full body", detail: "top of the ladder")
            HStack(spacing: 14) {
                ForEach([MockItem.rocketBoots, .lightningKicks, .wingedSandals], id: \.self) { s in
                    FlameyCell(flamey: Flamey(items: [s], size: 170), title: s.name, sub: s.medal, width: 348, height: 280, flameyY: -8)
                }
            }
            SectionLabel(text: "The ladder", detail: "feet close-ups")
            grid(shoes, cols: 4) { s in
                Card(width: 257, height: 200) {
                    VStack(spacing: 4) {
                        FeetCrop(item: s)
                        Caption(title: s.name, sub: s.medal)
                    }
                }
            }
        }
        .padding(36)
        .frame(width: 1140)
        .background(SheetBackground())
    }
}

// MARK: 03 hats

let hats: [MockItem] = [.ballCap, .visor, .beanie, .bucketHat, .safariHat, .cowboyHat, .aviatorCap, .headlampHelmet, .crown, .laurel, .vikingHelmet, .astronautHelmet]

struct HatsSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SheetHeader(eyebrow: "Lifetime miles  →  hats",
                        title: "The Explorer's Hats",
                        subtitle: "Every lifetime-mile medal is a hat. 25 miles gets a ball cap; 2,500 puts him in space.")
            grid(hats, cols: 6) { h in
                FlameyCell(flamey: Flamey(items: [h], size: 118), title: h.name, sub: h.medal, width: 172, height: 222, flameyY: 10)
            }
        }
        .padding(36)
        .frame(width: 1140)
        .background(SheetBackground())
    }
}

// MARK: 04 trails

let trails: [MockItem] = [.emberSparks, .dustPuffs, .speedLines, .cometTail, .smokeRings, .starTrail, .rainbowStreak, .lightningTrail, .fireworks, .phoenixFeathers, .auroraRibbon, .meteorShower]

struct TrailsSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SheetHeader(eyebrow: "Distance in one day  →  trails",
                        title: "Trails",
                        subtitle: "What he leaves behind when he hops. Shown frozen mid-hop; in the app it streams out and fades on every hop and on the Walk screen.")
            grid(trails, cols: 4) { t in
                Card(width: 257, height: 210) {
                    VStack(spacing: 0) {
                        Flamey(items: [t], size: 92, hop: true)
                            .offset(x: 52, y: 8)
                            .frame(width: 257, height: 160)
                        Caption(title: t.name, sub: t.medal)
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

@main struct Main {
    @MainActor static func main() {
        let which = CommandLine.arguments.dropFirst().first ?? "all"
        func want(_ s: String) -> Bool { which == "all" || which == s }
        if want("01") { renderPNG(ColoursSheet(), OUT + "01_colours.png") }
        if want("02") { renderPNG(ShoesSheet(), OUT + "02_shoes.png") }
        if want("03") { renderPNG(HatsSheet(), OUT + "03_hats.png") }
        if want("04") { renderPNG(TrailsSheet(), OUT + "04_trails.png") }
        renderMore(which)
    }
}
