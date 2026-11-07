import SwiftUI

/// Tuck Flamey in: the hinge is his bedtime story. Unfolding the first time
/// each day wakes him with a stretch; closing the phone once the day's mile
/// is done tucks him in. Each plays at most once a day, and never mid-workout.
struct DuoFlameyMomentsHost: View {
    enum Moment: Identifiable {
        case stretch, tuck
        var id: Self { self }
    }

    let dayDone: Bool
    let isTracking: Bool

    @AppStorage("duoFlameyStretchDayV1") private var stretchDay = ""
    @AppStorage("duoFlameyTuckDayV1") private var tuckDay = ""
    @AppStorage("flameyWokenDayV1") private var flameyWokenDay = ""
    @State private var moment: Moment?

    private var today: String { FlameMoodKind.dayStamp() }

    var body: some View {
        // Always a real view: an empty body gets no lifecycle, so the hinge
        // observer below would never attach.
        Color.clear
            .allowsHitTesting(false)
            .overlay {
                if let moment {
                    DuoFlameyMomentView(moment: moment) { self.moment = nil }
                        .id(moment)
                        .transition(.opacity)
                }
            }
        .animation(.easeInOut(duration: 0.3), value: moment)
        .onDuoHinge(open: unfolded, close: folded)
        .onAppear(perform: previewForScreenshots)
        #if DEBUG
        .duoDemoCover()
        #endif
    }

    private func unfolded() {
        guard !isTracking, !dayDone, stretchDay != today else { return }
        stretchDay = today
        // The same wake a poke gives him, so the dashboard and widget agree.
        flameyWokenDay = today
        WidgetDataStore.save(flameyWokenDay: today)
        moment = .stretch
    }

    private func folded() {
        guard !isTracking, dayDone, tuckDay != today else { return }
        tuckDay = today
        moment = .tuck
    }

    /// `-MADDuoMoment stretch|tuck` holds a moment on screen in test builds.
    private func previewForScreenshots() {
        #if DEBUG
        let value = UserDefaults.standard.string(forKey: "MADDuoMoment")
        if value == "stretch" { moment = .stretch }
        if value == "tuck" { moment = .tuck }
        #endif
    }
}

private struct DuoFlameyMomentView: View {
    let moment: DuoFlameyMomentsHost.Moment
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    private var isTuck: Bool { moment == .tuck }
    private var title: LocalizedStringKey { isTuck ? "Tucked in." : "Morning!" }
    private var subtitle: LocalizedStringKey { isTuck ? "Mile done. See you tomorrow." : "Let's get that mile." }

    var body: some View {
        ZStack {
            (isTuck ? Color(red: 0.05, green: 0.05, blue: 0.13) : MADTheme.Colors.madRed)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                ZStack(alignment: .bottom) {
                    FlameyDressedFigure(
                        look: FlameyFacts.look() ?? .plain,
                        health: .blazing,
                        size: 190,
                        scale: 1,
                        arms: isTuck ? nil : .cheer,
                        mood: isTuck ? .bedtime : .ready
                    )
                    .frame(width: 280, height: 300, alignment: .bottom)
                    .scaleEffect(x: stretchWidth, y: stretchHeight, anchor: .bottom)

                    if isTuck { blanket }
                }

                VStack(spacing: 6) {
                    Text(title)
                        .madFont(size: 34, weight: .heavy, design: .rounded, maxScale: 1.4)
                        .foregroundColor(.white)
                    Text(subtitle)
                        .madFont(size: 17, weight: .semibold, design: .rounded, maxScale: 1.4)
                        .foregroundColor(.white.opacity(0.8))
                }
                .multilineTextAlignment(.center)
            }
            .padding(24)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDone)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .task {
            MADHaptics.success()
            // Next turn, so the first frame draws before the spring starts.
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.5)) { settled = true }
            #if DEBUG
            if UserDefaults.standard.string(forKey: "MADDuoMoment") != nil { return }
            #endif
            try? await Task.sleep(for: .seconds(2.6))
            onDone()
        }
    }

    /// He rises tall and thin, then settles; tucked in, he stays put.
    private var stretchHeight: CGFloat { isTuck ? 1 : (settled ? 1 : 0.8) }
    private var stretchWidth: CGFloat { isTuck ? 1 : (settled ? 1 : 1.16) }

    private var blanket: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(MADTheme.Colors.madRed)
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(0.92))
                    .frame(height: 12)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }
            .frame(width: 250, height: settled ? 52 : 0)
            .accessibilityHidden(true)
    }
}
