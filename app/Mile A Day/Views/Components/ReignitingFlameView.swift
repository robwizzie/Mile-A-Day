import SwiftUI

struct ReignitingFlameView: View {
    var showsFace: Bool
    var size: CGFloat = 220
    var progress: CGFloat
    var intensity: CGFloat = 1
    var startsSad: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clampedProgress: CGFloat {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            heatGlow
            ignitionWave

            if reduceMotion {
                flame(phase: 0, blink: false)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    flame(
                        phase: CGFloat(t * 5.0),
                        blink: showsFace && clampedProgress > 0.84 && Int(t * 2.0) % 11 == 0
                    )
                }
            }

            // The moment the coal catches: a bright burst of light that peaks as
            // the ember ignites, then fades. This is the "it caught fire" beat the
            // plain grow was missing. Only the reignite (sad) path has an ember.
            if startsSad {
                catchFlash
            }

            ignitionSparks
        }
        .frame(width: size * 1.34, height: size * 1.24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(clampedProgress >= 1 ? "Flame reignited" : "Flame reigniting")
    }

    @ViewBuilder
    private func flame(phase: CGFloat, blink: Bool) -> some View {
        ZStack {
            // The dying coal lingers, then hands off to the flame that catches
            // over it — a crossfade instead of a hard swap, so the ember visibly
            // BECOMES fire rather than popping into it. Only the reignite path
            // has an ember; the plain (Modern) path renders the flame alone.
            if startsSad {
                SadEmberBuddy(size: size * 0.46, progress: min(1, clampedProgress / 0.24))
                    .scaleEffect(0.86 + clampedProgress * 0.42, anchor: .bottom)
                    .offset(y: size * 0.24)
                    .opacity(emberOpacity)
            }

            flameFigure(phase: phase, blink: blink)
                .opacity(flameFadeIn)
        }
    }

    private func flameFigure(phase: CGFloat, blink: Bool) -> some View {
        FlameBuddyFigure(
            health: revivalHealth,
            flickerPhase: phase,
            blink: blink,
            size: size,
            showsFace: showsFace && (startsSad || clampedProgress > 0.58)
        )
        .scaleEffect(
            x: flameScale * (1 + sin(phase * 0.42) * 0.014 * effectiveFlameProgress),
            y: flameScale * (1 + cos(phase * 0.34) * 0.010 * effectiveFlameProgress),
            anchor: .bottom
        )
        .opacity(flameOpacity)
        .offset(y: (1 - easedFlameProgress) * size * 0.22 + sin(phase * 0.38) * 1.2 * effectiveFlameProgress)
        .shadow(color: Color.orange.opacity(Double(effectiveFlameProgress) * Double(0.28 * intensity)), radius: size * 0.10 * intensity, x: 0, y: size * 0.04)
    }

    /// Coal opacity: full while it lingers, gone once the flame has caught over
    /// it. Crossfaded against `flameFadeIn` across the same window for a smooth
    /// hand-off. Reignite (sad) path only.
    private var emberOpacity: Double {
        guard startsSad else { return 0 }
        return Double(1 - smoothstep(0.16, 0.40, clampedProgress))
    }

    /// Flame fade-in as it catches over the ember. The plain (Modern) path shows
    /// the flame at full opacity throughout — it IS the whole animation.
    private var flameFadeIn: Double {
        guard startsSad else { return 1 }
        return Double(smoothstep(0.16, 0.40, clampedProgress))
    }

    /// Triangular pulse that peaks as the coal ignites (~progress 0.34), driving
    /// the catch-flash burst. Squared for a sharper, more ignition-like peak.
    private var catchIntensity: Double {
        let center: CGFloat = 0.34
        let halfWidth: CGFloat = 0.22
        let raw = max(0, 1 - abs(clampedProgress - center) / halfWidth)
        return Double(raw * raw)
    }

    private var catchFlash: some View {
        let scale = 0.44 + CGFloat(catchIntensity) * 1.05
        return RadialGradient(
            gradient: Gradient(colors: [
                Color.white.opacity(0.92),
                Color(red: 1.0, green: 0.80, blue: 0.34).opacity(0.58),
                Color.orange.opacity(0)
            ]),
            center: .center,
            startRadius: 0,
            endRadius: size * 0.5
        )
        .frame(width: size * scale, height: size * scale)
        .offset(y: size * 0.08)
        .opacity(catchIntensity)
        .blur(radius: size * 0.02)
        .blendMode(.screen)
        .allowsHitTesting(false)
    }

    /// Hermite smoothstep — eases a linear ramp between two edges into an
    /// S-curve so crossfades start and end gently instead of clipping.
    private func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        guard edge1 > edge0 else { return x < edge0 ? 0 : 1 }
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private var easedProgress: CGFloat {
        clampedProgress * clampedProgress * (3 - 2 * clampedProgress)
    }

    private var effectiveFlameProgress: CGFloat {
        guard startsSad else { return clampedProgress }
        return max(0, min(1, (clampedProgress - 0.22) / 0.78))
    }

    private var easedFlameProgress: CGFloat {
        effectiveFlameProgress * effectiveFlameProgress * (3 - 2 * effectiveFlameProgress)
    }

    private var flameScale: CGFloat {
        0.10 + easedFlameProgress * 0.92
    }

    private var flameOpacity: Double {
        Double(min(1, 0.10 + easedFlameProgress * 1.10))
    }

    private var revivalHealth: FlameHealth {
        guard startsSad else { return .blazing }
        if clampedProgress < 0.46 { return .low }
        if clampedProgress < 0.72 { return .dimming }
        if clampedProgress < 0.88 { return .healthy }
        return .blazing
    }

    private var heatGlow: some View {
        ZStack {
            Circle()
                .fill(Color.orange.opacity(Double(effectiveFlameProgress) * Double(0.18 * intensity)))
                .blur(radius: size * 0.25)
                .frame(width: size * 1.08, height: size * 1.00)
            Circle()
                .fill(MADTheme.Colors.madRed.opacity(Double(effectiveFlameProgress) * Double(0.10 * intensity)))
                .blur(radius: size * 0.38)
                .frame(width: size * 1.34, height: size * 1.08)
                .offset(y: size * 0.12)
            Ellipse()
                .fill(Color.orange.opacity(Double(effectiveFlameProgress) * Double(0.20 * intensity)))
                .blur(radius: size * 0.12)
                .frame(width: size * 0.74, height: size * 0.22)
                .offset(y: size * 0.44)
        }
    }

    private var ignitionWave: some View {
        let wave = max(0, min(1, (effectiveFlameProgress - 0.05) / 0.70))
        return Circle()
            .stroke(
                Color.orange.opacity(Double((1 - wave) * 0.42 * intensity)),
                style: StrokeStyle(lineWidth: max(1.5, size * 0.018), lineCap: .round)
            )
            .frame(width: size * (0.34 + wave * 0.82), height: size * (0.28 + wave * 0.70))
            .scaleEffect(x: 1.10, y: 0.82)
            .offset(y: size * 0.10)
            .blur(radius: size * 0.006)
            .opacity(effectiveFlameProgress > 0.05 && effectiveFlameProgress < 0.90 ? 1 : 0)
    }

    private var ignitionSparks: some View {
        ZStack {
            ForEach(0..<7, id: \.self) { index in
                let appear = max(0, min(1, (effectiveFlameProgress - 0.12 - CGFloat(index) * 0.035) / 0.36))
                Capsule()
                    .fill(index.isMultiple(of: 2) ? Color.orange.opacity(0.62) : Color.yellow.opacity(0.46))
                    .frame(width: 3, height: 10 + CGFloat(index % 3) * 3)
                    .rotationEffect(.degrees(Double([-18, 22, -36, 14, 34, -9, 26][index])))
                    .offset(
                        x: CGFloat([-58, -36, -18, 28, 47, 64, 5][index]) / 220 * size,
                        y: (CGFloat([54, 34, 14, 20, 42, 62, 2][index]) / 220 * size) - appear * size * 0.36
                    )
                    .opacity(Double(appear) * Double(0.58 * intensity) * Double(1 - max(0, clampedProgress - 0.82) / 0.16))
            }
        }
    }
}

private struct SadEmberBuddy: View {
    let size: CGFloat
    let progress: CGFloat

    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.32))
                .frame(width: size * 0.88, height: size * 0.20)
                .blur(radius: 3)
                .offset(y: size * 0.42)

            Circle()
                .fill(Color(red: 0.18, green: 0.12, blue: 0.12))
                .frame(width: size * 0.72, height: size * 0.58)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: max(1, size * 0.014))
                )
                .shadow(color: Color.orange.opacity(Double(progress) * 0.16), radius: size * 0.10, x: 0, y: 4)

            HStack(spacing: size * 0.20) {
                SadEmberFrownShape()
                    .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: max(1.5, size * 0.018), lineCap: .round))
                    .frame(width: size * 0.13, height: size * 0.07)
                    .rotationEffect(.degrees(8))
                SadEmberFrownShape()
                    .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: max(1.5, size * 0.018), lineCap: .round))
                    .frame(width: size * 0.13, height: size * 0.07)
                    .rotationEffect(.degrees(-8))
            }
            .offset(y: -size * 0.06)

            SadEmberFrownShape()
                .stroke(Color.white.opacity(0.62), style: StrokeStyle(lineWidth: max(2, size * 0.022), lineCap: .round))
                .frame(width: size * 0.26, height: size * 0.10)
                .offset(y: size * 0.13)

            Circle()
                .fill(Color.orange.opacity(Double(progress) * 0.50))
                .frame(width: size * 0.10, height: size * 0.10)
                .blur(radius: 2)
                .offset(x: -size * 0.18, y: size * 0.25)
        }
        .frame(width: size, height: size)
    }
}

private struct SadEmberFrownShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY * 0.78))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY * 0.78),
            control: CGPoint(x: rect.midX, y: rect.minY)
        )
        return path
    }
}
