//
//  ReviewPromptManager.swift
//  Mile A Day
//

import SwiftUI

/// Decides when to ask the SYSTEM for a review (`requestReview`) and records
/// which streak milestones we've already asked at.
///
/// App Review 5.6.1: ratings go through Apple's own prompt only. There is no
/// custom "Rate us" sheet and no deep link from an unprompted moment; the
/// system decides whether the prompt actually shows (it rate-limits itself).
///
/// Rules (per product):
/// - Milestones are 3, 7, and 30 day streaks.
/// - Each milestone fires **at most once, ever** — if the streak breaks and
///   re-climbs past a milestone we've already asked at, we do NOT re-ask.
/// - It's **retroactive**: an existing user whose streak is already past a
///   milestone (with nothing recorded yet) is asked the next time the app is
///   open and calm — once, not once per milestone.
/// - Never in the first launch on this install (sign-in, Health, paywall and
///   token reveals already compete for that session), never in a launch's
///   first 20 seconds, and at most once per launch.
final class ReviewPromptManager: ObservableObject {
    static let shared = ReviewPromptManager()

    /// App Store listing, deep-linked straight to the write-a-review composer.
    /// Only for an explicit user action (e.g. a "Rate the app" row), never for
    /// an unprompted ask.
    static let writeReviewURL = URL(string: "https://apps.apple.com/app/id6746970905?action=write-review")

    /// Streak thresholds that trigger the review moment, ascending.
    private let milestones = [3, 7, 30]

    /// Comma-separated list of milestones already prompted at. Persisted so the
    /// "once ever" guarantee survives relaunches.
    @AppStorage("reviewPromptedMilestones") private var promptedMilestonesRaw: String = ""

    /// Process launches on this install, counted when the manager is first
    /// touched (once per launch). The first launch never asks.
    private static let launchCountKey = "reviewPromptLaunchCountV1"

    /// Bumped when the system review prompt should be requested. `MainTabView`
    /// observes it and calls SwiftUI's `requestReview` action.
    @Published private(set) var requestNonce = 0

    private var askedThisLaunch = false
    private let launchCount: Int
    /// Never at launch: system permission sheets (Health, notifications) and
    /// the splash own the first moments. An early check is just skipped; the
    /// next foreground or streak change re-evaluates.
    private let launchedAt = Date()
    private static let settleDelay: TimeInterval = 20

    private init() {
        let count = UserDefaults.standard.integer(forKey: Self.launchCountKey) + 1
        UserDefaults.standard.set(count, forKey: Self.launchCountKey)
        launchCount = count
    }

    private var promptedMilestones: Set<Int> {
        get { Set(promptedMilestonesRaw.split(separator: ",").compactMap { Int($0) }) }
        set { promptedMilestonesRaw = newValue.sorted().map(String.init).joined(separator: ",") }
    }

    /// Evaluate eligibility for the current streak and request the system
    /// prompt if the user qualifies. `allowPresent` lets the caller suppress the
    /// ask when the screen is busy without losing the eligibility — it'll fire
    /// on the next calm check. Call on the main thread.
    func evaluate(streak: Int, allowPresent: Bool) {
        guard allowPresent, !askedThisLaunch, launchCount >= 2,
              Date().timeIntervalSince(launchedAt) >= Self.settleDelay else { return }

        let unprompted = milestones.filter { streak >= $0 && !promptedMilestones.contains($0) }
        guard !unprompted.isEmpty else { return }

        // Mark every milestone the user has ALREADY reached as prompted. This is
        // what makes an existing user (already past all thresholds) get asked
        // exactly once, while a brand-new user is asked once per newly-crossed
        // band as their streak grows.
        var updated = promptedMilestones
        for m in milestones where streak >= m { updated.insert(m) }
        promptedMilestones = updated

        askedThisLaunch = true
        requestNonce += 1
    }

    #if DEBUG
    /// Clears the recorded milestones (and the first-launch hold) so the
    /// prompt can be re-tested.
    func resetForTesting() {
        promptedMilestonesRaw = ""
        askedThisLaunch = false
        UserDefaults.standard.set(1, forKey: Self.launchCountKey)
    }
    #endif
}
