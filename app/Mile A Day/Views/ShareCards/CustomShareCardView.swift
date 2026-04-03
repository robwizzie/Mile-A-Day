//
//  CustomShareCardView.swift
//  Mile A Day
//
//  Custom share card view and builder extracted from ShareCardsView.swift
//

import SwiftUI
import HealthKit

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

    // Dynamic sizing based on element count
    private var elementSpacing: CGFloat {
        config.elements.count > 5 ? 12 : 20
    }

    private var titleSize: CGFloat {
        config.elements.count > 6 ? 26 : 32
    }

    private var elementFontSize: CGFloat {
        config.elements.count > 6 ? 17 : 20
    }

    private var elementIconSize: CGFloat {
        config.elements.count > 6 ? 17 : 20
    }

    private var logoSize: CGFloat {
        config.elements.count > 5 ? 100 : 140
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

                // Custom content - centered with adaptive sizing
                VStack(spacing: config.elements.count > 5 ? 16 : 24) {
                    Text(config.name.uppercased())
                        .font(.system(size: titleSize, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    VStack(spacing: elementSpacing) {
                        ForEach(config.elements, id: \.self) { element in
                            elementView(for: element)
                        }
                    }
                }

                Spacer()

                // MAD icon and slogan at bottom
                VStack(spacing: 6) {
                    Image("mad-logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: logoSize, height: logoSize)
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
                    .font(.system(size: elementIconSize))
                    .foregroundColor(element.color)
                Text("\(user.streak) Day Streak")
                    .font(.system(size: elementFontSize, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
            }
        case .todaysDistance:
            HStack(spacing: 12) {
                Image(systemName: element.icon)
                    .font(.system(size: elementIconSize))
                    .foregroundColor(element.color)
                Text("\(String(format: "%.2f", currentDistance)) mi Today")
                    .font(.system(size: elementFontSize, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
            }
        case .todaysProgress:
            HStack(spacing: 12) {
                Image(systemName: element.icon)
                    .font(.system(size: elementIconSize))
                    .foregroundColor(element.color)
                Text("\(Int(progress * 100))% Complete")
                    .font(.system(size: elementFontSize, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
            }
        case .goalStatus:
            if isGoalCompleted {
                HStack(spacing: 12) {
                    Image(systemName: element.icon)
                        .font(.system(size: elementIconSize))
                        .foregroundColor(.green)
                    Text("Goal Completed!")
                        .font(.system(size: elementFontSize, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                }
            }
        case .fastestPace:
            let minutes = Int(fastestPace)
            let seconds = Int((fastestPace - Double(minutes)) * 60)
            let paceStr = String(format: "%d:%02d", minutes, seconds)
            HStack(spacing: 12) {
                Image(systemName: element.icon)
                    .font(.system(size: elementIconSize))
                    .foregroundColor(element.color)
                Text("\(paceStr) /mi Best")
                    .font(.system(size: elementFontSize, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
            }
        case .mostMiles:
            HStack(spacing: 12) {
                Image(systemName: element.icon)
                    .font(.system(size: elementIconSize))
                    .foregroundColor(element.color)
                Text("\(String(format: "%.2f", mostMiles)) mi Record")
                    .font(.system(size: elementFontSize, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
            }
        case .totalMiles:
            HStack(spacing: 12) {
                Image(systemName: element.icon)
                    .font(.system(size: elementIconSize))
                    .foregroundColor(element.color)
                Text("\(String(format: "%.1f", totalMiles)) mi Total")
                    .font(.system(size: elementFontSize, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
            }
        case .averagePerDay:
            let avg = totalMiles / Double(max(user.streak, 1))
            HStack(spacing: 12) {
                Image(systemName: element.icon)
                    .font(.system(size: elementIconSize))
                    .foregroundColor(element.color)
                Text("\(String(format: "%.2f", avg)) mi/day avg")
                    .font(.system(size: elementFontSize, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
            }
        case .marathonEquivalent:
            let marathons = totalMiles / 26.2
            HStack(spacing: 12) {
                Image(systemName: element.icon)
                    .font(.system(size: elementIconSize))
                    .foregroundColor(element.color)
                Text("\(String(format: "%.1f", marathons)) marathons")
                    .font(.system(size: elementFontSize, weight: .medium, design: .rounded))
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
