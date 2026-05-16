import Foundation
import SwiftUI

/// Shared deterministic daily-challenge selection + progress evaluation.
///
/// Used by both `DailyChallengeCard` (on the dashboard) and `DailyChallengesView`
/// (detail screen) so they always agree on "today's challenge".
enum DailyChallengeCatalog {
    /// Local mirror of the backend `daily_challenges` catalog. The backend is the source of truth
    /// (returns per-user description + dynamic `cross_train` variant); this pool is the offline
    /// fallback when `RemoteChallengeService` can't reach the server.
    static func pool(avgPace: Double) -> [DailyChallenge] {
        [
            DailyChallenge(
                key: "beat_your_pace",
                title: "Beat Your Pace",
                description: avgPace > 0
                    ? "Run faster than \(formatPace(avgPace + 0.5)) min/mi today"
                    : "Set a new personal best pace today",
                icon: "bolt.fill",
                gradient: [.orange, .red],
                type: .pace
            ),
            DailyChallenge(
                key: "double_down",
                title: "Double Down",
                description: "Run 2+ miles today instead of just 1",
                icon: "2.circle.fill",
                gradient: [.purple, .blue],
                type: .distance
            ),
            DailyChallenge(
                key: "early_or_late",
                title: "Early Bird or Night Owl",
                description: "Finish a mile before 9 AM or after 8 PM",
                icon: "moon.stars.fill",
                gradient: [.yellow, .indigo],
                type: .time
            ),
            DailyChallenge(
                key: "cross_train",
                title: "Mix It Up",
                description: "Log both a walk and a run today (at least 0.5 mi each)",
                icon: "figure.mixed.cardio",
                gradient: [.green, .cyan],
                type: .activity
            ),
            DailyChallenge(
                key: "speed_round",
                title: "Speed Round",
                description: "Finish your mile in under 12 minutes",
                icon: "timer",
                gradient: [.red, .pink],
                type: .pace
            ),
            DailyChallenge(
                key: "bonus_mile",
                title: "Bonus Mile",
                description: "Run an extra half mile beyond your goal",
                icon: "plus.circle.fill",
                gradient: [.cyan, .blue],
                type: .distance
            ),
            DailyChallenge(
                key: "ten_k_steps",
                title: "10K Steps",
                description: "Hit 10,000 steps alongside your mile",
                icon: "shoeprints.fill",
                gradient: [.mint, .green],
                type: .steps
            ),
        ]
    }

    /// Returns today's challenge, cycled by day-of-year.
    static func todays(for user: User) -> DailyChallenge? {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let challenges = pool(avgPace: user.fastestMilePace)
        guard !challenges.isEmpty else { return nil }
        return challenges[dayOfYear % challenges.count]
    }

    struct Context {
        let distance: Double               // today's total distance (miles)
        let steps: Int                     // today's step count
        let goalMiles: Double              // user's daily goal (miles)
        let lastCompletion: Date?          // when the user last completed their goal mile
        let todaysFastestPace: TimeInterval? // today's best single-workout pace, min/mi
        let userFastestMilePace: TimeInterval // lifetime fastest mile pace, min/mi (0 if none)
        let todaysWalkingDistance: Double  // miles from today's walking workouts only
    }

    /// 0...1 progress against the given challenge. Completion = 1.0.
    /// Partial values are only for display; callers check `>= 1.0` for completion.
    static func progress(for challenge: DailyChallenge, ctx: Context) -> Double {
        switch challenge.key {
        case "beat_your_pace":
            return beatYourPaceProgress(ctx: ctx)
        case "speed_round":
            return speedRoundProgress(ctx: ctx)
        case "walk_it_out":
            return walkItOutProgress(ctx: ctx)
        case "cross_train":
            // Offline fallback only — server returns the authoritative variant + progress.
            // Locally we just show "log a walk and a run" progress as a sensible default.
            let walkP = min(ctx.todaysWalkingDistance / 0.5, 1.0)
            let runP = min(max(ctx.distance - ctx.todaysWalkingDistance, 0) / 0.5, 1.0)
            return min((walkP + runP) / 2.0, 1.0)
        case "double_down":
            return min(ctx.distance / 2.0, 1.0)
        case "bonus_mile":
            return min(ctx.distance / (ctx.goalMiles + 0.5), 1.0)
        case "ten_k_steps":
            return min(Double(ctx.steps) / 10000.0, 1.0)
        case "early_bird":
            return earlyBirdProgress(ctx: ctx)
        case "early_or_late":
            return earlyOrLateProgress(ctx: ctx)
        default:
            return 0
        }
    }

    private static func beatYourPaceProgress(ctx: Context) -> Double {
        // Target = user's existing fastest + 0.5 min/mi. If no prior PR, any qualifying mile counts.
        guard let todaysPace = ctx.todaysFastestPace else { return 0 }
        if ctx.userFastestMilePace <= 0 {
            return ctx.distance >= ctx.goalMiles * 0.95 ? 1.0 : 0
        }
        let target = ctx.userFastestMilePace + 0.5
        if todaysPace <= target { return 1.0 }
        // Partial: how close today's pace is to target. Clamp to < 1.0 so we don't falsely "complete".
        return min(target / todaysPace, 0.99)
    }

    private static func speedRoundProgress(ctx: Context) -> Double {
        // Finish a mile in under 12 min.
        guard ctx.distance >= 1.0, let todaysPace = ctx.todaysFastestPace else { return 0 }
        if todaysPace <= 12.0 { return 1.0 }
        return min(12.0 / todaysPace, 0.99)
    }

    private static func walkItOutProgress(ctx: Context) -> Double {
        // Walked the goal distance today via walking-type workouts.
        guard ctx.goalMiles > 0 else { return 0 }
        let needed = ctx.goalMiles * 0.95
        if ctx.todaysWalkingDistance >= needed { return 1.0 }
        return min(ctx.todaysWalkingDistance / ctx.goalMiles, 0.99)
    }

    private static func earlyBirdProgress(ctx: Context) -> Double {
        // Goal mile must be completed today before noon local time.
        guard let last = ctx.lastCompletion, Calendar.current.isDateInToday(last) else {
            // Not completed yet — show partial progress if distance is piling up.
            return ctx.distance >= ctx.goalMiles * 0.95 ? 0.75 : min(ctx.distance / max(ctx.goalMiles, 0.01), 0.5)
        }
        let hour = Calendar.current.component(.hour, from: last)
        return hour < 12 ? 1.0 : 0.75 // goal finished but too late — won't complete
    }

    private static func earlyOrLateProgress(ctx: Context) -> Double {
        // Mile must finish before 9 AM OR at/after 8 PM local time.
        guard let last = ctx.lastCompletion, Calendar.current.isDateInToday(last) else {
            return ctx.distance >= ctx.goalMiles * 0.95 ? 0.75 : min(ctx.distance / max(ctx.goalMiles, 0.01), 0.5)
        }
        let hour = Calendar.current.component(.hour, from: last)
        return (hour < 9 || hour >= 20) ? 1.0 : 0.75
    }

    static func formatPace(_ pace: TimeInterval) -> String {
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}
