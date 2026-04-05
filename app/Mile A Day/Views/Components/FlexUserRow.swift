import SwiftUI

/// A row for flexing on a specific competition opponent with preset or custom messages
struct FlexUserRow: View {
    let user: CompetitionUser
    let typeColor: Color
    let competitionType: CompetitionType
    let onFlex: (String?, @escaping (Bool) -> Void) -> Void

    @State private var isExpanded = false
    @State private var customMessage = ""
    @State private var isSending = false
    @State private var sentMessage: String?
    @State private var showSentIndicator = false

    private let presets = [
        "Better luck next time",
        "Can't catch me",
        "Feeling unstoppable",
        "Is that all you got?",
        "Try to keep up",
        "Too easy",
        "You should probably go run",
        "I woke up and chose victory"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Main row - tap to expand
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: MADTheme.Spacing.sm) {
                    // Avatar
                    AvatarView(
                        name: user.displayName,
                        imageURL: user.profile_image_url,
                        size: 36
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)

                        let score = user.score ?? 0
                        Text(scoreLabel(score))
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(.white.opacity(0.4))
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Text("Flex")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(typeColor)

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(typeColor.opacity(0.6))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(typeColor.opacity(0.12))
                            .overlay(
                                Capsule()
                                    .stroke(typeColor.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                .padding(MADTheme.Spacing.md)
            }
            .buttonStyle(.plain)

            // Expanded: message picker
            if isExpanded {
                VStack(spacing: MADTheme.Spacing.sm) {
                    // Quick send (no message)
                    Button {
                        sendFlex(message: nil)
                    } label: {
                        HStack(spacing: MADTheme.Spacing.sm) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 12))
                                .foregroundColor(typeColor)
                            Text("Send flex (no message)")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.6))
                            Spacer()
                        }
                        .padding(.horizontal, MADTheme.Spacing.md)
                        .padding(.vertical, MADTheme.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                                .fill(Color.white.opacity(0.04))
                        )
                    }
                    .buttonStyle(.plain)

                    // Preset messages (scrollable horizontal)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: MADTheme.Spacing.sm) {
                            ForEach(presets, id: \.self) { preset in
                                Button {
                                    sendFlex(message: preset)
                                } label: {
                                    Text(preset)
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundColor(.white.opacity(0.8))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(typeColor.opacity(0.15))
                                                .overlay(
                                                    Capsule()
                                                        .stroke(typeColor.opacity(0.15), lineWidth: 1)
                                                )
                                        )
                                }
                                .buttonStyle(ScaleButtonStyle())
                            }
                        }
                        .padding(.horizontal, MADTheme.Spacing.md)
                    }

                    // Custom message input
                    HStack(spacing: MADTheme.Spacing.sm) {
                        TextField("Custom message...", text: $customMessage)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                                    .fill(Color.white.opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    )
                            )

                        Button {
                            let msg = customMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                            sendFlex(message: msg.isEmpty ? nil : msg)
                        } label: {
                            if isSending {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .tint(typeColor)
                                    .frame(width: 32, height: 32)
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(
                                        Circle()
                                            .fill(typeColor)
                                    )
                            }
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .disabled(isSending)
                    }
                    .padding(.horizontal, MADTheme.Spacing.md)
                }
                .padding(.bottom, MADTheme.Spacing.md)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Sent indicator with message
            if showSentIndicator {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(typeColor)
                    Text("Flex sent")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(typeColor)
                    if let msg = sentMessage {
                        Text("— \"\(msg)\"")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.bottom, MADTheme.Spacing.sm)
                .transition(.opacity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .stroke(typeColor.opacity(0.15), lineWidth: 1)
                )
        )
    }

    private func scoreLabel(_ score: Double) -> String {
        switch competitionType {
        case .streaks:
            return "\(Int(score)) day streak"
        case .clash:
            return "\(Int(score)) \(Int(score) == 1 ? "win" : "wins")"
        case .apex:
            return String(format: "%.1f total", score)
        case .targets:
            return "\(Int(score)) \(Int(score) == 1 ? "point" : "points")"
        case .race:
            return String(format: "%.1f completed", score)
        }
    }

    private func sendFlex(message: String?) {
        guard !isSending else { return }
        isSending = true
        sentMessage = message

        onFlex(message) { success in
            isSending = false
            if success {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = false
                    showSentIndicator = true
                }
                customMessage = ""
                // Hide sent indicator after a few seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSentIndicator = false
                    }
                }
            }
        }
    }
}
