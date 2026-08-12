import SwiftUI

/// This week's challenge, at the top of the Compete tab.
///
/// The reason the tab is worth opening when you have no competitions: there is
/// always something running, it's the same thing your friends got, and the
/// number is sized to you rather than to an average.
struct WeeklyChallengeHeroCard: View {
    let response: WeeklyChallengeResponse
    var compact: Bool = false
    let action: () -> Void

    private var gradientColors: [Color] {
        [
            Color(hex: response.challenge.gradient_start),
            Color(hex: response.challenge.gradient_end)
        ]
    }

    private var progressText: String {
        let value = WeeklyChallengeFormat.value(
            response.progress.value,
            unit: response.challenge.unit
        )
        let target = WeeklyChallengeFormat.value(
            response.target,
            unit: response.challenge.unit
        )
        return "\(value) / \(target) \(response.challenge.unit)"
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                header
                progressBar
                if !compact { footer }
            }
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [gradientColors[0].opacity(0.16), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [gradientColors[0].opacity(0.45), Color.white.opacity(0.06)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: response.challenge.icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(
                    LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 42, height: 42)
                .background(
                    Circle()
                        .fill(gradientColors[0].opacity(0.15))
                        .overlay(Circle().strokeBorder(gradientColors[0].opacity(0.45), lineWidth: 1))
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("THIS WEEK")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .tracking(1.2)
                        .foregroundColor(gradientColors[0])

                    if response.progress.completed {
                        Text("DONE")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .tracking(1.2)
                            .foregroundColor(.green)
                    }
                }

                Text(response.challenge.title)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(WeeklyChallengeFormat.daysLeft(response.days_left))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                // The title truncates before this does.
                .fixedSize()
        }
    }

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(response.challenge.description)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(
                            LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: max(0, geo.size.width * response.progress.percent))
                }
            }
            .frame(height: 8)

            HStack {
                Text(progressText)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.75))

                Spacer(minLength: 4)

                Text("\(Int((response.progress.percent * 100).rounded()))%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(gradientColors[0])
            }
        }
    }

    /// Where you sit among friends, plus the "why this number" line. Both are
    /// the parts that make a personal target feel fair rather than arbitrary.
    @ViewBuilder
    private var footer: some View {
        let others = response.friends.filter { !$0.is_me }
        if !others.isEmpty {
            Divider().overlay(Color.white.opacity(0.08))

            HStack(spacing: 10) {
                HStack(spacing: -8) {
                    ForEach(response.friends.prefix(4)) { entry in
                        AvatarView(
                            name: entry.displayName,
                            imageURL: entry.profile_image_url,
                            size: 26
                        )
                        .overlay(Circle().strokeBorder(MADTheme.Colors.madBlack, lineWidth: 2))
                    }
                }

                if let rank = response.my_rank {
                    Text("You're \(ActiveCompetitionRow.ordinal(rank)) of \(response.friends.count)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
            }
        } else if let baseline = response.baseline, baseline > 0 {
            Text("Sized to your last 4 weeks — you've been averaging \(WeeklyChallengeFormat.valueWithUnit(baseline, unit: response.challenge.unit)).")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
