import SwiftUI

/// Past weeks: what the challenge was, the target you were set, and whether you
/// got there.
///
/// The target shown is the one that was frozen for you that week, not what the
/// scaling formula would produce today — which is the whole reason it's stored
/// rather than recomputed.
struct WeeklyChallengeHistoryView: View {
    @ObservedObject var service: WeeklyChallengeService
    @Environment(\.dismiss) private var dismiss

    private var completedCount: Int {
        service.history.filter { $0.completed }.count
    }

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

            if service.history.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: MADTheme.Spacing.md) {
                        summary
                        ForEach(service.history) { item in
                            row(item)
                        }
                    }
                    .padding(.horizontal, MADTheme.Spacing.md)
                    .padding(.vertical, MADTheme.Spacing.md)
                }
            }
        }
        .navigationTitle("Weekly History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .task { await service.loadHistory() }
    }

    private var summary: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.green)
            Text("\(completedCount) of \(service.history.count) weeks completed")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.75))
            Spacer(minLength: 0)
        }
    }

    private func row(_ item: WeeklyChallengeHistoryResponse.Item) -> some View {
        let colors = [Color(hex: item.gradient_start), Color(hex: item.gradient_end)]

        return HStack(spacing: 12) {
            Image(systemName: item.completed ? "checkmark.circle.fill" : item.icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(
                    item.completed
                        ? LinearGradient(colors: [.green, .green], startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 38, height: 38)
                .background(
                    Circle().fill(
                        (item.completed ? Color.green : colors[0]).opacity(0.14)
                    )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text("Week of \(WeeklyChallengeFormat.shortDate(item.week_start))")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text(item.completed ? "Done" : "Missed")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(item.completed ? .green : .white.opacity(0.4))

                Text(targetText(item))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
            }
            .fixedSize()
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                        .strokeBorder(
                            item.completed ? Color.green.opacity(0.22) : Color.white.opacity(0.07),
                            lineWidth: 1
                        )
                )
        )
    }

    /// A completed week reports what you actually did; a missed one reports the
    /// target you were chasing.
    private func targetText(_ item: WeeklyChallengeHistoryResponse.Item) -> String {
        if let final = item.final_value, item.completed {
            return WeeklyChallengeFormat.valueWithUnit(final, unit: item.unit)
        }
        return "Goal \(WeeklyChallengeFormat.valueWithUnit(item.target, unit: item.unit))"
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 34, weight: .medium))
                .foregroundColor(MADTheme.Colors.madRed.opacity(0.5))

            Text("No weeks yet")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Your past weekly challenges will show up here.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
