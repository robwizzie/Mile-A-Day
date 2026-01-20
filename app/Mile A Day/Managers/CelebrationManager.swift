//
//  CelebrationManager.swift
//  Mile A Day
//
//  Created by Claude on 1/9/26.
//

import Foundation
import SwiftUI

/// Types of celebrations that can be shown
enum CelebrationType: Identifiable, Equatable {
    case goalCompleted
    case badgeUnlocked(badge: Badge)
    case milestone(title: String, description: String, icon: String)

    var id: String {
        switch self {
        case .goalCompleted:
            return "goal-completed"
        case .badgeUnlocked(let badge):
            return "badge-\(badge.id)"
        case .milestone(let title, _, _):
            return "milestone-\(title)"
        }
    }

    static func == (lhs: CelebrationType, rhs: CelebrationType) -> Bool {
        lhs.id == rhs.id
    }
}

/// Manages queuing and displaying celebration screens
class CelebrationManager: ObservableObject {
    static let shared = CelebrationManager()

    @Published private(set) var celebrationQueue: [CelebrationType] = []
    @Published var currentCelebration: CelebrationType?
    @Published var isShowingCelebration = false

    private init() {}

    /// Add a celebration to the queue
    func addCelebration(_ celebration: CelebrationType) {
        // Avoid duplicates
        guard !celebrationQueue.contains(where: { $0.id == celebration.id }) else { return }
        guard currentCelebration?.id != celebration.id else { return }

        celebrationQueue.append(celebration)

        // If nothing is currently showing, show the next one
        if !isShowingCelebration {
            showNextCelebration()
        }
    }

    /// Dismiss the current celebration and show the next one if available
    func dismissCurrentCelebration() {
        isShowingCelebration = false
        currentCelebration = nil

        // Small delay before showing next celebration for better UX
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showNextCelebration()
        }
    }

    /// Show the next celebration in the queue
    private func showNextCelebration() {
        guard !celebrationQueue.isEmpty else { return }

        currentCelebration = celebrationQueue.removeFirst()
        isShowingCelebration = true
    }

    /// Clear all celebrations (useful for testing or reset)
    func clearAll() {
        celebrationQueue.removeAll()
        currentCelebration = nil
        isShowingCelebration = false
    }
}
