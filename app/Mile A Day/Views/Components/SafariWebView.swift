import SwiftUI
import SafariServices

/// Lightweight UIViewControllerRepresentable wrapper around SFSafariViewController.
/// Used for in-app presentation of legal documents (Privacy Policy, Terms of Service).
struct SafariWebView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: config)
        controller.preferredControlTintColor = UIColor(MADTheme.Colors.madRed)
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
