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

struct MedalPalette {
    let rimHi: Color, rimMid: Color, rimLo: Color
    let faceHi: Color, faceMid: Color, faceLo: Color
    let iconHi: Color, iconLo: Color
    let glow: Color

    static func forRarity(_ rarity: BadgeRarity, locked: Bool) -> MedalPalette {
        if locked {
            return MedalPalette(
                rimHi: Color(red: 0.46, green: 0.47, blue: 0.51),
                rimMid: Color(red: 0.30, green: 0.31, blue: 0.35),
                rimLo: Color(red: 0.16, green: 0.17, blue: 0.20),
                faceHi: Color(red: 0.34, green: 0.35, blue: 0.39),
                faceMid: Color(red: 0.24, green: 0.25, blue: 0.29),
                faceLo: Color(red: 0.13, green: 0.14, blue: 0.17),
                iconHi: Color(red: 0.55, green: 0.56, blue: 0.60),
                iconLo: Color(red: 0.30, green: 0.31, blue: 0.35),
                glow: .clear
            )
        }
        switch rarity {
        case .legendary:
            return MedalPalette(
                rimHi: Color(red: 1.00, green: 0.95, blue: 0.66),
                rimMid: Color(red: 1.00, green: 0.80, blue: 0.26),
                rimLo: Color(red: 0.62, green: 0.40, blue: 0.04),
                faceHi: Color(red: 1.00, green: 0.89, blue: 0.52),
                faceMid: Color(red: 0.95, green: 0.71, blue: 0.22),
                faceLo: Color(red: 0.52, green: 0.32, blue: 0.02),
                iconHi: Color(red: 1.00, green: 0.98, blue: 0.84),
                iconLo: Color(red: 0.80, green: 0.54, blue: 0.12),
                glow: Color(red: 1.00, green: 0.76, blue: 0.20)
            )
        case .rare:
            return MedalPalette(
                rimHi: Color(red: 0.93, green: 0.87, blue: 1.00),
                rimMid: Color(red: 0.66, green: 0.45, blue: 0.96),
                rimLo: Color(red: 0.30, green: 0.13, blue: 0.52),
                faceHi: Color(red: 0.82, green: 0.64, blue: 1.00),
                faceMid: Color(red: 0.58, green: 0.36, blue: 0.86),
                faceLo: Color(red: 0.28, green: 0.12, blue: 0.48),
                iconHi: Color(red: 0.97, green: 0.93, blue: 1.00),
                iconLo: Color(red: 0.62, green: 0.42, blue: 0.92),
                glow: Color(red: 0.62, green: 0.36, blue: 0.96)
            )
        case .common:
            return MedalPalette(
                rimHi: Color(red: 0.86, green: 0.94, blue: 1.00),
                rimMid: Color(red: 0.42, green: 0.66, blue: 0.97),
                rimLo: Color(red: 0.12, green: 0.31, blue: 0.60),
                faceHi: Color(red: 0.64, green: 0.81, blue: 1.00),
                faceMid: Color(red: 0.34, green: 0.56, blue: 0.89),
                faceLo: Color(red: 0.13, green: 0.29, blue: 0.56),
                iconHi: Color(red: 0.93, green: 0.97, blue: 1.00),
                iconLo: Color(red: 0.42, green: 0.62, blue: 0.92),
                glow: Color(red: 0.30, green: 0.56, blue: 0.96)
            )
        }
    }
}

// MARK: - The medal disc

struct MedalView: View {
    let badge: Badge
    var size: CGFloat = 120
    /// Device tilt, -1...1. Drive these for a live 3D effect, or leave 0 for a
    /// static (but still premium) render in grids.
    var roll: Double = 0
    var pitch: Double = 0
    var showShimmer: Bool = true

    @State private var shimmer: CGFloat = -1.2
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var locked: Bool { badge.isLocked }
    private var palette: MedalPalette { MedalPalette.forRarity(badge.rarity, locked: locked) }
    private var rimWidth: CGFloat { size * 0.085 }
    private var icon: String { iconName(for: badge) }

    // Stagger each medal's shimmer so a grid doesn't sweep in unison.
    private var shimmerDelay: Double {
        Double(abs(badge.id.hashValue) % 100) / 100.0 * 2.2
    }

    var body: some View {
        ZStack {
            rim
            face
            bevel
            engravedIcon
            if !locked { specularHighlight }
            if showShimmer && !locked { shimmerSweep }
            if locked { lockGlyph }
        }
        .frame(width: size, height: size)
        .compositingGroup()
        .rotation3DEffect(.degrees(pitch * 9), axis: (x: -1, y: 0, z: 0), perspective: 0.5)
        .rotation3DEffect(.degrees(roll * 9), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .shadow(color: locked ? .black.opacity(0.35) : palette.glow.opacity(0.55),
                radius: size * 0.13, x: 0, y: size * 0.06)
        .onAppear {
            guard showShimmer && !locked && !reduceMotion else { return }
            withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false).delay(0.5 + shimmerDelay)) {
                shimmer = 1.4
            }
        }
    }

    // Metallic rim with an angular gradient that rotates slightly with tilt so it
    // catches "light" like brushed metal, plus a milled-edge knurl on bigger sizes.
    private var rim: some View {
        ZStack {
            Circle().fill(palette.rimLo)
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            palette.rimHi, palette.rimMid, palette.rimLo, palette.rimMid,
                            palette.rimHi, palette.rimLo, palette.rimMid, palette.rimHi,
                        ]),
                        center: .center,
                        angle: .degrees(roll * 35 - pitch * 15)
                    )
                )
            // Milled-edge detail is reserved for the large hero medals so grids of
            // many medals stay light.
            if size >= 120 { knurling }
        }
    }

    private var knurling: some View {
        ZStack {
            ForEach(0..<48, id: \.self) { i in
                Capsule()
                    .fill(Color.black.opacity(0.18))
                    .frame(width: size * 0.012, height: rimWidth * 0.9)
                    .offset(y: -(size / 2 - rimWidth / 2))
                    .rotationEffect(.degrees(Double(i) / 48.0 * 360.0))
            }
        }
        .mask(Circle())
    }

    // Domed coin face — radial gradient lit from the upper-left.
    private var face: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [palette.faceHi, palette.faceMid, palette.faceLo],
                    center: UnitPoint(x: 0.38, y: 0.32),
                    startRadius: 1,
                    endRadius: size * 0.52
                )
            )
            .padding(rimWidth)
    }

    // Beveled edge between rim and face: bright top-left, dark bottom-right.
    private var bevel: some View {
        Circle()
            .strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.55), Color.clear, Color.black.opacity(0.38)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: max(1.5, size * 0.02)
            )
            .padding(rimWidth)
    }

    private var engravedIcon: some View {
        ZStack {
            // Engrave shadow (down-right) and top highlight (up-left) sandwich the
            // metallic glyph for a stamped-into-metal look.
            Image(systemName: icon)
                .foregroundColor(.black.opacity(0.30))
                .offset(x: size * 0.008, y: size * 0.012)
            Image(systemName: icon)
                .foregroundColor(.white.opacity(locked ? 0.10 : 0.30))
                .offset(x: -size * 0.006, y: -size * 0.01)
            Image(systemName: icon)
                .foregroundStyle(
                    LinearGradient(colors: [palette.iconHi, palette.iconLo],
                                   startPoint: .top, endPoint: .bottom)
                )
        }
        .font(.system(size: size * 0.34, weight: .black))
        .opacity(locked ? 0.45 : 1)
    }

    // Soft white blob that slides with device tilt — the marquee "real medal" cue.
    private var specularHighlight: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color.white.opacity(0.6), Color.white.opacity(0)],
                    center: .center, startRadius: 0, endRadius: size * 0.32
                )
            )
            .frame(width: size * 0.6, height: size * 0.6)
            .offset(x: CGFloat(roll) * size * 0.26 + size * 0.06,
                    y: CGFloat(-pitch) * size * 0.26 - size * 0.12)
            .blendMode(.screen)
            .mask(Circle().padding(rimWidth * 0.5))
    }

    private var shimmerSweep: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.55), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .frame(width: size * 0.5, height: size * 1.6)
            .rotationEffect(.degrees(28))
            .offset(x: shimmer * size)
            .blendMode(.screen)
            .mask(Circle().padding(rimWidth * 0.5))
            .allowsHitTesting(false)
    }

    private var lockGlyph: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: size * 0.26, weight: .bold))
            .foregroundColor(.white.opacity(0.5))
            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
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

    @ObservedObject private var motion = MedalMotion.shared

    var body: some View {
        MedalView(badge: badge, size: size,
                  roll: badge.isLocked ? 0 : motion.roll,
                  pitch: badge.isLocked ? 0 : motion.pitch,
                  showShimmer: showShimmer)
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
