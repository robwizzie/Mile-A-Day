//
//  CustomShareCard.swift
//  Mile A Day
//
//  Custom share card configuration model
//

import Foundation
import SwiftUI

// MARK: - Card Element Types

enum ShareCardElement: String, CaseIterable, Identifiable, Codable {
    case streak = "Streak"
    case todaysDistance = "Today's Distance"
    case todaysProgress = "Today's Progress"
    case goalStatus = "Goal Status"
    case fastestPace = "Fastest Pace"
    case mostMiles = "Most Miles"
    case totalMiles = "Total Miles"
    case averagePerDay = "Average Per Day"
    case marathonEquivalent = "Marathon Equivalent"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .streak: return "flame.fill"
        case .todaysDistance: return "figure.run"
        case .todaysProgress: return "chart.bar.fill"
        case .goalStatus: return "checkmark.circle.fill"
        case .fastestPace: return "hare.fill"
        case .mostMiles: return "star.fill"
        case .totalMiles: return "map.fill"
        case .averagePerDay: return "chart.line.uptrend.xyaxis"
        case .marathonEquivalent: return "flag.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .streak: return .orange
        case .todaysDistance, .todaysProgress, .goalStatus: return .blue
        case .fastestPace: return .green
        case .mostMiles: return .purple
        case .totalMiles, .averagePerDay, .marathonEquivalent: return .red
        }
    }
}

// MARK: - Custom Card Configuration

struct CustomShareCardConfig: Codable, Identifiable {
    var id: UUID
    var name: String
    var elements: [ShareCardElement]
    var accentColor: String // Hex color
    var isDefault: Bool
    
    init(id: UUID = UUID(), name: String, elements: [ShareCardElement], accentColor: String = "#FF6B35", isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.elements = elements
        self.accentColor = accentColor
        self.isDefault = isDefault
    }
    
    var color: Color {
        colorFromHex(accentColor)
    }
    
    private func colorFromHex(_ hex: String) -> Color {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        
        return Color(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Default Configurations

extension CustomShareCardConfig {
    static let presets: [CustomShareCardConfig] = [
        CustomShareCardConfig(
            name: "Quick Update",
            elements: [.streak, .todaysDistance, .goalStatus],
            accentColor: "#FF6B35"
        ),
        CustomShareCardConfig(
            name: "Personal Records",
            elements: [.fastestPace, .mostMiles, .streak],
            accentColor: "#4ECDC4"
        ),
        CustomShareCardConfig(
            name: "Full Stats",
            elements: [.streak, .todaysDistance, .totalMiles, .fastestPace],
            accentColor: "#95E1D3"
        ),
        CustomShareCardConfig(
            name: "Achievement",
            elements: [.totalMiles, .marathonEquivalent, .averagePerDay],
            accentColor: "#F38181"
        )
    ]
}

// MARK: - UserDefaults Storage

extension CustomShareCardConfig {
    static let storageKey = "customShareCards"
    
    static func loadSavedCards() -> [CustomShareCardConfig] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let cards = try? JSONDecoder().decode([CustomShareCardConfig].self, from: data) else {
            return []
        }
        return cards
    }
    
    static func saveCards(_ cards: [CustomShareCardConfig]) {
        if let data = try? JSONEncoder().encode(cards) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    static func getDefaultCard() -> CustomShareCardConfig? {
        return loadSavedCards().first(where: { $0.isDefault })
    }
}

