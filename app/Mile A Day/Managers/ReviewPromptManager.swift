//
//  ReviewPromptManager.swift
//  Mile A Day
//

import SwiftUI

/// Decides when to show the "Enjoying Mile A Day?" review moment and records
/// which streak milestones we've already asked at.
///
/// Rules (per product):
/// - Milestones are 3, 7, and 30 day streaks.
/// - Each milestone fires **at most once, ever** — if the streak breaks and
///   re-climbs past a milestone we've already asked at, we do NOT re-ask.
/// - It's **retroactive**: an existing user whose streak is already past a
///   milestone (with nothing recorded yet) is asked the next time the app is
///   open and calm — they're shown the prompt once, not once per milestone.
///
/// The prompt itself is never shown during onboarding — this manager is only
/// consulted from the main app once the user is on the dashboard.
final class ReviewPromptManager: ObservableObject {
    static let shared = ReviewPromptManager()

    /// Streak thresholds that trigger the review moment, ascending.
    private let milestones = [3, 7, 30]

    /// Comma-separated list of milestones already prompted at. Persisted so the
    /// "once ever" guarantee survives relaunches.
    @AppStorage("reviewPromptedMilestones") private var promptedMilestonesRaw: String = ""

    /// Drives the review sheet in `MainTabView`.
    @Published var isPresented = false

    /// Set true when the user taps the positive CTA, so the presenter knows to
    /// fire the native StoreKit review request once the sheet has dismissed.
    @Published var pendingRateRequest = false

    /// The milestone the current prompt is celebrating (drives the copy).
    private(set) var triggeredMilestone: Int = 3

    private init() {}

    private var promptedMilestones: Set<Int> {
        get { Set(promptedMilestonesRaw.split(separator: ",").compactMap { Int($0) }) }
        set { promptedMilestonesRaw = newValue.sorted().map(String.init).joined(separator: ",") }
    }

    /// Evaluate eligibility for the current streak and present the prompt if the
    /// user qualifies. `allowPresent` lets the caller suppress the ask when the
    /// screen is busy (e.g. a celebration is on-screen) without losing the
    /// eligibility — it'll fire on the next calm check. Call on the main thread.
    func evaluate(streak: Int, allowPresent: Bool) {
        guard allowPresent, !isPresented else { return }

        let unprompted = milestones.filter { streak >= $0 && !promptedMilestones.contains($0) }
        guard let highest = unprompted.max() else { return }

        triggeredMilestone = highest

        // Mark every milestone the user has ALREADY reached as prompted. This is
        // what makes an existing user (already past all thresholds) get asked
        // exactly once, while a brand-new user is asked once per newly-crossed
        // band as their streak grows.
        var updated = promptedMilestones
        for m in milestones where streak >= m { updated.insert(m) }
        promptedMilestones = updated

        pendingRateRequest = false
        isPresented = true
    }

    /// User tapped the positive CTA — dismiss and let the presenter fire the
    /// native review request on a clean screen.
    func userTappedRate() {
        pendingRateRequest = true
        isPresented = false
    }

    /// User dismissed without rating.
    func userTappedLater() {
        pendingRateRequest = false
        isPresented = false
    }

    /// Fun, milestone-specific headline for the current prompt.
    var headline: String {
        switch triggeredMilestone {
        case 30: return "30 days. You're built different. 🏆"
        case 7: return "A full week of miles! 🔥"
        default: return "3 days strong — you're on a roll! 🔥"
        }
    }

    #if DEBUG
    /// Clears the recorded milestones so the prompt can be re-tested.
    func resetForTesting() {
        promptedMilestonesRaw = ""
        isPresented = false
        pendingRateRequest = false
    }
    #endif
}
