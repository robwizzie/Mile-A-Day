//
//  ShareCardsView.swift
//  Mile A Day
//

import SwiftUI

// MARK: - The dashboard's share entry
//
// Tapping either dashboard hero (or its Share capsule) used to open a separate
// STATS builder — six light/dark sticker cards in their own sheet, with their
// own Instagram button and their own look. That was a second share surface
// answering the same question ("how do I post my streak?") differently from
// the first, and the one people reached most. It is now the Share Studio,
// opened on the DAY: the streak, Flamey, the stats sticker. One surface, one
// set of cards, one Instagram path.
//
// The type and its initialiser survive so the three hero call sites don't
// move; everything it takes is folded into one `MADStoryContent`.

struct EnhancedShareView: View {
    let user: User
    let currentDistance: Double
    let progress: Double
    let isGoalCompleted: Bool
    let fastestPace: TimeInterval
    let mostMiles: Double

    var body: some View {
        ShareStudioView(content: content, initialTemplate: initialTemplate)
            .onAppear { TelemetryService.record(ShareTelemetry.opened) }
    }

    /// The day. Lifetime miles come off `user` — the server's figure, the
    /// one the profile and the medals show (ios.md) — never HealthKit's.
    private var content: MADStoryContent {
        var content = MADStoryContent(
            distanceMiles: currentDistance > 0 ? currentDistance : nil,
            streak: user.streak > 0 ? user.streak : nil,
            totalMiles: user.totalMiles > 0 ? user.totalMiles : nil,
            date: Date()
        )
        content.goalMet = isGoalCompleted
        return content
    }

    /// A milestone day opens on the milestone; otherwise the flame the user's
    /// own dashboard draws — Flamey on Fun, the streak on Modern.
    private var initialTemplate: ShareTemplate {
        if ShareMilestone.isMilestone(user.streak) { return .streakMilestone }
        return DashboardStylePreference.current == .fun ? .flameyMile : .streakFlame
    }
}

// MARK: - Activity View Controller

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
