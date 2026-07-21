//
//  ReviewPromptView.swift
//  Mile A Day
//
//  The friendly "Enjoying Mile A Day?" moment shown after a streak milestone.
//  Tapping the positive CTA hands off to the native StoreKit review request
//  (handled by the presenter once this sheet dismisses).
//

import SwiftUI

struct ReviewPromptView: View {
    @ObservedObject var manager: ReviewPromptManager

    @State private var starsIn = false
    @State private var contentIn = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.14, green: 0.07, blue: 0.10),
                    Color(red: 0.07, green: 0.04, blue: 0.05)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: MADTheme.Spacing.lg) {
                Spacer(minLength: MADTheme.Spacing.md)

                stars

                VStack(spacing: MADTheme.Spacing.sm) {
                    Text(manager.headline)
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("You keep showing up — that's the whole game. If Mile A Day's helped you keep the streak alive, a quick rating helps other runners find us. 🙏")
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, MADTheme.Spacing.sm)
                }
                .opacity(contentIn ? 1 : 0)
                .offset(y: contentIn ? 0 : 8)

                Spacer(minLength: 0)

                VStack(spacing: MADTheme.Spacing.sm) {
                    Button {
                        MADHaptics.action()
                        manager.userTappedRate()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 15, weight: .bold))
                            Text("Rate Mile A Day")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(MADTheme.Colors.madRed)
                        )
                        .shadow(color: MADTheme.Colors.madRed.opacity(0.4), radius: 14, x: 0, y: 6)
                    }

                    Button {
                        manager.userTappedLater()
                    } label: {
                        Text("Maybe later")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                }
                .opacity(contentIn ? 1 : 0)
            }
            .padding(.horizontal, MADTheme.Spacing.xl)
            .padding(.bottom, MADTheme.Spacing.md)
            .padding(.top, MADTheme.Spacing.lg)
        }
        .presentationDetents([.height(440)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(red: 0.07, green: 0.04, blue: 0.05))
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) { starsIn = true }
            withAnimation(.easeOut(duration: 0.45).delay(0.15)) { contentIn = true }
        }
    }

    private var stars: some View {
        HStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: "star.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.82, blue: 0.30), Color(red: 1.0, green: 0.62, blue: 0.10)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .scaleEffect(starsIn ? 1 : 0.2)
                    .opacity(starsIn ? 1 : 0)
                    .rotationEffect(.degrees(starsIn ? 0 : -35))
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.55).delay(Double(i) * 0.07),
                        value: starsIn
                    )
                    .shadow(color: Color(red: 1.0, green: 0.7, blue: 0.2).opacity(0.5), radius: 8, x: 0, y: 3)
            }
        }
    }
}

#Preview {
    Color.black
        .sheet(isPresented: .constant(true)) {
            ReviewPromptView(manager: .shared)
                .preferredColorScheme(.dark)
        }
}
