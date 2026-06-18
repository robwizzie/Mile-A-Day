import SwiftUI
import CoreImage.CIFilterBuiltins

/// Share-your-profile screen: a scannable QR code plus a share-sheet link to
/// mileaday.run/u/<username>. The link is a universal link, so anyone with
/// the app installed lands directly on this user's profile with an
/// Add Friend button; everyone else gets the web profile + App Store CTA.
struct ShareProfileView: View {
    @StateObject private var userManager = UserManager.shared
    @State private var qrImage: UIImage?

    private var username: String? {
        guard let name = userManager.currentUser.username?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !name.isEmpty
        else { return nil }
        return name
    }

    /// Encoded in the QR code. A custom-scheme link so it resolves entirely
    /// in-app when a friend scans it with the in-app scanner — no domain,
    /// no universal-link dependency.
    private var inAppProfileURL: URL? {
        guard let username else { return nil }
        return URL(string: "mileaday://u/\(username)")
    }

    /// Shared via the share sheet (text/Messages). A web link so people who
    /// don't have the app yet land on a profile page + App Store CTA.
    private var profileURL: URL? {
        guard let username else { return nil }
        return URL(string: "https://mileaday.run/u/\(username)")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: MADTheme.Spacing.xl) {
                if let username, let url = profileURL {
                    shareContent(username: username, url: url)
                } else {
                    noUsernameView
                }
            }
            .frame(maxWidth: .infinity)
            .padding(MADTheme.Spacing.lg)
            .padding(.top, MADTheme.Spacing.md)
        }
        .background(MADTheme.Colors.appBackgroundGradient.ignoresSafeArea())
        .navigationTitle("Share Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let url = inAppProfileURL {
                qrImage = Self.generateQRCode(from: url.absoluteString)
            }
        }
    }

    // MARK: - Share Content

    @ViewBuilder
    private func shareContent(username: String, url: URL) -> some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            AvatarView(
                name: userManager.currentUser.name,
                imageURL: userManager.currentUser.profileImageUrl,
                size: 72
            )
            .overlay(
                Circle()
                    .stroke(MADTheme.Colors.madRed.opacity(0.4), lineWidth: 2)
            )

            Text("@\(username)")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
        }

        // QR card — black-on-white for maximum scanner contrast against
        // the app's dark theme.
        VStack(spacing: MADTheme.Spacing.md) {
            if let qrImage {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
            } else {
                ProgressView()
                    .frame(width: 220, height: 220)
            }
        }
        .padding(MADTheme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                .fill(Color.white)
        )

        VStack(spacing: MADTheme.Spacing.xs) {
            Text("Have a friend scan this in Mile A Day → Find Friends → Scan")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))

            Text(url.absoluteString)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(MADTheme.Colors.madRed)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .multilineTextAlignment(.center)

        ShareLink(
            item: url,
            message: Text("Add me on Mile A Day and let's keep our streaks going!")
        ) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                Text("Share Profile")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(MADTheme.Colors.madRed)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - No Username Fallback

    private var noUsernameView: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 48))
                .foregroundColor(MADTheme.Colors.secondaryText)

            Text("Set a Username First")
                .font(MADTheme.Typography.title3)
                .foregroundColor(MADTheme.Colors.primaryText)

            Text("Your share link uses your username. Add one from Profile → Edit Profile, then come back here.")
                .font(MADTheme.Typography.body)
                .foregroundColor(MADTheme.Colors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, MADTheme.Spacing.xxl)
    }

    // MARK: - QR Generation

    /// CoreImage QR generation — no third-party dependency. Scaled up with
    /// nearest-neighbor (interpolation(.none) on the Image) so modules stay
    /// crisp.
    static func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Preview
struct ShareProfileView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ShareProfileView()
        }
    }
}
