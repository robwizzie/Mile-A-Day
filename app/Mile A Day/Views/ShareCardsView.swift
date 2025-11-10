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
            VStack(spacing: 16) {
                // Theme picker
                Picker("Theme", selection: $selectedTheme) {
                    Text("Light").tag(ColorScheme.light)
                    Text("Dark").tag(ColorScheme.dark)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                
                // Card type picker with padding and always-visible scroll indicator
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 12) {
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
                    .padding(.vertical, 8)
                }
                .background(Color.secondary.opacity(0.05))
                
                // Preview with glow
                ZStack {
                    if generatedImage != nil {
                        Image(uiImage: generatedImage!)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 420)
                            .cornerRadius(20)
                            
                    } else {
                        ProgressView()
                            .frame(height: 420)
                    }
                }
                .padding(.horizontal, 20)
                
                // Custom card selector (if custom cards exist)
                if selectedCard == .custom && !customCards.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(customCards) { card in
                                Button {
                                    selectedCustomCard = card
                                    generateImage()
                                } label: {
                                    VStack(spacing: 4) {
                                        Circle()
                                            .fill(card.color)
                                            .frame(width: 12, height: 12)
                                        Text(card.name)
                                            .font(.caption2)
                                            .foregroundColor(selectedCustomCard?.id == card.id ? .primary : .secondary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(selectedCustomCard?.id == card.id ? Color.secondary.opacity(0.2) : Color.clear)
                                    .cornerRadius(12)
                                }
                            }
                            
                            Button {
                                showingCustomBuilder = true
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.pink)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                // Action buttons
                VStack(spacing: 12) {
                    if selectedCard == .custom {
                        Button {
                            showingCustomBuilder = true
                        } label: {
                            Label("Customize Card", systemImage: "slider.horizontal.3")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.pink)
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
                            Label(showingCopiedFeedback ? "Copied!" : "Copy", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(showingCopiedFeedback ? Color.green : Color.blue)
                        
                        Button {
                            guard generatedImage != nil else { return }
                            showingShareSheet = true
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal)
                
                // compact layout: no vertical spacers
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
                renderer = ImageRenderer(content: AnyView(
                    MostMilesShareCard(mostMiles: mostMiles)
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
                    .foregroundColor(isSelected ? .white : cardType.color)
                Text(cardType.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(width: 85, height: 85)
            .background(isSelected ? cardType.color : Color.secondary.opacity(0.1))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? cardType.color : Color.clear, lineWidth: 2)
            )
            .shadow(color: isSelected ? cardType.color.opacity(0.3) : Color.clear, radius: 8, x: 0, y: 4)
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
    
    var body: some View {
        VStack(spacing: 10) {
            Text("Current Streak")
                .font(.system(size: 18, weight: .semibold, design: .default))
                .fontWidth(.condensed)
                .foregroundColor(isDarkMode ? .white : .black)
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.black.opacity(0.75), Color.black.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(Circle().stroke(Color.black.opacity(0.7), lineWidth: 6))
                Circle()
                    .inset(by: 6)
                    .stroke(Color.green, lineWidth: 14)
                VStack(spacing: 6) {
                    Text("\(streak)")
                        .font(.system(size: 64, weight: .heavy, design: .default))
                        .fontWidth(.condensed)
                        .foregroundColor(Color.green)
                    Text("days")
                        .font(.system(size: 16, weight: .regular, design: .default))
                        .foregroundColor(isDarkMode ? .white.opacity(0.8) : .black.opacity(0.7))
                }
            }
            .frame(width: 220, height: 220)
            if isActiveToday {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 14, weight: .semibold))
                    Text("Goal completed!")
                        .font(.system(size: 16, weight: .semibold, design: .default))
                        .foregroundColor(Color.green)
                }
            } else if isAtRisk {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 14, weight: .semibold))
                    Text("At risk")
                        .font(.system(size: 16, weight: .semibold, design: .default))
                        .foregroundColor(.yellow)
                }
            }
            // Branding footer
            MADBrandingFooter(isDarkMode: isDarkMode)
        }
        .shareStickerCard(accentColor: .green, isDarkMode: isDarkMode)
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
    
    var body: some View {
        VStack(spacing: 10) {
            Text("Today's Progress")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(isDarkMode ? .white : .black)
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(String(format: "%.2f", currentDistance))
                    .font(.system(size: 44, weight: .heavy))
                    .foregroundColor(.blue)
                Text("/ \(String(format: "%.1f", goalDistance))")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isDarkMode ? .white.opacity(0.75) : .black.opacity(0.65))
            }
            Text("miles")
                .font(.system(size: 12))
                .foregroundColor(isDarkMode ? .white.opacity(0.75) : .black.opacity(0.65))
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.12))
                    RoundedRectangle(cornerRadius: 8)
                        .fill(didComplete ? Color.green : Color.blue)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 10)
            if didComplete {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("Goal completed!").font(.system(size: 14, weight: .semibold)).foregroundColor(.green)
                }
            } else {
                Text("\(Int(progress * 100))% complete").font(.system(size: 13)).foregroundColor(isDarkMode ? .white.opacity(0.75) : .black.opacity(0.65))
            }
            MADBrandingFooter(isDarkMode: isDarkMode)
        }
        .shareStickerCard(accentColor: .blue, isDarkMode: isDarkMode)
    }
}

struct FastestPaceShareCard: View {
    let fastestPace: TimeInterval
    @Environment(\.colorScheme) var colorScheme
    
    private var isDarkMode: Bool {
        colorScheme == .dark
    }
    
    private var paceString: String {
        let minutes = Int(fastestPace)
        let seconds = Int((fastestPace - Double(minutes)) * 60)
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var body: some View {
        VStack(spacing: 10) {
            Text("Fastest Mile").font(.system(size: 18, weight: .semibold)).foregroundColor(isDarkMode ? .white : .black)
            Text(paceString).font(.system(size: 56, weight: .heavy)).foregroundColor(.green)
            Text("per mile").font(.system(size: 12)).foregroundColor(isDarkMode ? .white.opacity(0.75) : .black.opacity(0.65))
            let mph = 60.0 / fastestPace
            Text(String(format: "%.1f mph", mph)).font(.system(size: 14, weight: .semibold)).foregroundColor(.green)
            MADBrandingFooter(isDarkMode: isDarkMode)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(isDarkMode ? Color.black.opacity(0.85) : Color.white)
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.green.opacity(0.3), lineWidth: 1))
        )
        .frame(width: 280)
    }
}

struct MostMilesShareCard: View {
    let mostMiles: Double
    @Environment(\.colorScheme) var colorScheme
    
    private var isDarkMode: Bool {
        colorScheme == .dark
    }
    
    var body: some View {
        VStack(spacing: 10) {
            Text("Most Miles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(isDarkMode ? .white : .black)
            Text("in a single day")
                .font(.system(size: 12))
                .foregroundColor(isDarkMode ? .white.opacity(0.75) : .black.opacity(0.65))
            Text(String(format: "%.2f", mostMiles))
                .font(.system(size: 56, weight: .heavy))
                .foregroundColor(.purple)
            Text("miles")
                .font(.system(size: 12))
                .foregroundColor(isDarkMode ? .white.opacity(0.75) : .black.opacity(0.65))
            MADBrandingFooter(isDarkMode: isDarkMode)
        }
        .shareStickerCard(accentColor: .purple, isDarkMode: isDarkMode)
    }
}

struct TotalMilesShareCard: View {
    let totalMiles: Double
    let streak: Int
    @Environment(\.colorScheme) var colorScheme
    
    private var isDarkMode: Bool {
        colorScheme == .dark
    }
    
    var body: some View {
        ZStack {
            // Sticker background (compact, high-contrast)
            StickerBackground(accentColor: .red, isDarkMode: isDarkMode)
            
            VStack(spacing: 12) {
                // Main content
                VStack(spacing: 20) {
                    Text("TOTAL DISTANCE")
                        .font(.system(size: 16, weight: .semibold, design: .default))
                        .fontWidth(.condensed)
                        .foregroundColor(isDarkMode ? .white : .black)
                    
                    // Miles display with subtle glow effect
                    VStack(spacing: 12) {
                        ZStack {
                            Text(String(format: "%.1f", totalMiles))
                                .font(.system(size: 72, weight: .heavy, design: .default))
                                .fontWidth(.condensed)
                                .foregroundColor(.red)
                                
                            
                            Text(String(format: "%.1f", totalMiles))
                                .font(.system(size: 72, weight: .heavy, design: .default))
                                .fontWidth(.condensed)
                                .foregroundColor(.red)
                        }
                        
                        Text("lifetime miles")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(isDarkMode ? .white.opacity(0.7) : .black.opacity(0.6))
                    }
                    
                    // Fun facts with glass effect
                    VStack(spacing: 12) {
                        let marathons = totalMiles / 26.2
                        GlassStatRow(icon: "flag.fill", text: "\(String(format: "%.1f", marathons)) marathons", color: .red, isDarkMode: isDarkMode)
                        
                        let avgPerDay = totalMiles / Double(max(streak, 1))
                        GlassStatRow(icon: "chart.line.uptrend.xyaxis", text: "\(String(format: "%.2f", avgPerDay)) mi/day avg", color: .red, isDarkMode: isDarkMode)
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.red.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.red.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                
                // Branding footer
                MADBrandingFooter(isDarkMode: isDarkMode)
            }
            .padding(16)
        }
        .frame(width: 280)
        
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
    
    private var paceString: String {
        let minutes = Int(fastestPace)
        let seconds = Int((fastestPace - Double(minutes)) * 60)
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var body: some View {
        ZStack {
            // Sticker background (compact, high-contrast)
            StickerBackground(accentColor: .cyan, isDarkMode: isDarkMode)
            
            VStack(spacing: 12) {
                // Main content
                VStack(spacing: 20) {
                    Text("MY STATS")
                        .font(.system(size: 16, weight: .semibold, design: .default))
                        .fontWidth(.condensed)
                        .foregroundColor(isDarkMode ? .white : .black)
                    
                    // Stats grid with glass effect
                    VStack(spacing: 16) {
                        GlassStatRow(icon: "flame.fill", text: "\(streak) Day Streak", color: .orange, isDarkMode: isDarkMode)
                        GlassStatRow(icon: "figure.run", text: "\(String(format: "%.2f", currentDistance)) mi Today", color: .blue, isDarkMode: isDarkMode)
                        GlassStatRow(icon: "map.fill", text: "\(String(format: "%.1f", totalMiles)) mi Total", color: .red, isDarkMode: isDarkMode)
                        GlassStatRow(icon: "hare.fill", text: "\(paceString) /mi Best", color: .green, isDarkMode: isDarkMode)
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.cyan.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.cyan.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                
                // Branding footer
                MADBrandingFooter(isDarkMode: isDarkMode)
            }
            .padding(16)
        }
        .frame(width: 280)
        
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
    
    var body: some View {
        ZStack {
            // Sticker background (compact, high-contrast)
            StickerBackground(accentColor: config.color, isDarkMode: isDarkMode)
            
            VStack(spacing: 12) {
                // Main content
                VStack(spacing: 20) {
                    Text(config.name.uppercased())
                        .font(.system(size: 16, weight: .semibold, design: .default))
                        .fontWidth(.condensed)
                        .foregroundColor(isDarkMode ? .white : .black)
                    
                    VStack(spacing: 16) {
                        ForEach(config.elements, id: \.self) { element in
                            elementView(for: element)
                        }
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(config.color.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(config.color.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                
                // Branding footer
                MADBrandingFooter(isDarkMode: isDarkMode)
            }
            .padding(16)
        }
        .frame(width: 280)
        
    }
    
    @ViewBuilder
    private func elementView(for element: ShareCardElement) -> some View {
        switch element {
        case .streak:
            GlassStatRow(icon: element.icon, text: "\(user.streak) Day Streak", color: element.color, isDarkMode: isDarkMode)
        case .todaysDistance:
            GlassStatRow(icon: element.icon, text: "\(String(format: "%.2f", currentDistance)) mi Today", color: element.color, isDarkMode: isDarkMode)
        case .todaysProgress:
            GlassStatRow(icon: element.icon, text: "\(Int(progress * 100))% Complete", color: element.color, isDarkMode: isDarkMode)
        case .goalStatus:
            if isGoalCompleted {
                GlassStatRow(icon: element.icon, text: "Goal Completed!", color: .green, isDarkMode: isDarkMode)
            }
        case .fastestPace:
            let minutes = Int(fastestPace)
            let seconds = Int((fastestPace - Double(minutes)) * 60)
            let paceStr = String(format: "%d:%02d", minutes, seconds)
            GlassStatRow(icon: element.icon, text: "\(paceStr) /mi Best", color: element.color, isDarkMode: isDarkMode)
        case .mostMiles:
            GlassStatRow(icon: element.icon, text: "\(String(format: "%.2f", mostMiles)) mi Record", color: element.color, isDarkMode: isDarkMode)
        case .totalMiles:
            GlassStatRow(icon: element.icon, text: "\(String(format: "%.1f", totalMiles)) mi Total", color: element.color, isDarkMode: isDarkMode)
        case .averagePerDay:
            let avg = totalMiles / Double(max(user.streak, 1))
            GlassStatRow(icon: element.icon, text: "\(String(format: "%.2f", avg)) mi/day avg", color: element.color, isDarkMode: isDarkMode)
        case .marathonEquivalent:
            let marathons = totalMiles / 26.2
            GlassStatRow(icon: element.icon, text: "\(String(format: "%.1f", marathons)) marathons", color: element.color, isDarkMode: isDarkMode)
        }
    }
}

// MARK: - Helper Views

struct StatRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(color)
                .frame(width: 24)
            Text(text)
                .font(.callout)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            Spacer()
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
            GeometryReader { geometry in
                if geometry.size.width > 700 {
                    // iPad/Large screen: Side-by-side
                    HStack(spacing: 0) {
                        // Left: Form
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                formContent
                            }
                            .padding()
                        }
                        .frame(width: geometry.size.width * 0.5)
                        
                        Divider()
                        
                        // Right: Live Preview
                        ScrollView {
                            VStack {
                                Text("Live Preview")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                    .padding(.top)
                                
                                livePreview
                                    .scaleEffect(0.6)
                            }
                        }
                        .frame(width: geometry.size.width * 0.5)
                        .background(Color.secondary.opacity(0.05))
                    }
                } else {
                    // iPhone: Stacked with live preview at top
                    ScrollView {
                        VStack(spacing: 20) {
                            // Live Preview (always visible on iPhone)
                            VStack {
                                Text("Live Preview")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                livePreview
                                    .scaleEffect(0.45)
                                    .frame(height: 200)
                            }
                            .padding(.vertical, 10)
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(12)
                            
                            Divider()
                            
                            // Form content
                            formContent
                        }
                        .padding()
                    }
                }
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
        VStack(alignment: .leading, spacing: 20) {
            // Card Name
            VStack(alignment: .leading, spacing: 8) {
                Text("Card Name")
                    .font(.headline)
                TextField("Enter name", text: $cardName)
                    .textFieldStyle(.roundedBorder)
            }
            
            // Select Elements
            VStack(alignment: .leading, spacing: 12) {
                Text("Select Elements")
                    .font(.headline)
                
                ForEach(ShareCardElement.allCases) { element in
                    Button {
                        if selectedElements.contains(element) {
                            selectedElements.remove(element)
                        } else {
                            selectedElements.insert(element)
                        }
                    } label: {
                        HStack {
                            Image(systemName: element.icon)
                                .foregroundColor(element.color)
                                .frame(width: 24)
                            Text(element.rawValue)
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedElements.contains(element) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(selectedElements.contains(element) ? element.color.opacity(0.1) : Color.clear)
                        .cornerRadius(8)
                    }
                }
            }
            
            // Accent Color
            VStack(alignment: .leading, spacing: 8) {
                Text("Accent Color")
                    .font(.headline)
                ColorPicker("Choose color", selection: $selectedColor)
            }
            
            // Default toggle
            Toggle("Set as default card", isOn: $isDefault)
                .padding(.vertical, 8)
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
