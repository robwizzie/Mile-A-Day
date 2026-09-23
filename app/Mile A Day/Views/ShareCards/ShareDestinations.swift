import SwiftUI
import UIKit
import Photos
import MessageUI

// MARK: - Where a finished card can go
//
// The Share Studio's destination row, Strava-style: one big "Instagram
// Stories" button, then round buttons for the other places people actually
// send a walk. Each one is a real, direct action — a door to the share sheet
// dressed up as five doors is what the old two-button layout was avoiding,
// so only destinations that do something the sheet can't do in fewer taps get
// a button, and "More" is the sheet itself.

enum ShareDestination: String, Identifiable {
    case instagramFeed, messages, save, copyLink, more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .instagramFeed: return "Instagram"
        case .messages: return "Messages"
        case .save: return "Save"
        case .copyLink: return "Copy link"
        case .more: return "More"
        }
    }

    var icon: String {
        switch self {
        case .instagramFeed: return "camera"
        case .messages: return "message.fill"
        case .save: return "square.and.arrow.down"
        case .copyLink: return "link"
        case .more: return "ellipsis"
        }
    }
}

/// Saving to the camera roll with ADD-ONLY access — the app never reads the
/// library to do this, so it asks for the narrowest permission there is
/// (`NSPhotoLibraryAddUsageDescription`).
enum SharePhotoSaver {
    enum Outcome { case saved, denied, failed }

    /// PNG data, so a sticker keeps its transparent edge in the roll.
    static func save(_ image: UIImage) async -> Outcome {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return .denied }
        guard let data = image.pngData() else { return .failed }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }
            return .saved
        } catch {
            print("[ShareStudio] save failed: \(error.localizedDescription)")
            return .failed
        }
    }
}

/// The Messages composer with the card attached (and the link, when the walk
/// has one — a friend in a thread can open a link, not a picture).
struct MessageComposeSheet: UIViewControllerRepresentable {
    let image: UIImage
    var link: URL?
    let onFinish: () -> Void

    static var canSend: Bool {
        MFMessageComposeViewController.canSendText()
            && MFMessageComposeViewController.canSendAttachments()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        if let data = image.pngData() {
            controller.addAttachmentData(data, typeIdentifier: "public.png", filename: "mile-a-day.png")
        }
        if let link { controller.body = link.absoluteString }
        return controller
    }

    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true)
            onFinish()
        }
    }
}

/// `.sheet(item:)` for the Messages composer.
struct ShareMessageItem: Identifiable {
    let id = UUID()
    let image: UIImage
}
