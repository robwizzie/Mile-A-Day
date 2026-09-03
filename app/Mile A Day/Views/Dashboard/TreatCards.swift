import SwiftUI

/// ONE card for every surface that hosts Well Earned (the opt-in dashboard
/// slot, Insights): the Fun face or the Modern face, following the dashboard
/// style, so Insights matches whichever dashboard the user chose.
struct TreatsCard: View {
    @ObservedObject var healthManager: HealthKitManager
    @AppStorage(DashboardStylePreference.key) private var dashboardStyleRaw = DashboardStyle.modern.rawValue

    var body: some View {
        if DashboardStyle(rawValue: dashboardStyleRaw) == .fun {
            TreatSceneCard(healthManager: healthManager)
        } else {
            ModernTreatsCard(healthManager: healthManager)
        }
    }
}

/// The Fun face: Flamey enjoying what the miles earned on the right, the
/// number on the left, one caption that says whose calories and from when.
struct TreatSceneCard: View {
    @ObservedObject var healthManager: HealthKitManager
    @State private var model = TreatCounterModel()
    @State private var showDetail = false

    var body: some View {
        Button {
            MADHaptics.tap()
            showDetail = true
        } label: {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Text(CalorieTreat.featureName)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.72))
                    Spacer()
                    Text(model.period.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                }

                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(TreatFormat.count(model.count))
                            .font(.system(size: 40, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white)
                            .contentTransition(.numericText())
                        Text(model.treat.unitName(count: model.count))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(TreatCopy.caption(model))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    // `.id(sceneKey)`: a new treat, or a flip between "nothing
                    // yet" and "something", is a new set of motions — rebuild
                    // rather than re-drive (see TreatFlameBuddyView).
                    TreatFlameBuddyView(size: 88, treat: model.treat, count: model.count)
                        .id(model.sceneKey)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass()
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: model.count)
        .animation(.easeInOut(duration: 0.25), value: model.sceneKey)
        .treatRefresh(model: model, healthManager: healthManager)
        .sheet(isPresented: $showDetail) {
            CalorieEquivalentsView(healthManager: healthManager, model: model)
        }
    }
}

/// The Modern face: the number, the same caption, and a shelf of glyphs —
/// one per unit earned, the last one only as full as the fraction.
struct ModernTreatsCard: View {
    @ObservedObject var healthManager: HealthKitManager
    @State private var model = TreatCounterModel()
    @State private var showDetail = false

    var body: some View {
        Button {
            MADHaptics.tap()
            showDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.pink)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.pink.opacity(0.15)))
                    Spacer()
                    Text(model.period.title)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.48))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.28))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(CalorieTreat.featureName)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.48))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(TreatFormat.count(model.count))
                            .font(.system(size: 23, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white)
                            .contentTransition(.numericText())
                        Text(model.treat.unitName(count: model.count))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Text(TreatCopy.caption(model))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(model.isEmpty ? .white.opacity(0.5) : .pink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                TreatGlyphShelf(treat: model.treat, count: model.count, size: 22)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            // ModernTile's surface, restated: it's private to DashboardModeCards.
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.075, green: 0.075, blue: 0.085))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: model.count)
        .treatRefresh(model: model, healthManager: healthManager)
        .sheet(isPresented: $showDetail) {
            CalorieEquivalentsView(healthManager: healthManager, model: model)
        }
    }
}

/// One glyph per unit earned, the last one partially filled to the fraction,
/// capped at a dozen with a "+N". An empty day shows one empty glyph so the
/// shelf never reads as broken.
struct TreatGlyphShelf: View {
    let treat: CalorieTreat
    let count: Double
    var size: CGFloat = 22

    private static let cap = 12

    var body: some View {
        let whole = Int(max(0, count).rounded(.down))
        let fraction = max(0, count) - Double(whole)
        let shown = min(whole, Self.cap)
        let overflow = whole - shown
        let showsPartial = fraction >= 0.05 && overflow == 0
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: size, maximum: size), spacing: 6)],
            alignment: .leading, spacing: 6
        ) {
            ForEach(0..<shown, id: \.self) { _ in
                TreatGlyph(treat: treat, size: size, fill: 1)
            }
            if showsPartial {
                TreatGlyph(treat: treat, size: size, fill: fraction)
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: max(9, size * 0.5), weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(height: size)
                    .padding(.horizontal, 6)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
            }
            if whole == 0 && !showsPartial {
                TreatGlyph(treat: treat, size: size, fill: 0)
                    .opacity(0.6)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Shared refresh wiring

private struct TreatRefreshModifier: ViewModifier {
    let model: TreatCounterModel
    @ObservedObject var healthManager: HealthKitManager

    func body(content: Content) -> some View {
        content
            .onAppear { model.refresh(healthManager) }
            .onChange(of: healthManager.cachedWorkouts.count) { _, _ in model.refresh(healthManager) }
            .onChange(of: healthManager.todaysWorkouts.count) { _, _ in model.refresh(healthManager) }
            .onChange(of: healthManager.todaysDistance) { _, _ in model.refresh(healthManager) }
    }
}

extension View {
    /// Recompute whenever the HealthKit caches the tiles already observe
    /// move — the same publishes ModernStepsTile watches.
    func treatRefresh(model: TreatCounterModel, healthManager: HealthKitManager) -> some View {
        modifier(TreatRefreshModifier(model: model, healthManager: healthManager))
    }
}
