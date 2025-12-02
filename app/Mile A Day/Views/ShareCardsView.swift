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
    case custom = "Custom"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .streak: return "flame.fill"
        case .todaysProgress: return "figure.run"
        case .fastestPace: return "hare.fill"
        case .mostMiles: return "star.fill"
        case .totalMiles: return "map.fill"
        case .weekSummary: return "calendar.badge.clock"
        case .custom: return "slider.horizontal.3"
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
        case .custom: return .pink
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
    @State private var showingCustomBuilder = false
    @State private var customCards: [CustomShareCardConfig] = []
    @State private var selectedCustomCard: CustomShareCardConfig?
    
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
                                        if cardType == .custom {
                                            if let defaultCard = CustomShareCardConfig.getDefaultCard() {
                                                selectedCustomCard = defaultCard
                                            } else if let firstCard = customCards.first {
                                                selectedCustomCard = firstCard
                                            } else {
                                                showingCustomBuilder = true
                                                return
                                            }
                                        }
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
                
                    // Custom card selector (if custom cards exist)
                    if selectedCard == .custom && !customCards.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Custom Cards")
                                    .font(MADTheme.Typography.headline)
                                    .foregroundColor(.white)
                                Spacer()
                                Button {
                                    showingCustomBuilder = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus.circle.fill")
                                        Text("New")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.white.opacity(0.2))
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(customCards) { card in
                                        VStack(spacing: 8) {
                                            Button {
                                                selectedCustomCard = card
                                                generateImage()
                                            } label: {
                                                VStack(spacing: 6) {
                                                    Image(systemName: "square.fill")
                                                        .font(.title3)
                                                        .foregroundColor(Color(hex: card.accentColor))
                                                    
                                                    Text(card.name)
                                                        .font(.caption)
                                                        .foregroundColor(.white)
                                                        .lineLimit(1)
                                                        .frame(maxWidth: 80)
                                                }
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 10)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .fill(selectedCustomCard?.id == card.id ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
                                                )
                                            }
                                            
                                            // Edit and Delete buttons
                                            HStack(spacing: 8) {
                                                Button {
                                                    selectedCustomCard = card
                                                    showingCustomBuilder = true
                                                } label: {
                                                    Image(systemName: "pencil")
                                                        .font(.caption2)
                                                        .foregroundColor(.white.opacity(0.8))
                                                        .padding(6)
                                                        .background(
                                                            Circle()
                                                                .fill(Color.blue.opacity(0.3))
                                                        )
                                                }
                                                
                                                Button {
                                                    if let index = customCards.firstIndex(where: { $0.id == card.id }) {
                                                        customCards.remove(at: index)
                                                        CustomShareCardConfig.saveCards(customCards)
                                                        if selectedCustomCard?.id == card.id {
                                                            selectedCustomCard = customCards.first
                                                            if selectedCustomCard == nil {
                                                                selectedCard = .streak
                                                            }
                                                        }
                                                        generateImage()
                                                    }
                                                } label: {
                                                    Image(systemName: "trash")
                                                        .font(.caption2)
                                                        .foregroundColor(.white.opacity(0.8))
                                                        .padding(6)
                                                        .background(
                                                            Circle()
                                                                .fill(Color.red.opacity(0.3))
                                                        )
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }
                    
                    // Action buttons with glass effect
                    VStack(spacing: 12) {
                        if selectedCard == .custom {
                            Button {
                                showingCustomBuilder = true
                            } label: {
                                HStack {
                                    Image(systemName: "slider.horizontal.3")
                                    Text("Customize Card")
                                }
                                .font(MADTheme.Typography.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(.ultraThinMaterial)
                                )
                            }
                        }
                        
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
            .sheet(isPresented: $showingCustomBuilder) {
                CustomCardBuilderView(
                    user: user,
                    currentDistance: currentDistance,
                    progress: progress,
                    isGoalCompleted: isGoalCompleted,
                    fastestPace: fastestPace,
                    mostMiles: mostMiles,
                    totalMiles: totalMiles,
                    existingCard: selectedCustomCard
                ) { newCard in
                    if let index = customCards.firstIndex(where: { $0.id == newCard.id }) {
                        customCards[index] = newCard
                    } else {
                        customCards.append(newCard)
                    }
                    CustomShareCardConfig.saveCards(customCards)
                    selectedCustomCard = newCard
                    selectedCard = .custom
                    generateImage()
                }
            }
            .onAppear {
                selectedTheme = systemColorScheme
                customCards = CustomShareCardConfig.loadSavedCards()
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
        
        if selectedCard == .custom, let customCard = selectedCustomCard {
            renderer = ImageRenderer(content: AnyView(
                CustomShareCardView(
                    config: customCard,
                    user: user,
                    currentDistance: currentDistance,
                    progress: progress,
                    isGoalCompleted: isGoalCompleted,
                    fastestPace: fastestPace,
                    mostMiles: mostMiles,
                    totalMiles: totalMiles
                ).environment(\.colorScheme, selectedTheme)
            ))
        } else {
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
            case .custom:
                renderer = ImageRenderer(content: AnyView(
                    Text("No custom card selected")
                        .environment(\.colorScheme, selectedTheme)
                ))
            }
        }
        
        // High resolution - tight crop with no extra space
        renderer.scale = 3.0
        renderer.isOpaque = false
        generatedImage = renderer.uiImage
    }
}

// MARK: - Share Card Button with Better Padding

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

// MARK: - Individual Share Cards (Tighter Spacing)

struct StreakShareCard: View {
    let streak: Int
    let isActiveToday: Bool
    let isAtRisk: Bool
    @Environment(\.colorScheme) var colorScheme
    
    private var isDarkMode: Bool {
        colorScheme == .dark
    }
    
    // Dynamic colors based on streak status
    private var streakColor: Color {
        if isActiveToday {
            return .green
        } else if isAtRisk {
            return .red
        } else {
            return .orange
        }
    }
    
    private var gradientColors: [Color] {
        if isActiveToday {
            return [.green.opacity(0.4), .green.opacity(0.2), .green.opacity(0.1)]
        } else if isAtRisk {
            return [.red.opacity(0.4), .red.opacity(0.2), .red.opacity(0.1)]
        } else {
            return [.orange.opacity(0.4), .orange.opacity(0.2), .orange.opacity(0.1)]
        }
    }
    
    var body: some View {
        ZStack {
            // Base background color
            RoundedRectangle(cornerRadius: 80)
                .fill(isDarkMode ? Color.black.opacity(0.95) : Color.white.opacity(0.2))
            
            // Red tint overlay
            RoundedRectangle(cornerRadius: 80)
                .fill(
                    LinearGradient(
                        colors: [
                            MADTheme.Colors.madRed.opacity(0.25),
                            MADTheme.Colors.madRed.opacity(0.15),
                            MADTheme.Colors.madRed.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Red glow outline
            RoundedRectangle(cornerRadius: 80)
                .stroke(
                    LinearGradient(
                        colors: [
                            MADTheme.Colors.madRed.opacity(0.9),
                            MADTheme.Colors.madRed.opacity(0.6),
                            MADTheme.Colors.madRed.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 4
                )
            
            // Shadow for glow effect
            RoundedRectangle(cornerRadius: 80)
                .fill(Color.clear)
                .shadow(color: MADTheme.Colors.madRed.opacity(0.7), radius: 40, x: 0, y: 0)
            
            VStack(spacing: 0) {
                // Streak circle with fire icon (like widget) - tighter and more exciting
                ZStack {
                    // Outer glow effect
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    streakColor.opacity(0.4),
                                    streakColor.opacity(0.2),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 120,
                                endRadius: 180
                            )
                        )
                        .frame(width: 360, height: 360)
                        .blur(radius: 20)
                    
                    // Background circle with gradient
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 260, height: 260)
                        .shadow(color: streakColor.opacity(0.6), radius: 20, x: 0, y: 0)
                    
                    // Progress ring background
                    Circle()
                        .stroke(Color.gray.opacity(0.25), lineWidth: 7)
                        .frame(width: 285, height: 285)
                    
                    // Progress ring (full when completed) with glow
                    Circle()
                        .trim(from: 0, to: isActiveToday ? 1.0 : 0.8)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    streakColor,
                                    streakColor.opacity(0.9),
                                    streakColor.opacity(0.7)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .frame(width: 285, height: 285)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: streakColor.opacity(0.7), radius: 10, x: 0, y: 0)
                    
                    // Center content with fire icon - more exciting
                    VStack(spacing: 8) {
                        // Fire icon with glow and animation effect
                        ZStack {
                            // Fire glow behind
                            Image(systemName: "flame.fill")
                                .font(.system(size: 50, weight: .bold))
                                .foregroundColor(.orange.opacity(0.4))
                                .blur(radius: 8)
                            
                            // Main fire icon
                            Image(systemName: "flame.fill")
                                .font(.system(size: 50, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.yellow, .orange, .red],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: .orange.opacity(0.9), radius: 10, x: 0, y: 0)
                        }
                        
                        // Streak number with glow
                        Text("\(streak)")
                            .font(.system(size: 70, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: streakColor.opacity(0.6), radius: 6, x: 0, y: 0)
                        
                        // Days text
                        Text(streak == 1 ? "day" : "days")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                .padding(.top, 30)
                
                Spacer(minLength: 10)
                
                // MAD icon and slogan at bottom
                VStack(spacing: 8) {
                    Image("mad-logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 140, height: 140)
                        .shadow(color: .black.opacity(0.4), radius: 15, x: 0, y: 5)
                    
                    Text("Go the Extra Mile")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.bottom, 20)
            }
            .padding(30)
        }
        .frame(width: 600, height: 750) // Much tighter, more compact size
        .padding(8) // Add tiny bit of blank space around the card
        .clipped()
    }
}

struct TodaysProgressShareCard: View {
    let currentDistance: Double
    let goalDistance: Double
    let progress: Double
    let didComplete: Bool
    @Environment(\.colorScheme) var colorScheme
    
    private var isDarkMode: Bool {
        colorScheme == .dark
    }
    
    private var accentColor: Color {
        .blue
    }
    
    var body: some View {
        ZStack {
            // Base background color
            RoundedRectangle(cornerRadius: 80)
                .fill(isDarkMode ? Color.black.opacity(0.95) : Color.white.opacity(0.2))
            
            // Blue tint overlay
            RoundedRectangle(cornerRadius: 80)
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.25),
                            accentColor.opacity(0.15),
                            accentColor.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Blue glow outline
            RoundedRectangle(cornerRadius: 80)
                .stroke(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.9),
                            accentColor.opacity(0.6),
                            accentColor.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 4
                )
            
            // Shadow for glow effect
            RoundedRectangle(cornerRadius: 80)
                .fill(Color.clear)
                .shadow(color: accentColor.opacity(0.7), radius: 40, x: 0, y: 0)
            
            VStack(spacing: 0) {
                Spacer()
                
                // Progress content - centered
                VStack(spacing: 24) {
                    Text("Today's Progress")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    HStack(alignment: .lastTextBaseline, spacing: 10) {
                        Text(String(format: "%.2f", currentDistance))
                            .font(.system(size: 90, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("/ \(String(format: "%.1f", goalDistance))")
                            .font(.system(size: 36, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Text("miles")
                        .font(.system(size: 24, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                    
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.2))
                            RoundedRectangle(cornerRadius: 14)
                                .fill(didComplete ? Color.green : accentColor)
                                .frame(width: geometry.size.width * min(progress, 1.0))
                        }
                    }
                    .frame(height: 20)
                    .padding(.horizontal, 50)
                    
                    if didComplete {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.green)
                            Text("Goal completed!")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundColor(.green)
                        }
                    } else {
                        Text("\(Int(progress * 100))% complete")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                
                Spacer()
                
                // MAD icon and slogan at bottom
                VStack(spacing: 8) {
                    Image("mad-logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 140, height: 140)
                        .shadow(color: .black.opacity(0.4), radius: 15, x: 0, y: 5)
                    
                    Text("Go the Extra Mile")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.bottom, 20)
            }
            .padding(30)
        }
        .frame(width: 600, height: 750)
        .padding(8)
        .clipped()
    }
}

struct FastestPaceShareCard: View {
    let fastestPace: TimeInterval
    @Environment(\.colorScheme) var colorScheme
    
    private var isDarkMode: Bool {
        colorScheme == .dark
    }
    
    private var accentColor: Color {
        .green
    }
    
    private var paceString: String {
        let minutes = Int(fastestPace)
        let seconds = Int((fastestPace - Double(minutes)) * 60)
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var body: some View {
        ZStack {
            // Base background color
            RoundedRectangle(cornerRadius: 80)
                .fill(isDarkMode ? Color.black.opacity(0.95) : Color.white.opacity(0.2))
            
            // Green tint overlay
            RoundedRectangle(cornerRadius: 80)
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.25),
                            accentColor.opacity(0.15),
                            accentColor.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Green glow outline
            RoundedRectangle(cornerRadius: 80)
                .stroke(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.9),
                            accentColor.opacity(0.6),
                            accentColor.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 4
                )
            
            // Shadow for glow effect
            RoundedRectangle(cornerRadius: 80)
                .fill(Color.clear)
                .shadow(color: accentColor.opacity(0.7), radius: 40, x: 0, y: 0)
            
            VStack(spacing: 0) {
                Spacer()
                
                // Pace content - centered
                VStack(spacing: 24) {
                    Text("Fastest Mile")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text(paceString)
                        .font(.system(size: 100, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("per mile")
                        .font(.system(size: 24, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                    
                    let mph = 60.0 / fastestPace
                    Text(String(format: "%.1f mph", mph))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundColor(accentColor)
                }
                
                Spacer()
                
                // MAD icon and slogan at bottom
                VStack(spacing: 8) {
                    Image("mad-logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 140, height: 140)
                        .shadow(color: .black.opacity(0.4), radius: 15, x: 0, y: 5)
                    
                    Text("Go the Extra Mile")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.bottom, 20)
            }
            .padding(30)
        }
        .frame(width: 600, height: 750)
        .padding(8)
        .clipped()
    }
}

struct MostMilesShareCard: View {
    let mostMiles: Double
    @Environment(\.colorScheme) var colorScheme
    
    private var isDarkMode: Bool {
        colorScheme == .dark
    }
    
    private var accentColor: Color {
        .purple
    }
    
    var body: some View {
        ZStack {
            // Base background color
            RoundedRectangle(cornerRadius: 80)
                .fill(isDarkMode ? Color.black.opacity(0.95) : Color.white.opacity(0.2))
            
            // Purple tint overlay
            RoundedRectangle(cornerRadius: 80)
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.25),
                            accentColor.opacity(0.15),
                            accentColor.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Purple glow outline
            RoundedRectangle(cornerRadius: 80)
                .stroke(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.9),
                            accentColor.opacity(0.6),
                            accentColor.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 4
                )
            
            // Shadow for glow effect
            RoundedRectangle(cornerRadius: 80)
                .fill(Color.clear)
                .shadow(color: accentColor.opacity(0.7), radius: 40, x: 0, y: 0)
            
            VStack(spacing: 0) {
                Spacer()
                
                // Miles content - centered
                VStack(spacing: 24) {
                    Text("Most Miles")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("in a single day")
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text(String(format: "%.2f", mostMiles))
                        .font(.system(size: 100, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("miles")
                        .font(.system(size: 24, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                }
                
                Spacer()
                
                // MAD icon and slogan at bottom
                VStack(spacing: 8) {
                    Image("mad-logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 140, height: 140)
                        .shadow(color: .black.opacity(0.4), radius: 15, x: 0, y: 5)
                    
                    Text("Go the Extra Mile")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.bottom, 20)
            }
            .padding(30)
        }
        .frame(width: 600, height: 750)
        .padding(8)
        .clipped()
    }
}

struct TotalMilesShareCard: View {
    let totalMiles: Double
    let streak: Int
    @Environment(\.colorScheme) var colorScheme
    
    private var isDarkMode: Bool {
        colorScheme == .dark
    }
    
    private var accentColor: Color {
        .red
    }
    
    var body: some View {
        ZStack {
            // Base background color
            RoundedRectangle(cornerRadius: 80)
                .fill(isDarkMode ? Color.black.opacity(0.95) : Color.white.opacity(0.2))
            
            // Red tint overlay
            RoundedRectangle(cornerRadius: 80)
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.25),
                            accentColor.opacity(0.15),
                            accentColor.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Red glow outline
            RoundedRectangle(cornerRadius: 80)
                .stroke(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.9),
                            accentColor.opacity(0.6),
                            accentColor.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 4
                )
            
            // Shadow for glow effect
            RoundedRectangle(cornerRadius: 80)
                .fill(Color.clear)
                .shadow(color: accentColor.opacity(0.7), radius: 40, x: 0, y: 0)
            
            VStack(spacing: 0) {
                Spacer()
                
                // Total miles content - centered
                VStack(spacing: 24) {
                    Text("TOTAL DISTANCE")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text(String(format: "%.1f", totalMiles))
                        .font(.system(size: 100, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("lifetime miles")
                        .font(.system(size: 24, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                    
                    // Fun facts
                    VStack(spacing: 16) {
                        let marathons = totalMiles / 26.2
                        HStack(spacing: 12) {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white.opacity(0.8))
                            Text("\(String(format: "%.1f", marathons)) marathons")
                                .font(.system(size: 20, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        
                        let avgPerDay = totalMiles / Double(max(streak, 1))
                        HStack(spacing: 12) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 20))
                                .foregroundColor(.white.opacity(0.8))
                            Text("\(String(format: "%.2f", avgPerDay)) mi/day avg")
                                .font(.system(size: 20, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .padding(.top, 10)
                }
                
                Spacer()
                
                // MAD icon and slogan at bottom
                VStack(spacing: 8) {
                    Image("mad-logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 140, height: 140)
                        .shadow(color: .black.opacity(0.4), radius: 15, x: 0, y: 5)
                    
                    Text("Go the Extra Mile")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.bottom, 20)
            }
            .padding(30)
        }
        .frame(width: 600, height: 750)
        .padding(8)
        .clipped()
    }
}

struct WeekSummaryShareCard: View {
    let currentDistance: Double
    let totalMiles: Double
    let streak: Int
    let fastestPace: TimeInterval
    @Environment(\.colorScheme) var colorScheme
    
    private var isDarkMode: Bool {
        colorScheme == .dark
    }
    
    private var accentColor: Color {
        .cyan
    }
    
    private var paceString: String {
        let minutes = Int(fastestPace)
        let seconds = Int((fastestPace - Double(minutes)) * 60)
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var body: some View {
        ZStack {
            // Base background color
            RoundedRectangle(cornerRadius: 80)
                .fill(isDarkMode ? Color.black.opacity(0.95) : Color.white.opacity(0.2))
            
            // Cyan tint overlay
            RoundedRectangle(cornerRadius: 80)
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.25),
                            accentColor.opacity(0.15),
                            accentColor.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Cyan glow outline
            RoundedRectangle(cornerRadius: 80)
                .stroke(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.9),
                            accentColor.opacity(0.6),
                            accentColor.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 4
                )
            
            // Shadow for glow effect
            RoundedRectangle(cornerRadius: 80)
                .fill(Color.clear)
                .shadow(color: accentColor.opacity(0.7), radius: 40, x: 0, y: 0)
            
            VStack(spacing: 0) {
                Spacer()
                
                // Stats content - centered
                VStack(spacing: 24) {
                    Text("MY STATS")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    // Stats grid
                    VStack(spacing: 20) {
                        HStack(spacing: 12) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.orange)
                            Text("\(streak) Day Streak")
                                .font(.system(size: 22, weight: .medium, design: .rounded))
                                .foregroundColor(.white)
                        }
                        
                        HStack(spacing: 12) {
                            Image(systemName: "figure.run")
                                .font(.system(size: 22))
                                .foregroundColor(.blue)
                            Text("\(String(format: "%.2f", currentDistance)) mi Today")
                                .font(.system(size: 22, weight: .medium, design: .rounded))
                                .foregroundColor(.white)
                        }
                        
                        HStack(spacing: 12) {
                            Image(systemName: "map.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.red)
                            Text("\(String(format: "%.1f", totalMiles)) mi Total")
                                .font(.system(size: 22, weight: .medium, design: .rounded))
                                .foregroundColor(.white)
                        }
                        
                        HStack(spacing: 12) {
                            Image(systemName: "hare.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.green)
                            Text("\(paceString) /mi Best")
                                .font(.system(size: 22, weight: .medium, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                }
                
                Spacer()
                
                // MAD icon and slogan at bottom
                VStack(spacing: 8) {
                    Image("mad-logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 140, height: 140)
                        .shadow(color: .black.opacity(0.4), radius: 15, x: 0, y: 5)
                    
                    Text("Go the Extra Mile")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.bottom, 20)
            }
            .padding(30)
        }
        .frame(width: 600, height: 750)
        .padding(8)
        .clipped()
    }
}

// MARK: - Glass Stat Row Component

struct GlassStatRow: View {
    let icon: String
    let text: String
    let color: Color
    let isDarkMode: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(text)
                .font(.system(size: 14, weight: .medium, design: .default))
                .foregroundColor(isDarkMode ? .white : .black)
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Custom Card View

struct CustomShareCardView: View {
    let config: CustomShareCardConfig
    let user: User
    let currentDistance: Double
    let progress: Double
    let isGoalCompleted: Bool
    let fastestPace: TimeInterval
    let mostMiles: Double
    let totalMiles: Double
    @Environment(\.colorScheme) var colorScheme
    
    private var isDarkMode: Bool {
        colorScheme == .dark
    }
    
    private var accentColor: Color {
        Color(hex: config.accentColor)
    }
    
    var body: some View {
        ZStack {
            // Base background color
            RoundedRectangle(cornerRadius: 80)
                .fill(isDarkMode ? Color.black.opacity(0.95) : Color.white.opacity(0.2))
            
            // Custom color tint overlay
            RoundedRectangle(cornerRadius: 80)
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.25),
                            accentColor.opacity(0.15),
                            accentColor.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Custom color glow outline
            RoundedRectangle(cornerRadius: 80)
                .stroke(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.9),
                            accentColor.opacity(0.6),
                            accentColor.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 4
                )
            
            // Shadow for glow effect
            RoundedRectangle(cornerRadius: 80)
                .fill(Color.clear)
                .shadow(color: accentColor.opacity(0.7), radius: 40, x: 0, y: 0)
            
            VStack(spacing: 0) {
                Spacer()
                
                // Custom content - centered
                VStack(spacing: 24) {
                    Text(config.name.uppercased())
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    VStack(spacing: 20) {
                        ForEach(config.elements, id: \.self) { element in
                            elementView(for: element)
                        }
                    }
                }
                
                Spacer()
                
                // MAD icon and slogan at bottom
                VStack(spacing: 8) {
                    Image("mad-logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 140, height: 140)
                        .shadow(color: .black.opacity(0.4), radius: 15, x: 0, y: 5)
                    
                    Text("Go the Extra Mile")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.bottom, 20)
            }
            .padding(30)
        }
        .frame(width: 600, height: 750)
        .padding(8)
        .clipped()
    }
    
    @ViewBuilder
    private func elementView(for element: ShareCardElement) -> some View {
        switch element {
        case .streak:
            HStack(spacing: 12) {
                Image(systemName: element.icon)
                    .font(.system(size: 20))
                    .foregroundColor(element.color)
                Text("\(user.streak) Day Streak")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
            }
        case .todaysDistance:
            HStack(spacing: 12) {
                Image(systemName: element.icon)
                    .font(.system(size: 20))
                    .foregroundColor(element.color)
                Text("\(String(format: "%.2f", currentDistance)) mi Today")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
            }
        case .todaysProgress:
            HStack(spacing: 12) {
                Image(systemName: element.icon)
                    .font(.system(size: 20))
                    .foregroundColor(element.color)
                Text("\(Int(progress * 100))% Complete")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
            }
        case .goalStatus:
            if isGoalCompleted {
                HStack(spacing: 12) {
                    Image(systemName: element.icon)
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                    Text("Goal Completed!")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                }
            }
        case .fastestPace:
            let minutes = Int(fastestPace)
            let seconds = Int((fastestPace - Double(minutes)) * 60)
            let paceStr = String(format: "%d:%02d", minutes, seconds)
            HStack(spacing: 12) {
                Image(systemName: element.icon)
                    .font(.system(size: 20))
                    .foregroundColor(element.color)
                Text("\(paceStr) /mi Best")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
            }
        case .mostMiles:
            HStack(spacing: 12) {
                Image(systemName: element.icon)
                    .font(.system(size: 20))
                    .foregroundColor(element.color)
                Text("\(String(format: "%.2f", mostMiles)) mi Record")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
            }
        case .totalMiles:
            HStack(spacing: 12) {
                Image(systemName: element.icon)
                    .font(.system(size: 20))
                    .foregroundColor(element.color)
                Text("\(String(format: "%.1f", totalMiles)) mi Total")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
            }
        case .averagePerDay:
            let avg = totalMiles / Double(max(user.streak, 1))
            HStack(spacing: 12) {
                Image(systemName: element.icon)
                    .font(.system(size: 20))
                    .foregroundColor(element.color)
                Text("\(String(format: "%.2f", avg)) mi/day avg")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
            }
        case .marathonEquivalent:
            let marathons = totalMiles / 26.2
            HStack(spacing: 12) {
                Image(systemName: element.icon)
                    .font(.system(size: 20))
                    .foregroundColor(element.color)
                Text("\(String(format: "%.1f", marathons)) marathons")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
            }
        }
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

// MARK: - Custom Card Builder (Placeholder - will implement next)

struct CustomCardBuilderView: View {
    let user: User
    let currentDistance: Double
    let progress: Double
    let isGoalCompleted: Bool
    let fastestPace: TimeInterval
    let mostMiles: Double
    let totalMiles: Double
    let existingCard: CustomShareCardConfig?
    let onSave: (CustomShareCardConfig) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var cardName: String
    @State private var selectedElements: Set<ShareCardElement>
    @State private var selectedColor: Color
    @State private var isDefault: Bool
    
    init(user: User, currentDistance: Double, progress: Double, isGoalCompleted: Bool, fastestPace: TimeInterval, mostMiles: Double, totalMiles: Double, existingCard: CustomShareCardConfig?, onSave: @escaping (CustomShareCardConfig) -> Void) {
        self.user = user
        self.currentDistance = currentDistance
        self.progress = progress
        self.isGoalCompleted = isGoalCompleted
        self.fastestPace = fastestPace
        self.mostMiles = mostMiles
        self.totalMiles = totalMiles
        self.existingCard = existingCard
        self.onSave = onSave
        
        _cardName = State(initialValue: existingCard?.name ?? "My Custom Card")
        _selectedElements = State(initialValue: Set(existingCard?.elements ?? [.streak, .todaysDistance]))
        _selectedColor = State(initialValue: existingCard?.color ?? .pink)
        _isDefault = State(initialValue: existingCard?.isDefault ?? false)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    // Live Preview - very compact
                    VStack(spacing: 2) {
                        Text("Live Preview")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        livePreview
                            .scaleEffect(0.18)
                            .frame(height: 135)
                            .frame(maxWidth: .infinity)
                            .clipped()
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.1))
                    )
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    // Form content - scrollable
                    formContent
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
            .navigationTitle("Customize Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let config = CustomShareCardConfig(
                            id: existingCard?.id ?? UUID(),
                            name: cardName,
                            elements: Array(selectedElements),
                            accentColor: selectedColor.toHex() ?? "#FF6B35",
                            isDefault: isDefault
                        )
                        onSave(config)
                        dismiss()
                    }
                    .disabled(cardName.isEmpty || selectedElements.isEmpty)
                }
            }
        }
    }
    
    private var formContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Card Name
            VStack(alignment: .leading, spacing: 4) {
                Text("Card Name")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                TextField("Enter name", text: $cardName)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
            }
            
            // Select Elements - very compact list
            VStack(alignment: .leading, spacing: 6) {
                Text("Select Elements")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                VStack(spacing: 4) {
                    ForEach(ShareCardElement.allCases) { element in
                        Button {
                            if selectedElements.contains(element) {
                                selectedElements.remove(element)
                            } else {
                                selectedElements.insert(element)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: element.icon)
                                    .foregroundColor(element.color)
                                    .frame(width: 20, height: 20)
                                    .font(.system(size: 14))
                                Text(element.rawValue)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedElements.contains(element) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 14))
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 14))
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedElements.contains(element) ? element.color.opacity(0.1) : Color.secondary.opacity(0.05))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Accent Color
            VStack(alignment: .leading, spacing: 4) {
                Text("Accent Color")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                ColorPicker("Choose color", selection: $selectedColor)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Default toggle
            Toggle("Set as default card", isOn: $isDefault)
                .font(.subheadline)
        }
    }
    
    private var livePreview: some View {
        CustomShareCardView(
            config: CustomShareCardConfig(
                name: cardName.isEmpty ? "Preview" : cardName,
                elements: Array(selectedElements),
                accentColor: selectedColor.toHex() ?? "#FF6B35"
            ),
            user: user,
            currentDistance: currentDistance,
            progress: progress,
            isGoalCompleted: isGoalCompleted,
            fastestPace: fastestPace,
            mostMiles: mostMiles,
            totalMiles: totalMiles
        )
    }
}
