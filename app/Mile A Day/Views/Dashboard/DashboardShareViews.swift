import SwiftUI
import UIKit

// The system share sheet, used by every card renderer in the app.
//
// This file also held `StreakCardShareView`, `TodayProgressCardShareView` and
// `SharePreviewView` — an earlier dashboard share flow that lost its last
// caller and was never reachable again. `EnhancedShareView` (the sticker
// builder, opened by tapping either dashboard hero) and `ShareStudioView` (a
// walk, story-shaped) are what the app shares through now, so those are gone
// rather than left sitting here reading as live code.

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
