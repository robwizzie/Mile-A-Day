//
//  ShareCardsView.swift
//  Mile A Day
//
//  Enhanced share card system with full customization
//

import SwiftUI
import HealthKit

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
                            .shadow(color: selectedCard.color.opacity(0.4), radius: 20, x: 0, y: 10)
                            .shadow(color: selectedCard.color.opacity(0.2), radius: 40, x: 0, y: 20)
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
                        .tint(showingCopiedFeedback ? .green : .blue)
                        
                        Button {
                            if let image = generatedImage {
                                showingShareSheet = true
                            }
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
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
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .font(.subheadline)
                    .foregroundColor(.orange)
                Text("Mile A Day")
                    .font(.subheadline)
                    .fontWeight(.bold)
            }
            
            // Main content
            VStack(spacing: 8) {
                Text("\(streak)")
                    .font(.system(size: 70, weight: .bold, design: .rounded))
                    .foregroundColor(.orange)
                
                Text("Day Streak")
                    .font(.callout)
                    .fontWeight(.semibold)
                
                if isActiveToday {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                        Text("Active Today!")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(10)
                } else if isAtRisk {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.red)
                        Text("At Risk")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.15))
                    .cornerRadius(10)
                }
            }
            
            // Footer
            Text("Keep the streak alive!")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .orange.opacity(0.4), radius: 20, x: 0, y: 8)
        .shadow(color: .orange.opacity(0.2), radius: 40, x: 0, y: 16)
    }
}

struct TodaysProgressShareCard: View {
    let currentDistance: Double
    let goalDistance: Double
    let progress: Double
    let didComplete: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack(spacing: 5) {
                Image(systemName: "figure.run")
                    .font(.subheadline)
                    .foregroundColor(.blue)
                Text("Mile A Day")
                    .font(.subheadline)
                    .fontWeight(.bold)
            }
            
            // Main content
            VStack(spacing: 8) {
                Text("Today's Progress")
                    .font(.caption)
                    .fontWeight(.semibold)
                
                // Distance
                Text(String(format: "%.2f", currentDistance))
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundColor(.blue)
                + Text(" / \(String(format: "%.1f", goalDistance))")
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                
                Text("miles")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 10)
                        
                        RoundedRectangle(cornerRadius: 6)
                            .fill(didComplete ? Color.green : Color.blue)
                            .frame(width: geometry.size.width * progress, height: 10)
                    }
                }
                .frame(height: 10)
                .padding(.horizontal, 12)
                
                // Status
                if didComplete {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                        Text("Goal Completed! 🎉")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(10)
                } else {
                    Text("\(Int(progress * 100))% Complete")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
            }
            
            // Footer
            Text("One mile at a time")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .blue.opacity(0.4), radius: 20, x: 0, y: 8)
        .shadow(color: .blue.opacity(0.2), radius: 40, x: 0, y: 16)
    }
}

struct FastestPaceShareCard: View {
    let fastestPace: TimeInterval
    
    private var paceString: String {
        let minutes = Int(fastestPace)
        let seconds = Int((fastestPace - Double(minutes)) * 60)
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "hare.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                Text("Mile A Day")
                    .font(.title3)
                    .fontWeight(.bold)
            }
            
            // Main content
            VStack(spacing: 12) {
                Text("Fastest Mile")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text(paceString)
                    .font(.system(size: 90, weight: .bold, design: .rounded))
                    .foregroundColor(.green)
                
                Text("per mile")
                    .font(.title2)
                    .foregroundColor(.secondary)
                
                let mph = 60.0 / fastestPace
                Text(String(format: "%.1f mph", mph))
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(16)
            }
            
            // Footer
            Text("Personal Record")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .frame(width: 400, height: 600)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(.systemBackground))
                .shadow(color: .green.opacity(0.3), radius: 30, x: 0, y: 15)
        )
    }
}

struct MostMilesShareCard: View {
    let mostMiles: Double
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .font(.title2)
                    .foregroundColor(.purple)
                Text("Mile A Day")
                    .font(.title3)
                    .fontWeight(.bold)
            }
            
            // Main content
            VStack(spacing: 12) {
                Text("Most Miles")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("in a Single Day")
                    .font(.callout)
                    .foregroundColor(.secondary)
                
                Text(String(format: "%.2f", mostMiles))
                    .font(.system(size: 90, weight: .bold, design: .rounded))
                    .foregroundColor(.purple)
                
                Text("miles")
                    .font(.title2)
                    .foregroundColor(.secondary)
                
                let hours = mostMiles / 3.5
                Text("~\(String(format: "%.1f", hours)) hours of running")
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(.purple)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Color.purple.opacity(0.15))
                    .cornerRadius(16)
            }
            
            // Footer
            Text("Daily Record")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .frame(width: 400, height: 600)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(.systemBackground))
                .shadow(color: .purple.opacity(0.3), radius: 30, x: 0, y: 15)
        )
    }
}

struct TotalMilesShareCard: View {
    let totalMiles: Double
    let streak: Int
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "map.fill")
                    .font(.title2)
                    .foregroundColor(.red)
                Text("Mile A Day")
                    .font(.title3)
                    .fontWeight(.bold)
            }
            
            // Main content
            VStack(spacing: 12) {
                Text("Total Distance")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text(String(format: "%.1f", totalMiles))
                    .font(.system(size: 80, weight: .bold, design: .rounded))
                    .foregroundColor(.red)
                
                Text("lifetime miles")
                    .font(.callout)
                    .foregroundColor(.secondary)
                
                // Fun facts
                VStack(spacing: 10) {
                    let marathons = totalMiles / 26.2
                    StatRow(icon: "flag.fill", text: "\(String(format: "%.1f", marathons)) marathons", color: .red)
                    
                    let avgPerDay = totalMiles / Double(max(streak, 1))
                    StatRow(icon: "chart.line.uptrend.xyaxis", text: "\(String(format: "%.2f", avgPerDay)) mi/day avg", color: .red)
                }
                .padding(16)
                .background(Color.red.opacity(0.1))
                .cornerRadius(16)
            }
            
            // Footer
            Text("Keep moving forward!")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .frame(width: 400, height: 600)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(.systemBackground))
                .shadow(color: .red.opacity(0.3), radius: 30, x: 0, y: 15)
        )
    }
}

struct WeekSummaryShareCard: View {
    let currentDistance: Double
    let totalMiles: Double
    let streak: Int
    let fastestPace: TimeInterval
    
    private var paceString: String {
        let minutes = Int(fastestPace)
        let seconds = Int((fastestPace - Double(minutes)) * 60)
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title2)
                    .foregroundColor(.cyan)
                Text("Mile A Day")
                    .font(.title3)
                    .fontWeight(.bold)
            }
            
            // Main content
            VStack(spacing: 16) {
                Text("My Stats")
                    .font(.title2)
                    .fontWeight(.bold)
                
                // Stats grid
                VStack(spacing: 12) {
                    StatRow(icon: "flame.fill", text: "\(streak) Day Streak", color: .orange)
                    StatRow(icon: "figure.run", text: "\(String(format: "%.2f", currentDistance)) mi Today", color: .blue)
                    StatRow(icon: "map.fill", text: "\(String(format: "%.1f", totalMiles)) mi Total", color: .red)
                    StatRow(icon: "hare.fill", text: "\(paceString) /mi Best", color: .green)
                }
                .padding(20)
                .background(Color.cyan.opacity(0.1))
                .cornerRadius(16)
            }
            
            // Footer
            Text("Powered by consistency")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .frame(width: 400, height: 600)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(.systemBackground))
                .shadow(color: .cyan.opacity(0.3), radius: 30, x: 0, y: 15)
        )
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
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "star.circle.fill")
                    .font(.title2)
                    .foregroundColor(config.color)
                Text("Mile A Day")
                    .font(.title3)
                    .fontWeight(.bold)
            }
            
            // Main content
            VStack(spacing: 16) {
                Text(config.name)
                    .font(.title3)
                    .fontWeight(.bold)
                
                VStack(spacing: 12) {
                    ForEach(config.elements, id: \.self) { element in
                        elementView(for: element)
                    }
                }
                .padding(20)
                .background(config.color.opacity(0.1))
                .cornerRadius(16)
            }
            
            // Footer
            Text("Custom card")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .frame(width: 400, height: 600)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(.systemBackground))
                .shadow(color: config.color.opacity(0.3), radius: 30, x: 0, y: 15)
        )
    }
    
    @ViewBuilder
    private func elementView(for element: ShareCardElement) -> some View {
        switch element {
        case .streak:
            StatRow(icon: element.icon, text: "\(user.streak) Day Streak", color: element.color)
        case .todaysDistance:
            StatRow(icon: element.icon, text: "\(String(format: "%.2f", currentDistance)) mi Today", color: element.color)
        case .todaysProgress:
            StatRow(icon: element.icon, text: "\(Int(progress * 100))% Complete", color: element.color)
        case .goalStatus:
            if isGoalCompleted {
                StatRow(icon: element.icon, text: "Goal Completed!", color: .green)
            }
        case .fastestPace:
            let minutes = Int(fastestPace)
            let seconds = Int((fastestPace - Double(minutes)) * 60)
            let paceStr = String(format: "%d:%02d", minutes, seconds)
            StatRow(icon: element.icon, text: "\(paceStr) /mi Best", color: element.color)
        case .mostMiles:
            StatRow(icon: element.icon, text: "\(String(format: "%.2f", mostMiles)) mi Record", color: element.color)
        case .totalMiles:
            StatRow(icon: element.icon, text: "\(String(format: "%.1f", totalMiles)) mi Total", color: element.color)
        case .averagePerDay:
            let avg = totalMiles / Double(max(user.streak, 1))
            StatRow(icon: element.icon, text: "\(String(format: "%.2f", avg)) mi/day avg", color: element.color)
        case .marathonEquivalent:
            let marathons = totalMiles / 26.2
            StatRow(icon: element.icon, text: "\(String(format: "%.1f", marathons)) marathons", color: element.color)
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
