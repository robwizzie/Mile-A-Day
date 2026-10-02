import SwiftUI

/// Every way to start a competition, behind ONE button on the Compete tab once
/// the user already has competitions. Presets lead (the two-tap path), then the
/// five modes (each opens its explainer), then the blank form.
///
/// The sheet never presents anything itself: it reports a `Choice` and
/// dismisses, and the host acts in `onDismiss` — the shell's explainer/create
/// sheets can't come up while this one is still on screen.
struct StartCompetitionSheet: View {
    enum Choice {
        case preset(CompetitionPreset)
        case mode(CompetitionType)
        case blank
    }

    let onChoose: (Choice) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        CompeteHeader(eyebrow: "Quick start")
                        ForEach(CompetitionPreset.all) { preset in
                            PresetCard(preset: preset) { choose(.preset(preset)) }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        CompeteHeader(eyebrow: "How modes work")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(CompetitionType.allCases, id: \.self) { type in
                                    ModeGalleryCard(type: type) { choose(.mode(type)) }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                        .padding(.horizontal, -16)
                    }

                    Button { choose(.blank) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 12, weight: .bold))
                            Text("Build a custom competition")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(MADTheme.Colors.madRed)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Start a competition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }

    private func choose(_ choice: Choice) {
        onChoose(choice)
        dismiss()
    }
}
