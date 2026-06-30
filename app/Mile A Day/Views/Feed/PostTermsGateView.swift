import SwiftUI

/// One-time community-guidelines / EULA acceptance shown before a user's first
/// post (App Store Guideline 1.2 — zero tolerance for objectionable content and
/// abusive users). On accept it records server-side and invokes onAccepted.
struct PostTermsGateView: View {
    let onAccepted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var submitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(MADTheme.Colors.redGradient)
                            .padding(.top, MADTheme.Spacing.lg)

                        Text("Community Guidelines")
                            .font(MADTheme.Typography.title1)
                            .foregroundColor(.white)

                        Text("Mile A Day has zero tolerance for objectionable content or abusive behavior. By posting, you agree to:")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))

                        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                            rule("photo.fill", "Only share content you have the rights to.")
                            rule("eye.slash.fill", "No nudity, hate, harassment, or violent content.")
                            rule("flag.fill", "We review reports within 24 hours and remove violations.")
                            rule("hand.raised.fill", "You can block or report anyone at any time.")
                        }

                        Text("Posts and stories are visible to your friends. Accounts that violate these guidelines may be removed.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(MADTheme.Colors.error)
                        }
                    }
                    .padding(MADTheme.Spacing.lg)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: MADTheme.Spacing.sm) {
                    Button {
                        Task { await accept() }
                    } label: {
                        if submitting {
                            ProgressView().tint(.white).frame(maxWidth: .infinity)
                        } else {
                            Text("I Agree").frame(maxWidth: .infinity)
                        }
                    }
                    .madPrimaryButton(fullWidth: true)
                    .disabled(submitting)

                    Button("Not now") { dismiss() }
                        .madTertiaryButton()
                }
                .padding(MADTheme.Spacing.md)
                .background(.ultraThinMaterial)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func rule(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(MADTheme.Colors.madRed)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
        }
    }

    private func accept() async {
        submitting = true
        errorMessage = nil
        defer { submitting = false }
        do {
            _ = try await PostService.acceptTerms()
            onAccepted()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't save. Try again."
        }
    }
}
