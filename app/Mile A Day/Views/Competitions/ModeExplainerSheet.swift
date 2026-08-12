import SwiftUI

/// "What is Clash?" answered in one screen.
///
/// Until now the only place a mode was ever explained was the type-selector
/// push *inside* the create form — i.e. you had to already be creating a
/// competition to find out what the five names meant. This sheet is reachable
/// straight from the tab, and its CTA starts the mode it just described, so
/// learning and starting are the same gesture.
struct ModeExplainerSheet: View {
    let type: CompetitionType
    /// Start a competition in this mode. The host dismisses this sheet first —
    /// two presentations on one node silently drop one.
    let onStart: (CompetitionType) -> Void

    @Environment(\.dismiss) private var dismiss

    private var gradientColors: [Color] {
        type.gradient.map { Color(hex: $0) }
    }

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
                    header
                    steps
                    exampleCard
                    bestForRow
                }
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.top, MADTheme.Spacing.md)
                .padding(.bottom, 120)
            }
        }
        .safeAreaInset(edge: .bottom) { startButton }
        .navigationTitle(type.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .foregroundColor(.white.opacity(0.8))
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: type.icon)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(
                    LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 62, height: 62)
                .background(
                    Circle()
                        .fill(gradientColors[0].opacity(0.14))
                        .overlay(
                            Circle().strokeBorder(
                                LinearGradient(
                                    colors: gradientColors.map { $0.opacity(0.55) },
                                    startPoint: .top, endPoint: .bottom
                                ),
                                lineWidth: 1.5
                            )
                        )
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(type.displayName)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text(type.tagline)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
                    )
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - How it works

    private var steps: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            sectionLabel("HOW IT WORKS")

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(type.howItWorks.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .frame(width: 22, height: 22)
                            .background(
                                Circle().fill(
                                    LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom)
                                )
                            )

                        Text(step)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(MADTheme.Spacing.md)
            .background(cardBackground)
        }
    }

    // MARK: - Worked example

    private var exampleCard: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            sectionLabel("FOR EXAMPLE")

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(gradientColors[0].opacity(0.8))

                Text(type.example)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(MADTheme.Spacing.md)
            .background(cardBackground)
        }
    }

    private var bestForRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(gradientColors[0])

            Text(type.bestFor)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    // MARK: - CTA

    private var startButton: some View {
        Button {
            // Dismiss first: the host presents the create sheet, and two
            // presentations racing on one node drops one of them.
            dismiss()
            onStart(type)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                Text("Start a \(type.displayName) competition")
            }
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                    .fill(
                        LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.bottom, MADTheme.Spacing.md)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - Shared chrome

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .black, design: .rounded))
            .tracking(1.4)
            .foregroundColor(.white.opacity(0.5))
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [gradientColors[0].opacity(0.10), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [gradientColors[0].opacity(0.35), Color.white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
}

#Preview {
    NavigationStack {
        ModeExplainerSheet(type: .clash) { _ in }
    }
}
