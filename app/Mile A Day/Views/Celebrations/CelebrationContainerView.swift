//
//  CelebrationContainerView.swift
//  Mile A Day
//

import SwiftUI

struct CelebrationContainerView: View {
    @ObservedObject var manager = CelebrationManager.shared

    var body: some View {
        Group {
            if manager.isShowingCelebration, let celebration = manager.currentCelebration {
                celebrationView(for: celebration)
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .opacity
                    ))
                    .zIndex(1000) // Ensure it's always on top
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: manager.isShowingCelebration)
    }

    @ViewBuilder
    private func celebrationView(for celebration: CelebrationType) -> some View {
        switch celebration {
        case .goalCompleted(let stats):
            GoalCompletedCelebrationView(stats: stats)

        case .badgeUnlocked(let badge):
            BadgeUnlockCelebrationView(badge: badge)

        case .milestone(let title, let description, let icon):
            MilestoneCelebrationView(
                title: title,
                description: description,
                icon: icon
            )
        }
    }
}

#Preview {
    CelebrationContainerView()
        .onAppear {
            CelebrationManager.shared.addCelebration(.goalCompleted(stats: .placeholder))
        }
}
