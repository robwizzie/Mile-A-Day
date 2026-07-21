import SwiftUI

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

/// The tokens' one home on the Dashboard: a standalone card, always present
/// while the feature is active (never dependent on which week-view tab is
/// selected — the old in-StreakCard row vanished on the chart/trends tabs).
/// Renders nothing when the server gate is off. Tapping opens the explainer.
struct StreakTokensCard: View {
    @ObservedObject var tokensState = StreakTokensState.shared
    @State private var showDetail = false

    var body: some View {
        if let payload = tokensState.payload {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showDetail = true
            } label: {
                VStack(spacing: 12) {
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
                        meterCell(
                            emoji: "\u{1F525}",
                            label: "Double Down",
                            fraction: payload.double_down.fraction,
                            held: payload.double_down.held,
                            tint: .orange
                        )
                        meterCell(
                            emoji: "\u{2744}\u{FE0F}",
                            label: "Streak Save",
                            fraction: payload.streak_save.fraction,
                            held: payload.streak_save.held,
                            tint: MADTheme.Colors.walkBlue
                        )
                        meterCell(
                            emoji: "\u{1F91D}",
                            label: "Assist",
                            fraction: payload.streak_assist.fraction,
                            held: payload.streak_assist.held,
                            tint: MADTheme.Colors.madRed
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

    private func meterCell(
        emoji: String, label: String, fraction: Double, held: Bool, tint: Color
    ) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: held ? 1 : fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(emoji)
                    .font(.system(size: 13))
                    .opacity(held ? 1 : 0.55)
            }
            .frame(width: 32, height: 32)
            .overlay(alignment: .topTrailing) {
                if held {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.green)
                        .background(Circle().fill(.black.opacity(0.6)))
                        .offset(x: 4, y: -3)
                }
            }

            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(held ? 0.9 : 0.55))
                .lineLimit(1)
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
                                emoji: "\u{1F525}",
                                title: "Double Down",
                                tint: .orange,
                                what: "Miss a day? Run 2× your goal the next day and yesterday still counts.",
                                how: "Earn it by completing your mile 14 days (runs or walks count).",
                                meter: .init(
                                    progress: payload.double_down.progress,
                                    target: payload.double_down.target,
                                    held: payload.double_down.held,
                                    last_used: payload.double_down.last_used
                                ),
                                unit: "days"
                            )

                            tokenCard(
                                emoji: "\u{2744}\u{FE0F}",
                                title: "Streak Save",
                                tint: MADTheme.Colors.walkBlue,
                                what: "Life happens — if you miss a day and can't Double Down, this covers it automatically.",
                                how: "Earn it with 7 days of running your mile (walks don't count toward this one).",
                                meter: payload.streak_save,
                                unit: "run days"
                            )

                            tokenCard(
                                emoji: "\u{1F91D}",
                                title: "Streak Assist",
                                tint: MADTheme.Colors.madRed,
                                what: "Save a FRIEND's streak the day after it breaks — be their hero.",
                                how: "Earn it by going 20 miles beyond your daily goal, over any number of days.",
                                meter: payload.streak_assist,
                                unit: "mi over goal"
                            )

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
        emoji: String,
        title: String,
        tint: Color,
        what: String,
        how: String,
        meter: StreakTokenMeter,
        unit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            HStack(spacing: 10) {
                Text(emoji).font(.system(size: 22))
                Text(title)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
                if meter.held {
                    Text("READY")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.green.opacity(0.85)))
                }
            }

            Text(what)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(how)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Meter bar + count
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(tint)
                            .frame(width: max(6, geo.size.width * (meter.held ? 1 : meter.fraction)))
                    }
                }
                .frame(height: 8)

                Text(meter.held
                     ? "Earned — 1 held (max 1). Using it restarts the meter."
                     : "\(trimmed(meter.progress)) / \(trimmed(meter.target)) \(unit)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(meter.held ? .green : .secondary)
            }
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
