import SwiftUI

/// The Well Earned sheet: the scene big, then a plain-English sentence about
/// whose calories and from when, and the three choices — period, source,
/// treat. Picking any persists it, and the card follows.
///
/// Copy is an EQUIVALENCE, never an instruction ("that's the energy in…"),
/// and says it's rough — App Review 1.4.3 forbids encouraging drinking, and a
/// calorie figure is not nutrition advice.
struct CalorieEquivalentsView: View {
    @ObservedObject var healthManager: HealthKitManager
    let model: TreatCounterModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DashboardStylePreference.key) private var dashboardStyleRaw = DashboardStyle.modern.rawValue

    private var isFun: Bool { DashboardStyle(rawValue: dashboardStyleRaw) == .fun }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: MADTheme.Spacing.lg) {
                        scene
                        headline
                        periodChips
                        treatPicker
                        sourceNote
                        Text("Rough estimates, just for fun — not nutrition advice.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.35))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(MADTheme.Spacing.lg)
                    .padding(.bottom, MADTheme.Spacing.xl)
                }
            }
            .navigationTitle(CalorieTreat.featureName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { model.refresh(healthManager) }
    }

    // MARK: Sections

    @ViewBuilder
    private var scene: some View {
        if isFun {
            TreatFlameBuddyView(size: 150, treat: model.treat, count: model.count)
                .id(model.sceneKey)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.25), value: model.sceneKey)
        } else {
            TreatGlyphShelf(treat: model.treat, count: model.count, size: 34)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(MADTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
        }
    }

    private var headline: some View {
        VStack(spacing: 6) {
            Text(TreatFormat.count(model.count))
                .font(.system(size: 48, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .contentTransition(.numericText())
            Text(model.treat.unitName(count: model.count))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
            Text(story)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .animation(.snappy, value: model.count)
    }

    /// The one sentence that makes the mechanic unmistakable: whose calories,
    /// from when, and what they're worth.
    private var story: String {
        if model.isEmpty {
            let waiting = isFun ? " Flamey's waiting." : ""
            return "Nothing earned yet \(model.period.caption). \(model.treat.perMileHint)\(waiting)"
        }
        let enjoying = isFun ? " Flamey's enjoying them for you." : ""
        return "Your walks & runs burned ≈ \(TreatFormat.kcal(model.kcal)) kcal \(model.period.caption) — the energy in \(TreatFormat.count(model.count)) \(model.treat.unitName(count: model.count)).\(enjoying)"
    }

    private var periodChips: some View {
        HStack(spacing: 8) {
            ForEach(TreatPeriod.allCases) { period in
                chip(period.title, selected: model.period == period) {
                    model.select(period)
                    model.refresh(healthManager)
                }
            }
        }
    }

    /// Exactly what is counted and where it comes from, because "calories
    /// burned" means the Watch ring to most people and the mile to this app.
    private var sourceNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.pink)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text("Where this comes from")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                Text(CalorieLedger.sourceSentence)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var treatPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Count it in")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .padding(.leading, 4)
            // A 3 × 2 grid, not a horizontal scroll: six chips at 66pt never
            // fit a phone width, and a row that LOOKS complete hid the latte.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(CalorieTreat.allCases) { treat in
                    let selected = model.treat == treat
                    Button {
                        guard !selected else { return }
                        MADHaptics.tap()
                        withAnimation(.easeInOut(duration: 0.2)) { model.select(treat) }
                    } label: {
                        VStack(spacing: 6) {
                            TreatGlyph(treat: treat, size: 30)
                            Text(treat.title)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(selected ? .white : .white.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(selected ? 0.12 : 0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    selected ? MADTheme.Colors.madRed : Color.clear,
                                    lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            guard !selected else { return }
            MADHaptics.tap()
            withAnimation(.easeInOut(duration: 0.15)) { action() }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(selected ? .white : .white.opacity(0.55))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(selected
                    ? MADTheme.Colors.madRed.opacity(0.85)
                    : Color.white.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }
}
