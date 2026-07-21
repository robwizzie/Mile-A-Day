import SwiftUI
import UIKit

// MARK: - Share Views

// MARK: - Dashboard Card Share Views

struct StreakCardShareView: View {
    let streak: Int
    let isActiveToday: Bool
    let isAtRisk: Bool
    let user: User
    let progress: Double
    let isGoalCompleted: Bool
    @Environment(\.colorScheme) var colorScheme

    // Dynamic colors based on streak status
    var streakColor: Color {
        if isGoalCompleted {
            return .green
        } else if isAtRisk {
            return .red
        } else {
            return .orange
        }
    }

    var gradientColors: [Color] {
        if isGoalCompleted {
            return [.green.opacity(0.3), .green.opacity(0.1)]
        } else if isAtRisk {
            return [.red.opacity(0.3), .red.opacity(0.1)]
        } else {
            return [.orange.opacity(0.3), .orange.opacity(0.1)]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // MAD Branding Header
            HStack(spacing: 8) {
                MADLogoMark(size: 34, shadow: false)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            VStack(spacing: 10) {
                // Eyebrow title — same quiet grammar as the in-app card, so
                // the shared image matches what the app looks like.
                Text("CURRENT STREAK")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .tracking(1.2)
                    .foregroundColor(streakColor)

                // Streak circle
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: gradientColors),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)

                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                        .frame(width: 108, height: 108)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(streakColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 108, height: 108)
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 2) {
                        Text("\(streak)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(streakColor)

                        Text(streak == 1 ? "day" : "days")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(streakColor.opacity(0.8))
                    }
                }

                // One status line — mirrors the in-app card's merged caption.
                HStack(spacing: 4) {
                    Image(systemName: isGoalCompleted
                          ? "checkmark.circle.fill"
                          : (isAtRisk ? "exclamationmark.triangle.fill" : "flame.fill"))
                        .font(.system(size: 11, weight: .bold))
                    Text(isGoalCompleted
                         ? "Done for today"
                         : (isAtRisk ? "Streak at risk" : "Keep it going"))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundColor(streakColor)
            }
            .padding(16)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)

                LinearGradient(
                    colors: [
                        streakColor.opacity(0.05),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))

                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.2 : 0.3),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        .frame(width: 300, height: 380)
    }
}

struct TodayProgressCardShareView: View {
    let currentDistance: Double
    let goalDistance: Double
    let progress: Double
    let didComplete: Bool
    let totalMiles: Double
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // MAD Branding Header
            HStack(spacing: 8) {
                MADLogoMark(size: 34, shadow: false)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            VStack(spacing: 12) {
                // Eyebrow header — same quiet grammar as the in-app card.
                HStack(spacing: 6) {
                    Text("TODAY")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .tracking(1.2)
                        .foregroundColor(didComplete ? .green : .secondary)
                    if didComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    Spacer()
                }

                // Progress bar — slim capsule, matching the app.
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.gray.opacity(0.2))

                        Capsule()
                            .fill(didComplete ? Color.green : Color(red: 217/255, green: 64/255, blue: 63/255))
                            .frame(width: max(10, progress * geometry.size.width))
                    }
                }
                .frame(height: 10)

                // Distance Display
                HStack {
                    Text(String(format: "%.2f", currentDistance))
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("of")
                        .font(.subheadline)

                    Text(String(format: "%.1f mi", goalDistance))
                        .font(.title2)
                        .fontWeight(.bold)
                }

                // Status or remaining distance
                if didComplete {
                    Label("Goal Complete!", systemImage: "star.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                } else {
                    let remaining = max(goalDistance - currentDistance, 0.0)
                    Text(String(format: "%.2f mi to go", remaining))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Total miles display
                HStack {
                    Image(systemName: "trophy.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text(String(format: "Total Miles: %.1f", totalMiles))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
            }
            .padding(16)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)

                LinearGradient(
                    colors: [
                        (didComplete ? Color.green : Color(red: 217/255, green: 64/255, blue: 63/255)).opacity(0.05),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))

                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.2 : 0.3),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        .frame(width: 300, height: 350)
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Share Preview View

struct SharePreviewView: View {
    let streakImage: UIImage?
    let progressImage: UIImage?
    let title: String
    let initialTab: Int // 0 for streak, 1 for progress
    let user: User
    let progress: Double
    let isGoalCompleted: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false
    @State private var selectedImage: UIImage?
    @State private var copyButtonText = "Copy"
    @State private var showingCopiedFeedback = false
    @State private var currentTab = 0
    @State private var selectedTheme: ColorScheme = .light
    @State private var regeneratedImages: (streak: UIImage?, progress: UIImage?) = (nil, nil)
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Carousel for multiple images
                if let streakImage = streakImage, let progressImage = progressImage {
                    // Both images available - show carousel
                    TabView(selection: $currentTab) {
                        // Streak image
                        VStack(spacing: 12) {
                            Text("Streak")
                                .font(.headline)
                                .fontWeight(.semibold)

                            Image(uiImage: regeneratedImages.streak ?? streakImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding()
                        }
                        .tag(0)

                        // Progress image
                        VStack(spacing: 12) {
                            Text("Progress")
                                .font(.headline)
                                .fontWeight(.semibold)

                            Image(uiImage: regeneratedImages.progress ?? progressImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding()
                        }
                        .tag(1)
                    }
                    .tabViewStyle(PageTabViewStyle())
                    .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
                    .onAppear {
                        currentTab = initialTab
                        selectedTheme = systemColorScheme
                        selectedImage = initialTab == 0 ? (regeneratedImages.streak ?? streakImage) : (regeneratedImages.progress ?? progressImage)
                        regenerateImages()
                    }
                    .onChange(of: currentTab) { _, newValue in
                        selectedImage = newValue == 0 ? (regeneratedImages.streak ?? streakImage) : (regeneratedImages.progress ?? progressImage)
                    }
                    .onChange(of: showingCopiedFeedback) { _, newValue in
                        if newValue {
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                                copyButtonText = "Copy"
                                showingCopiedFeedback = false
                            }
                        }
                    }
                } else {
                    // Single image
                    Image(uiImage: selectedImage ?? (regeneratedImages.streak ?? streakImage) ?? (regeneratedImages.progress ?? progressImage) ?? UIImage())
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                        .onAppear {
                            selectedTheme = systemColorScheme
                            selectedImage = regeneratedImages.streak ?? regeneratedImages.progress ?? streakImage ?? progressImage
                            regenerateImages()
                        }
                }

                // Action buttons
                HStack(spacing: 12) {
                    // Copy button
                    Button {
                        if let imageToCopy = selectedImage {
                            UIPasteboard.general.image = imageToCopy
                            // Haptic feedback for copy
                            MADHaptics.action()

                            // Show "Copied!" feedback
                            copyButtonText = "Copied!"
                            showingCopiedFeedback = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: showingCopiedFeedback ? "checkmark" : "doc.on.doc")
                            Text(copyButtonText)
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(showingCopiedFeedback ? Color.green : Color.green)
                        .cornerRadius(12)
                        .animation(.easeInOut(duration: 0.2), value: showingCopiedFeedback)
                    }
                    .disabled(selectedImage == nil)

                    // Share button
                    Button {
                        showingShareSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    .disabled(selectedImage == nil)
                }
                .padding(.horizontal)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        selectedTheme = selectedTheme == .light ? .dark : .light
                        regenerateImages()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: selectedTheme == .light ? "moon.fill" : "sun.max.fill")
                                .foregroundColor(selectedTheme == .light ? .blue : .orange)
                            Text(selectedTheme == .light ? "Dark" : "Light")
                                .font(.caption)
                                .foregroundColor(selectedTheme == .light ? .blue : .orange)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let image = selectedImage {
                ShareSheet(items: [image])
            }
        }
    }

    private func regenerateImages() {
        // Generate new images with the selected theme
        let streakRenderer = ImageRenderer(content: StreakCardShareView(
            streak: user.streak,
            isActiveToday: user.isStreakActiveToday,
            isAtRisk: user.isStreakAtRisk,
            user: user,
            progress: progress,
            isGoalCompleted: isGoalCompleted
        ).environment(\.colorScheme, selectedTheme))
        streakRenderer.scale = 3.0

        let progressRenderer = ImageRenderer(content: TodayProgressCardShareView(
            currentDistance: progress * user.goalMiles,
            goalDistance: user.goalMiles,
            progress: progress,
            didComplete: isGoalCompleted,
            totalMiles: user.totalMiles
        ).environment(\.colorScheme, selectedTheme))
        progressRenderer.scale = 3.0

        if let streakImg = streakRenderer.uiImage, let progressImg = progressRenderer.uiImage {
            regeneratedImages = (streak: streakImg, progress: progressImg)
            selectedImage = currentTab == 0 ? streakImg : progressImg
        }
    }
}
