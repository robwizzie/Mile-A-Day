//
//  MedalView.swift
//  Mile A Day
//
//  One premium, metallic, embossed medal used EVERYWHERE a medal is shown so the
//  look is consistent across the grid, detail screen, unlock celebration, profile
//  showcase, and challenge gallery.
//
//  - `MedalView` is the pure disc. It takes `roll`/`pitch` (-1...1) so a parent can
//    drive a 3D tilt + moving specular highlight, plus an internal shimmer sweep.
//    It does NOT observe motion itself, so dozens can render in a grid cheaply.
//  - `TiltableMedal` wraps `MedalView` and feeds it live device tilt from the
//    shared `MedalMotion` — use it for the single hero medal on detail / unlock.
//

import SwiftUI
import CoreMotion

// MARK: - Shared device-motion source

/// One `CMMotionManager` for the whole app, ref-counted so the sensor only runs
/// while a tiltable medal is on screen. Publishes normalized roll/pitch in -1...1,
/// relative to however the phone is held when the first medal appears (so the
/// medal reads "flat" at rest and reacts to tilt from there).
final class MedalMotion: ObservableObject {
    static let shared = MedalMotion()

    @Published var roll: Double = 0
    @Published var pitch: Double = 0

    private let manager = CMMotionManager()
    private var refCount = 0
    private var refRoll: Double?
    private var refPitch: Double?

    private init() {}

    func start() {
        refCount += 1
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let m = motion else { return }
            if self.refRoll == nil { self.refRoll = m.attitude.roll }
            if self.refPitch == nil { self.refPitch = m.attitude.pitch }
            let span = 0.6 // radians of tilt that maps to the full -1...1 range
            let r = (m.attitude.roll - (self.refRoll ?? 0)) / span
            let p = (m.attitude.pitch - (self.refPitch ?? 0)) / span
            self.roll = min(1, max(-1, r))
            self.pitch = min(1, max(-1, p))
        }
    }

    func stop() {
        refCount = max(0, refCount - 1)
        if refCount == 0 {
            manager.stopDeviceMotionUpdates()
            refRoll = nil
            refPitch = nil
            roll = 0
            pitch = 0
        }
    }
}

// MARK: - Metallic palette

/// One palette per rarity: the metal (rim + face), the stamped icon, the glow,
/// and the neck ribbon's colours. Ribbons are deeper than the metal on purpose
/// so the disc stays the brightest thing on screen.
struct MedalPalette {
    let rimHi: Color, rimLo: Color
    let faceHi: Color, faceLo: Color
    let ink: Color, inkShadow: Color
    let glow: Color
    let ribbonA: Color, ribbonB: Color, ribbonStripe: Color

    static func forRarity(_ rarity: BadgeRarity, locked: Bool) -> MedalPalette {
        if locked {
            return MedalPalette(
                rimHi: Color(white: 0.42), rimLo: Color(white: 0.20),
                faceHi: Color(white: 0.26), faceLo: Color(white: 0.16),
                ink: Color(white: 0.48), inkShadow: .black.opacity(0.35),
                glow: .clear,
                ribbonA: Color(white: 0.30), ribbonB: Color(white: 0.22), ribbonStripe: Color(white: 0.40))
        }
        switch rarity {
        case .legendary:
            return MedalPalette(
                rimHi: Color(red: 1.00, green: 0.93, blue: 0.62), rimLo: Color(red: 0.70, green: 0.46, blue: 0.08),
                faceHi: Color(red: 0.99, green: 0.82, blue: 0.40), faceLo: Color(red: 0.80, green: 0.55, blue: 0.12),
                ink: Color(red: 1.00, green: 0.98, blue: 0.90),
                inkShadow: Color(red: 0.45, green: 0.26, blue: 0.0).opacity(0.55),
                glow: Color(red: 1.00, green: 0.74, blue: 0.20),
                ribbonA: Color(red: 0.78, green: 0.16, blue: 0.22), ribbonB: Color(red: 0.55, green: 0.08, blue: 0.14),
                ribbonStripe: Color(red: 1.00, green: 0.84, blue: 0.40))
        case .rare:
            return MedalPalette(
                rimHi: Color(red: 0.90, green: 0.84, blue: 1.00), rimLo: Color(red: 0.40, green: 0.22, blue: 0.68),
                faceHi: Color(red: 0.72, green: 0.56, blue: 0.98), faceLo: Color(red: 0.45, green: 0.26, blue: 0.78),
                ink: .white, inkShadow: Color(red: 0.20, green: 0.06, blue: 0.40).opacity(0.55),
                glow: Color(red: 0.62, green: 0.40, blue: 0.96),
                ribbonA: Color(red: 0.22, green: 0.20, blue: 0.55), ribbonB: Color(red: 0.13, green: 0.11, blue: 0.38),
                ribbonStripe: Color(red: 0.80, green: 0.66, blue: 1.00))
        case .common:
            return MedalPalette(
                rimHi: Color(red: 0.84, green: 0.92, blue: 1.00), rimLo: Color(red: 0.20, green: 0.40, blue: 0.72),
                faceHi: Color(red: 0.55, green: 0.74, blue: 0.99), faceLo: Color(red: 0.26, green: 0.48, blue: 0.84),
                ink: .white, inkShadow: Color(red: 0.06, green: 0.18, blue: 0.42).opacity(0.55),
                glow: Color(red: 0.32, green: 0.58, blue: 0.98),
                ribbonA: Color(red: 0.16, green: 0.30, blue: 0.62), ribbonB: Color(red: 0.09, green: 0.18, blue: 0.42),
                ribbonStripe: Color(red: 0.70, green: 0.86, blue: 1.00))
        }
    }
}

// MARK: - The medal disc

/// A struck medal: one metallic rim lit from the top, a recessed face, a fine
/// raised inner ring, and the icon stamped in relief. It replaced a design
/// that layered a knurled double rim, a radial blob highlight and a heavy
/// glow — which read as busy at grid size and smudgy at hero size. Locked
/// medals keep their icon (dimmed) and carry a small lock badge in the corner
/// instead of a lock drawn on top of the icon.
struct MedalView: View {
    let badge: Badge
    var size: CGFloat = 120
    /// Device tilt, -1...1. Drive these for a live 3D effect, or leave 0 for a
    /// static render in grids.
    var roll: Double = 0
    var pitch: Double = 0
    var showShimmer: Bool = true

    @State private var shimmer: CGFloat = -1.2
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var locked: Bool { badge.isLocked }
    private var palette: MedalPalette { MedalPalette.forRarity(badge.rarity, locked: locked) }
    private var rimWidth: CGFloat { size * 0.075 }

    // Stagger each medal's shimmer so a grid doesn't sweep in unison.
    private var shimmerDelay: Double {
        Double(abs(badge.id.hashValue) % 100) / 100.0 * 2.2
    }

    var body: some View {
        ZStack {
            rim
            face
            innerRing
            stampedIcon
            if !locked { sheen }
            if showShimmer && !locked { shimmerSweep }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) { if locked { lockBadge } }
        .compositingGroup()
        .rotation3DEffect(.degrees(pitch * 9), axis: (x: -1, y: 0, z: 0), perspective: 0.5)
        .rotation3DEffect(.degrees(roll * 9), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .shadow(color: locked ? .black.opacity(0.35) : palette.glow.opacity(0.35),
                radius: size * 0.08, x: 0, y: size * 0.04)
        .onAppear {
            guard showShimmer && !locked && !reduceMotion else { return }
            withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false).delay(0.5 + shimmerDelay)) {
                shimmer = 1.4
            }
        }
        .onDisappear {
            // Park the sweep off the disc (invisible) so a medal scrolled out of
            // a lazy grid stops re-compositing; onAppear starts it again.
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { shimmer = -1.2 }
        }
    }

    private var rim: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [palette.rimHi, palette.rimLo],
                                         startPoint: .top, endPoint: .bottom))
            // Hairline catch-light on the outer edge.
            Circle().strokeBorder(Color.white.opacity(locked ? 0.10 : 0.45),
                                  lineWidth: max(0.75, size * 0.008))
        }
    }

    /// Recessed into the rim, so it's darker at the top — a dish catches light
    /// at its lower lip — with a thin shadow where it meets the rim.
    private var face: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [palette.faceLo, palette.faceHi],
                                         startPoint: .top, endPoint: .bottom))
            Circle().strokeBorder(Color.black.opacity(0.22), lineWidth: max(1, size * 0.012))
        }
        .padding(rimWidth)
    }

    /// The one detail that makes it read as a struck medal rather than a button.
    private var innerRing: some View {
        Circle()
            .strokeBorder(
                LinearGradient(colors: [palette.rimHi.opacity(0.9), palette.rimLo.opacity(0.6)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: max(1, size * 0.014)
            )
            .padding(rimWidth + size * 0.06)
    }

    private var stampedIcon: some View {
        Image(systemName: iconName(for: badge))
            .font(.system(size: size * 0.32, weight: .bold))
            .foregroundStyle(palette.ink)
            // A hard 1-step drop under the icon: stamped, not glowing.
            .shadow(color: palette.inkShadow, radius: 0, x: 0, y: max(1, size * 0.012))
            .opacity(locked ? 0.55 : 1)
    }

    /// A soft arc of light across the upper rim that slides a little with tilt.
    private var sheen: some View {
        Circle()
            .trim(from: 0.58, to: 0.92)
            .stroke(Color.white.opacity(0.22),
                    style: StrokeStyle(lineWidth: size * 0.018, lineCap: .round))
            .rotationEffect(.degrees(roll * 25))
            .padding(rimWidth + size * 0.02)
            .blendMode(.screen)
    }

    private var shimmerSweep: some View {
        // A narrow blade of light that sweeps across the face like a camera
        // flash reflecting off polished metal.
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.10), Color.white.opacity(0.28),
                             Color.white.opacity(0.10), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .frame(width: size * 0.22, height: size * 1.6)
            .rotationEffect(.degrees(25))
            .offset(x: shimmer * size)
            .blendMode(.screen)
            .mask(Circle().padding(rimWidth))
            .allowsHitTesting(false)
    }

    private var lockBadge: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: size * 0.12, weight: .bold))
            .foregroundColor(.white.opacity(0.85))
            .frame(width: size * 0.26, height: size * 0.26)
            .background(Circle().fill(Color(white: 0.14)))
            .overlay(Circle().strokeBorder(Color(white: 0.32), lineWidth: max(1, size * 0.01)))
            .accessibilityLabel("Locked")
    }
}

// MARK: - Neck ribbon

/// Two straps converging into a metal loop on the medal's top edge, so the
/// ribbon and the disc read as ONE object. The detail screen used to draw a
/// short flag-cut ribbon floating ABOVE the medal with a gap under it.
struct MedalRibbon: View {
    let badge: Badge
    var medalSize: CGFloat

    private var palette: MedalPalette { .forRarity(badge.rarity, locked: badge.isLocked) }

    var body: some View {
        let spread = medalSize * 0.62
        let drop = medalSize * 0.62
        let strap = medalSize * 0.24
        ZStack(alignment: .top) {
            strapView(left: true, spread: spread, drop: drop, strap: strap)
            strapView(left: false, spread: spread, drop: drop, strap: strap)
        }
        .frame(width: spread + strap, height: drop)
        .accessibilityHidden(true)
    }

    private func strapView(left: Bool, spread: CGFloat, drop: CGFloat, strap: CGFloat) -> some View {
        let band = Path { path in
            let top: CGFloat = left ? 0 : spread
            let bottom = spread / 2
            path.move(to: CGPoint(x: top, y: 0))
            path.addLine(to: CGPoint(x: top + strap, y: 0))
            path.addLine(to: CGPoint(x: bottom + strap, y: drop))
            path.addLine(to: CGPoint(x: bottom, y: drop))
            path.closeSubpath()
        }
        let stripe = Path { path in
            let top: CGFloat = (left ? 0 : spread) + strap * 0.4
            let bottom = spread / 2 + strap * 0.4
            path.move(to: CGPoint(x: top, y: 0))
            path.addLine(to: CGPoint(x: top + strap * 0.2, y: 0))
            path.addLine(to: CGPoint(x: bottom + strap * 0.2, y: drop))
            path.addLine(to: CGPoint(x: bottom, y: drop))
            path.closeSubpath()
        }
        return ZStack {
            band.fill(LinearGradient(colors: left ? [palette.ribbonA, palette.ribbonB]
                                                  : [palette.ribbonB, palette.ribbonA],
                                     startPoint: .leading, endPoint: .trailing))
            stripe.fill(palette.ribbonStripe.opacity(0.9))
            // Shade toward the bottom, where the straps tuck behind the loop.
            band.fill(LinearGradient(colors: [.clear, .black.opacity(0.30)],
                                     startPoint: .top, endPoint: .bottom))
        }
        .frame(width: spread + strap, height: drop)
    }
}

/// Ribbon, loop and disc together — the medal as it hangs. Hero surfaces
/// (the medal detail, the share card) use this; grids use the bare disc.
struct HangingMedal: View {
    let badge: Badge
    var size: CGFloat = 156
    var roll: Double = 0
    var pitch: Double = 0
    var showShimmer: Bool = true

    private var palette: MedalPalette { .forRarity(badge.rarity, locked: badge.isLocked) }

    var body: some View {
        let loop = size * 0.16
        VStack(spacing: -loop * 0.45) {
            ZStack(alignment: .bottom) {
                MedalRibbon(badge: badge, medalSize: size)
                Capsule()
                    .strokeBorder(LinearGradient(colors: [palette.rimHi, palette.rimLo],
                                                 startPoint: .top, endPoint: .bottom),
                                  lineWidth: size * 0.032)
                    .frame(width: loop * 1.2, height: loop)
                    .offset(y: loop * 0.35)
            }
            MedalView(badge: badge, size: size, roll: roll, pitch: pitch, showShimmer: showShimmer)
        }
    }
}

// MARK: - Live-tilt hero medal

/// `MedalView` driven by live device motion. Use for the single large medal on
/// the detail screen and the unlock celebration. Starts/stops the shared sensor
/// with its lifetime.
struct TiltableMedal: View {
    let badge: Badge
    var size: CGFloat = 160
    var showShimmer: Bool = true
    /// Draw it hanging from its neck ribbon (the medal detail screen).
    var hanging: Bool = false

    @ObservedObject private var motion = MedalMotion.shared

    var body: some View {
        Group {
            if hanging {
                HangingMedal(badge: badge, size: size,
                             roll: badge.isLocked ? 0 : motion.roll,
                             pitch: badge.isLocked ? 0 : motion.pitch,
                             showShimmer: showShimmer)
            } else {
                MedalView(badge: badge, size: size,
                          roll: badge.isLocked ? 0 : motion.roll,
                          pitch: badge.isLocked ? 0 : motion.pitch,
                          showShimmer: showShimmer)
            }
        }
            .onAppear { if !badge.isLocked { motion.start() } }
            .onDisappear { if !badge.isLocked { motion.stop() } }
    }
}

// MARK: - Previews

#Preview("Medals") {
    ZStack {
        Color.black.ignoresSafeArea()
        HStack(spacing: 24) {
            MedalView(badge: Badge(id: "streak_7", name: "Common", description: ""), size: 110)
            MedalView(badge: Badge(id: "streak_100", name: "Rare", description: ""), size: 110)
            MedalView(badge: Badge(id: "streak_365", name: "Legendary", description: ""), size: 110)
            MedalView(badge: Badge(id: "miles_500", name: "Locked", description: "", isLocked: true), size: 110)
        }
    }
}
