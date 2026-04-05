//
//  ShareCardsView.swift
//  Mile A Day
//
//  Enhanced share card system with full customization
//

import SwiftUI
import HealthKit

// MARK: - Liquid Glass Background Component

struct LiquidGlassBackground: View {
    let accentColor: Color
    let isDarkMode: Bool

    var body: some View {
        ZStack {
            // Base gradient background
            LinearGradient(
                colors: isDarkMode ? [
                    Color.black,
                    Color(red: 0.1, green: 0.1, blue: 0.1),
                    Color(red: 0.05, green: 0.05, blue: 0.05)
                ] : [
                    Color.white,
                    Color(red: 0.98, green: 0.98, blue: 0.98),
                    Color(red: 0.95, green: 0.95, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Accent color gradient overlay
            LinearGradient(
                colors: [
                    accentColor.opacity(0.15),
                    accentColor.opacity(0.05),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Glass reflection effect
            LinearGradient(
                colors: [
                    Color.white.opacity(isDarkMode ? 0.1 : 0.3),
                    Color.clear,
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .center
            )

            // Subtle highlight overlay
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isDarkMode ? 0.2 : 0.4),
                            Color.clear,
                            Color.clear,
                            Color.black.opacity(isDarkMode ? 0.3 : 0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
}

// MARK: - Sticker Background (compact, high-contrast, no glow)

struct StickerBackground: View {
    let accentColor: Color
    let isDarkMode: Bool

    var body: some View {
        ZStack {
            // Simple high-contrast base
            RoundedRectangle(cornerRadius: 24)
                .fill(isDarkMode ? Color.black.opacity(0.9) : Color.white)

            // Subtle accent edge
            RoundedRectangle(cornerRadius: 24)
                .stroke(accentColor.opacity(0.35), lineWidth: 2)
        }
    }
}

// MARK: - MAD Branding Component

struct MADBrandingHeader: View {
    let accentColor: Color
    let isDarkMode: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Actual MAD Logo from assets
            Image("mad-logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("MILE A DAY")
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .fontWidth(.condensed)
                    .foregroundColor(isDarkMode ? .white : .black)
                    .tracking(1)

                Text("Stay Active. Stay Motivated.")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(isDarkMode ? .white.opacity(0.7) : .black.opacity(0.6))
            }

            Spacer()
        }
    }
}

// MARK: - Compact Branding Footer (icon + slogan)

struct MADBrandingFooter: View {
    let isDarkMode: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image("mad-logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text("Mile A Day")
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .foregroundColor(isDarkMode ? .white : .black)
                Text("Stay Active. Stay Motivated.")
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundColor(isDarkMode ? .white.opacity(0.7) : .black.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Shared Sticker Card Container (dashboard-like)

struct ShareStickerCardContainer: ViewModifier {
    let accentColor: Color
    let isDarkMode: Bool

    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(accentColor.opacity(0.25), lineWidth: 1)
                    )
            )
            .frame(width: 280)
    }
}

extension View {
    func shareStickerCard(accentColor: Color, isDarkMode: Bool) -> some View {
        modifier(ShareStickerCardContainer(accentColor: accentColor, isDarkMode: isDarkMode))
    }
}

// MARK: - Share Card Types

enum ShareCardType: String, CaseIterable, Identifiable {
    case streak = "Streak"
    case todaysProgress = "Progress"
    case fastestPace = "Fastest"
    case mostMiles = "Most Miles"
    case totalMiles = "Total"
    case weekSummary = "Summary"

    var id: String { self.rawValue }

    var icon: String {
        switch self {
        case .streak: return "flame.fill"
        case .todaysProgress: return "figure.run"
        case .fastestPace: return "hare.fill"
        case .mostMiles: return "star.fill"
        case .totalMiles: return "map.fill"
        case .weekSummary: return "calendar.badge.clock"
        }
    }

    var color: Color {
        switch self {
        case .streak: return .orange
        case .todaysProgress: return .blue
        case .fastestPace: return .green
        case .mostMiles: return .purple
        case .totalMiles: return .red
        case .weekSummary: return .cyan
        }
    }
}

// MARK: - Main Share View with Full Customization

struct EnhancedShareView: View {
    let user: User
    let currentDistance: Double
    let progress: Double
    let isGoalCompleted: Bool
    let fastestPace: TimeInterval
    let mostMiles: Double
    let totalMiles: Double

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemColorScheme

    @State private var selectedCard: ShareCardType = .streak
    @State private var selectedTheme: ColorScheme = .light
    @State private var showingShareSheet = false
    @State private var generatedImage: UIImage?
    @State private var showingCopiedFeedback = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Gradient background
                MADTheme.Colors.appBackgroundGradient
                    .ignoresSafeArea(.all)

                VStack(spacing: 20) {
                    // Theme picker with glass effect
                    HStack {
                        Text("Theme")
                            .font(MADTheme.Typography.headline)
                            .foregroundColor(.white)

                        Spacer()

                        Picker("Theme", selection: $selectedTheme) {
                            Text("Light").tag(ColorScheme.light)
                            Text("Dark").tag(ColorScheme.dark)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 150)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                    )
                    .padding(.horizontal)

                    // Card type picker - cleaner grid layout
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(ShareCardType.allCases) { cardType in
                                ShareCardButton(
                                    cardType: cardType,
                                    isSelected: selectedCard == cardType,
                                    action: {
                                        selectedCard = cardType
                                        generateImage()
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }

                // Preview - Instagram story format
                ZStack {
                    if generatedImage != nil {
                        Image(uiImage: generatedImage!)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 500)
                            .cornerRadius(24)
                            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
                    } else {
                        ProgressView()
                            .frame(height: 500)
                    }
                }
                .padding(.horizontal, 20)

                    // Action buttons with glass effect
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Button {
                                if let image = generatedImage {
                                    UIPasteboard.general.image = image
                                    showingCopiedFeedback = true
                                    let impact = UIImpactFeedbackGenerator(style: .medium)
                                    impact.impactOccurred()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: showingCopiedFeedback ? "checkmark.circle.fill" : "doc.on.doc")
                                    Text(showingCopiedFeedback ? "Copied!" : "Copy")
                                }
                                .font(MADTheme.Typography.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(showingCopiedFeedback ? Color.green.opacity(0.3) : Color.blue.opacity(0.3))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .fill(.ultraThinMaterial)
                                        )
                                )
                            }

                            Button {
                                guard generatedImage != nil else { return }
                                showingShareSheet = true
                            } label: {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Share")
                                }
                                .font(MADTheme.Typography.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(MADTheme.Colors.madRed)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .fill(.ultraThinMaterial.opacity(0.2))
                                        )
                                )
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let image = generatedImage {
                    ActivityViewController(activityItems: [image])
                }
            }
            .onAppear {
                selectedTheme = systemColorScheme
                generateImage()
            }
            .onChange(of: selectedTheme) { _, _ in
                generateImage()
            }
            .onChange(of: showingCopiedFeedback) { _, newValue in
                if newValue {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showingCopiedFeedback = false
                    }
                }
            }
        }
    }

    private func generateImage() {
        let renderer: ImageRenderer<AnyView>

        switch selectedCard {
            case .streak:
                renderer = ImageRenderer(content: AnyView(
                    StreakShareCard(streak: user.streak, isActiveToday: isGoalCompleted, isAtRisk: user.isStreakAtRisk)
                        .environment(\.colorScheme, selectedTheme)
                ))
            case .todaysProgress:
                renderer = ImageRenderer(content: AnyView(
                    TodaysProgressShareCard(currentDistance: currentDistance, goalDistance: user.goalMiles, progress: min(progress, 1.0), didComplete: isGoalCompleted)
                        .environment(\.colorScheme, selectedTheme)
                ))
            case .fastestPace:
                renderer = ImageRenderer(content: AnyView(
                    FastestPaceShareCard(fastestPace: fastestPace)
                        .environment(\.colorScheme, selectedTheme)
                ))
            case .mostMiles:
                // Use current streak's most miles if available, otherwise fallback to all-time
                // Check if healthManager is available via environment or use cached value
                let displayMostMiles: Double
                if mostMiles > 0 {
                    // If mostMiles is passed and > 0, use it (should be current streak value)
                    displayMostMiles = mostMiles
                } else {
                    // Fallback to user's all-time most miles
                    displayMostMiles = user.mostMilesInOneDay
                }
                renderer = ImageRenderer(content: AnyView(
                    MostMilesShareCard(mostMiles: displayMostMiles)
                        .environment(\.colorScheme, selectedTheme)
                ))
            case .totalMiles:
                renderer = ImageRenderer(content: AnyView(
                    TotalMilesShareCard(totalMiles: totalMiles, streak: user.streak)
                        .environment(\.colorScheme, selectedTheme)
                ))
            case .weekSummary:
                renderer = ImageRenderer(content: AnyView(
                    WeekSummaryShareCard(currentDistance: currentDistance, totalMiles: totalMiles, streak: user.streak, fastestPace: fastestPace)
                        .environment(\.colorScheme, selectedTheme)
                ))
        }

        // High resolution - tight crop with no extra space
        renderer.scale = 3.0
        renderer.isOpaque = false
        generatedImage = renderer.uiImage
    }
}

// MARK: - Share Card Button with Better Padding

// MARK: - Activity View Controller

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Share Card Button

struct ShareCardButton: View {
    let cardType: ShareCardType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: cardType.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .white.opacity(0.8))
                Text(cardType.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isSelected ? .white : .white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(width: 90, height: 90)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)

                    if isSelected {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(cardType.color.opacity(0.3))
                    }

                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isSelected ? cardType.color : Color.white.opacity(0.2),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
            )
            .shadow(color: isSelected ? cardType.color.opacity(0.4) : Color.black.opacity(0.2), radius: isSelected ? 12 : 4, x: 0, y: 4)
        }
    }
}
