import SwiftUI

// MARK: - Token identity (one source of truth for look & copy)

enum StreakTokenKind {
    case doubleDown, save, assist

    var title: String {
        switch self {
        case .doubleDown: return "Double Down"
        case .save: return "Streak Save"
        case .assist: return "Streak Assist"
        }
    }

    var icon: String {
        switch self {
        case .doubleDown: return "flame.fill"
        case .save: return "snowflake"
        case .assist: return "lifepreserver"
        }
    }

    /// Coin-face gradient. Kept saturated and MAD-branded: ember for effort,
    /// ice for the freeze, brand red for the friend rescue.
    var gradient: [Color] {
        switch self {
        case .doubleDown:
            return [Color(red: 1.0, green: 0.62, blue: 0.20),
                    Color(red: 0.86, green: 0.28, blue: 0.08)]
        case .save:
            return [Color(red: 0.45, green: 0.78, blue: 1.0),
                    Color(red: 0.12, green: 0.42, blue: 0.85)]
        case .assist:
            return [Color(red: 0.95, green: 0.35, blue: 0.55),
                    MADTheme.Colors.madRed]
        }
    }

    var tint: Color {
        switch self {
        case .doubleDown: return .orange
        case .save: return MADTheme.Colors.walkBlue
        case .assist: return MADTheme.Colors.madRed
        }
    }

    var what: String {
        switch self {
        case .doubleDown:
            return "Miss a day? Run 2× your goal the next day and yesterday still counts."
        case .save:
            return "Life happens — if you miss a day and can't Double Down, this covers it automatically."
        case .assist:
            return "Save a friend's streak the day after it breaks — be their hero."
        }
    }

    var howToEarn: String {
        switch self {
        case .doubleDown:
            return "Complete your mile on 14 days — runs or walks both count."
        case .save:
            return "Run your full mile on 7 days. Running only — walks don't tick this one."
        case .assist:
            return "Go a total of 20 miles beyond your daily goal, over any number of days."
        }
    }
}

// MARK: - Token medallion (the token itself — a minted coin, not an emoji)

/// The canonical rendering of a token everywhere it appears: a coin with a
/// gradient face, top-light sheen, inner ring, and an engraved SF Symbol.
/// EARNED  → full color, gold rim, soft glow.
/// EARNING → dimmed face with a progress arc filling the rim.
struct TokenMedallion: View {
    let kind: StreakTokenKind
    var held: Bool = false
    /// 0…1 earn progress; ignored when held.
    var progress: Double = 0
    var size: CGFloat = 44

    private var gold: Color { Color(red: 1.0, green: 0.84, blue: 0.35) }

    var body: some View {
        ZStack {
            // Coin face
            Circle()
                .fill(
                    LinearGradient(
                        colors: kind.gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Top-light sheen — what makes it read as minted metal, not a dot.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.45), .clear],
                        center: .init(x: 0.32, y: 0.25),
                        startRadius: 0,
                        endRadius: size * 0.75
                    )
                )

            // Inner ring (the coin's lip)
            Circle()
                .strokeBorder(Color.white.opacity(0.35), lineWidth: max(1, size * 0.035))
                .padding(size * 0.10)

            // Engraved icon
            Image(systemName: kind.icon)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
        }
        .frame(width: size, height: size)
        .saturation(held ? 1 : 0.45)
        .opacity(held ? 1 : 0.85)
        .overlay(
            // Rim: solid gold when earned; progress arc while earning.
            Group {
                if held {
                    Circle().strokeBorder(gold, lineWidth: max(1.5, size * 0.05))
                } else {
                    Circle()
                        .trim(from: 0, to: max(0.02, min(progress, 1)))
                        .stroke(
                            kind.tint,
                            style: StrokeStyle(lineWidth: max(1.5, size * 0.05), lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .padding(max(0.75, size * 0.025))
                }
            }
        )
        .shadow(color: held ? kind.tint.opacity(0.55) : .clear, radius: size * 0.18)
        .accessibilityLabel("\(kind.title)\(held ? ", ready" : "")")
    }
}

// MARK: - Pure Flame badge (natural streak)

/// The "never needed a rescue" seal — shown beside the username when the
/// current streak is 100% natural (no Save, Double Down, or received Assist
/// inside it). Mile A Day's answer to a verified check: a gold-ringed flame.
struct PureFlameBadge: View {
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.84, blue: 0.3),
                                 Color(red: 0.95, green: 0.55, blue: 0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "flame.fill")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 1.2))
        .shadow(color: Color.orange.opacity(0.45), radius: 3)
        .accessibilityLabel("Natural streak — every day earned")
    }
}

// MARK: - Dashboard card

/// The tokens' home on the Dashboard: three minted medallions with earn
/// progress, always present while the feature is active (never dependent on
/// which week-view tab is selected). Renders nothing when the server gate is
/// off. Tapping opens the explainer.
struct StreakTokensCard: View {
    @ObservedObject var tokensState = StreakTokensState.shared
    @State private var showDetail = false
    /// Drives the slow breathing pulse on earned medallions.
    @State private var pulse = false

    var body: some View {
        if let payload = tokensState.payload {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showDetail = true
            } label: {
                VStack(spacing: 14) {
                    HStack(spacing: MADTheme.Spacing.sm) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(MADTheme.Colors.redGradient)
                        Text("Streak Tokens")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        Spacer()
                        let ready = [
                            payload.double_down.held,
                            payload.streak_save.held,
                            payload.streak_assist.held,
                        ].filter { $0 }.count
                        Text(ready > 0 ? "\(ready) ready" : "How they work")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(ready > 0 ? .green : .white.opacity(0.55))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.4))
                    }

                    HStack(spacing: 0) {
                        medallionCell(
                            kind: .doubleDown,
                            held: payload.double_down.held,
                            progress: payload.double_down.fraction,
                            caption: payload.double_down.held
                                ? "Ready"
                                : "\(Int(payload.double_down.progress))/\(Int(payload.double_down.target))"
                        )
                        medallionCell(
                            kind: .save,
                            held: payload.streak_save.held,
                            progress: payload.streak_save.fraction,
                            caption: payload.streak_save.held
                                ? "Ready"
                                : "\(Int(payload.streak_save.progress))/\(Int(payload.streak_save.target))"
                        )
                        medallionCell(
                            kind: .assist,
                            held: payload.streak_assist.held,
                            progress: payload.streak_assist.fraction,
                            caption: payload.streak_assist.held
                                ? "Ready"
                                : String(format: "%.1f/%.0f mi", payload.streak_assist.progress, payload.streak_assist.target)
                        )
                    }

                    if payload.streak_at_risk {
                        HStack(spacing: 6) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("Missed yesterday — run 2× today to save your streak!")
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(MADTheme.Spacing.md)
                .madLiquidGlass()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showDetail) {
                StreakTokensDetailView()
            }
        }
    }

    private func medallionCell(
        kind: StreakTokenKind, held: Bool, progress: Double, caption: String
    ) -> some View {
        VStack(spacing: 6) {
            TokenMedallion(kind: kind, held: held, progress: progress, size: 46)
                // Earned tokens breathe gently — alive, not static.
                .scaleEffect(held && pulse ? 1.05 : 1.0)
                .animation(
                    held
                        ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true)
                        : .default,
                    value: pulse
                )
                .onAppear { pulse = true }
            Text(kind.title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(held ? 0.95 : 0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(caption)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundColor(held ? .green : .white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Full explainer sheet

/// What each token does, how it's earned, and where its meter stands — the
/// "easily known how to unlock and what they do" surface.
struct StreakTokensDetailView: View {
    @ObservedObject var tokensState = StreakTokensState.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: MADTheme.Spacing.md) {
                        if let payload = tokensState.payload {
                            if payload.streak_at_risk {
                                atRiskBanner(payload)
                            }

                            tokenCard(
                                kind: .doubleDown,
                                meter: StreakTokenMeter(
                                    progress: payload.double_down.progress,
                                    target: payload.double_down.target,
                                    held: payload.double_down.held,
                                    last_used: payload.double_down.last_used
                                ),
                                unit: "days"
                            )
                            tokenCard(kind: .save, meter: payload.streak_save, unit: "run days")
                            tokenCard(kind: .assist, meter: payload.streak_assist, unit: "mi over goal")

                            naturalCard(payload.natural_streak)
                        } else {
                            ProgressView().tint(.white)
                                .padding(.top, MADTheme.Spacing.xl)
                        }
                    }
                    .padding(MADTheme.Spacing.md)
                }
            }
            .navigationTitle("Streak Tokens")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(MADTheme.Colors.madRed)
                        .fontWeight(.semibold)
                }
            }
            .task { await tokensState.refreshStatus() }
        }
    }

    private func atRiskBanner(_ payload: StreakFeaturesPayload) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your streak is on the line")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(.primary)
                Text("You missed yesterday. Run \(String(format: "%.1f", payload.double_down.recover_miles ?? 2.0)) mi today to Double Down and save it.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.orange.opacity(0.13))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private func tokenCard(
        kind: StreakTokenKind,
        meter: StreakTokenMeter,
        unit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            HStack(spacing: 14) {
                TokenMedallion(
                    kind: kind,
                    held: meter.held,
                    progress: meter.fraction,
                    size: 54
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.title)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundColor(.primary)
                    Text(kind.what)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if meter.held {
                    Text("READY")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.green.opacity(0.85)))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("HOW TO EARN")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1.1)
                    .foregroundColor(kind.tint)
                Text(kind.howToEarn)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TokenMeterBar(kind: kind, meter: meter, unit: unit)
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    private func naturalCard(_ natural: Bool) -> some View {
        HStack(spacing: 12) {
            if natural {
                PureFlameBadge(size: 30)
            } else {
                Image(systemName: "flame")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 30, height: 30)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(natural ? "Pure Flame — natural streak" : "Streak rescued along the way")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(.primary)
                Text(natural
                     ? "Every day of this streak was earned on the day. The gold flame shows on your profile."
                     : "A token kept this streak alive — the Pure Flame returns with your next untouched streak. (Helping a friend never affects yours.)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    private func trimmed(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}

// MARK: - Animated meter bar

/// The earn meter, made satisfying: the fill springs from zero on appear, a
/// light shimmer sweeps the filled portion, and the copy counts DOWN ("3 to
/// go") so progress reads as approach, not bookkeeping.
private struct TokenMeterBar: View {
    let kind: StreakTokenKind
    let meter: StreakTokenMeter
    let unit: String

    @State private var grown = false
    @State private var shimmer = false

    private var fraction: Double { meter.held ? 1 : meter.fraction }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let fillWidth = max(6, geo.size.width * fraction * (grown ? 1 : 0))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: kind.gradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fillWidth)
                        .overlay(
                            // Shimmer sweep across the filled portion.
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.clear, .white.opacity(0.45), .clear],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: 46)
                                .offset(x: shimmer ? fillWidth : -46)
                                .animation(
                                    .linear(duration: 1.8)
                                        .repeatForever(autoreverses: false)
                                        .delay(0.8),
                                    value: shimmer
                                )
                                .mask(Capsule().frame(width: fillWidth))
                        , alignment: .leading)
                }
            }
            .frame(height: 8)

            Text(statusLine)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(meter.held ? .green : .secondary)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.15)) {
                grown = true
            }
            if fraction > 0.1 { shimmer = true }
        }
    }

    private var statusLine: String {
        if meter.held {
            return "Earned — you're holding 1 (max 1). Using it restarts the meter."
        }
        let remaining = max(meter.target - meter.progress, 0)
        let togo = remaining.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(remaining))
            : String(format: "%.1f", remaining)
        let progressText = meter.progress.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(meter.progress))
            : String(format: "%.1f", meter.progress)
        let targetText = meter.target.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(meter.target))
            : String(format: "%.1f", meter.target)
        return "\(progressText) / \(targetText) \(unit) · \(togo) to go"
    }
}
