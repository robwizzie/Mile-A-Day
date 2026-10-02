//
//  CelebrationContainerView.swift
//  Mile A Day
//

import SwiftUI

struct CelebrationContainerView: View {
    @ObservedObject var manager = CelebrationManager.shared
    /// The root overlay (MainTabView) is the one host. A DETACHED host is a
    /// cover raised by a screen that may itself sit inside a sheet (a medal's
    /// "Replay celebration"), where the root overlay would play underneath it
    /// — while one is up, the root draws nothing so nothing plays twice.
    var isDetached = false

    private var isActiveHost: Bool {
        isDetached || manager.detachedHostCount == 0
    }

    var body: some View {
        Group {
            if isActiveHost, manager.isShowingCelebration, let celebration = manager.currentCelebration {
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
            if DashboardStylePreference.current == .fun {
                FunGoalCompletedCelebrationView(stats: stats)
            } else {
                ModernGoalCompletedCelebrationView(stats: stats)
            }

        case .leaderboardMoveUp(let stats):
            LeaderboardMoveUpView(stats: stats)

        case .postGoalWorkout(let stats):
            PostGoalEncouragementView(stats: stats)

        case .badgeUnlocked(let badge):
            BadgeUnlockCelebrationView(badge: badge)

        case .milestone(let title, let description, let icon):
            MilestoneCelebrationView(
                title: title,
                description: description,
                icon: icon
            )

        case .yearMilestone(let info):
            YearlyMilestoneCelebrationView(info: info)

        case .streakMilestone(let info):
            StreakMilestoneCelebrationView(info: info)

        case .badgeSummary(let count, let badges):
            BadgeSummaryCelebrationView(count: count, badges: badges)

        case .badgeBatch(let badges, let retroactive):
            BadgeSummaryCelebrationView(
                count: badges.count,
                badges: badges,
                mode: retroactive ? .retroactive : .burst
            )

        case .challengeCompleted(let info):
            ChallengeCompletedCelebrationView(info: info)

        case .postRunPhotoPrompt(let workoutId, let workoutType):
            PostRunPhotoPromptView(workoutId: workoutId, workoutType: workoutType)

        case .comeback(let day, let priorLength, let recordLength, let eraNumber, _):
            ComebackCelebrationView(
                day: day,
                priorLength: priorLength,
                recordLength: recordLength,
                eraNumber: eraNumber
            )

        case .newRecordStreak(let days, let previousBest, _):
            RecordStreakCelebrationView(days: days, previousBest: previousBest)

        case .ghostBeaten(let win):
            GhostBeatenCelebrationView(win: win)

        case .flameyUnlocked(let itemIds):
            FlameyUnlockCelebrationHost(itemIds: itemIds)
        }
    }
}

/// A full-screen host for replaying ONE celebration from a screen that may be
/// a sheet itself. Registers as the detached host (so the root overlay stands
/// down), starts the replay, and closes once the celebration — and anything
/// replayed after it — has been dismissed.
struct CelebrationReplayHost: View {
    let celebration: CelebrationType
    let onFinished: () -> Void
    @ObservedObject private var manager = CelebrationManager.shared
    @State private var started = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CelebrationContainerView(isDetached: true)
        }
        .onAppear {
            guard !started else { return }
            started = true
            manager.attachDetachedHost()
            manager.replayCelebration(celebration)
        }
        .onDisappear { manager.detachDetachedHost() }
        .onChange(of: manager.isShowingCelebration) { _, showing in
            guard started, !showing else { return }
            // dismissCurrentCelebration shows the next one after a beat; only
            // close once there's nothing left to show.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if !manager.isShowingCelebration { onFinished() }
            }
        }
    }
}

#Preview {
    CelebrationContainerView()
        .onAppear {
            CelebrationManager.shared.addCelebration(.goalCompleted(stats: .placeholder))
        }
}
