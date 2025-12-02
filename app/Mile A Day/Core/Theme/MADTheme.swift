import SwiftUI

/// MAD App Theme System
/// Based on the red, black, and white color scheme from the MAD logo
struct MADTheme {
    
    // MARK: - Colors
    struct Colors {
        // Primary brand colors from MAD logo
        static let madRed = Color(red: 0.85, green: 0.25, blue: 0.35) // Deep red from logo
        static let madBlack = Color(red: 0.1, green: 0.1, blue: 0.1) // Rich black
        static let madWhite = Color.white

        // Aliases for consistency
        static let primary = madRed

        // Gradient variations for visual interest
        static let redGradient = LinearGradient(
            colors: [
                Color(red: 0.9, green: 0.3, blue: 0.4),
                Color(red: 0.7, green: 0.2, blue: 0.3)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let primaryGradient = redGradient

        static let blackGradient = LinearGradient(
            colors: [
                Color(red: 0.15, green: 0.15, blue: 0.15),
                Color(red: 0.05, green: 0.05, blue: 0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        // App-wide gradient background (mostly black with slight red accents)
        static let appBackgroundGradient = LinearGradient(
            colors: [
                Color(red: 0.15, green: 0.08, blue: 0.1),   // Top: dark with slight red tint
                Color(red: 0.12, green: 0.06, blue: 0.08),   // Mid-top: darker
                Color(red: 0.08, green: 0.04, blue: 0.06),   // Mid-bottom: very dark
                Color(red: 0.05, green: 0.02, blue: 0.04)    // Bottom: almost black
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        // Text colors - adapt to dark mode
        static let primaryText = Color.primary
        static let secondaryText = Color.secondary
        static let inverseText = Color.white
        
        // Background colors - adapt to dark mode
        static let primaryBackground = Color(.systemBackground)
        static let secondaryBackground = Color(.systemGray6)
        static let cardBackground = Color(.systemBackground)
        
        // Interactive colors
        static let buttonPrimary = madRed
        static let buttonSecondary = madBlack
        static let buttonTertiary = Color(red: 0.95, green: 0.95, blue: 0.95)
        
        // Status colors
        static let success = Color(red: 0.2, green: 0.7, blue: 0.3)
        static let warning = Color(red: 1.0, green: 0.6, blue: 0.0)
        static let error = Color(red: 0.9, green: 0.2, blue: 0.2)
        
        // Shadow and overlay - adapt to dark mode
        static let shadow = Color.primary.opacity(0.1)
        static let overlay = Color.primary.opacity(0.3)
    }
    
    // MARK: - Typography
    struct Typography {
        // Headlines
        static let largeTitle = Font.system(size: 34, weight: .bold, design: .rounded)
        static let title1 = Font.system(size: 28, weight: .bold, design: .rounded)
        static let title2 = Font.system(size: 22, weight: .bold, design: .rounded)
        static let title3 = Font.system(size: 20, weight: .semibold, design: .rounded)
        
        // Body text
        static let headline = Font.system(size: 17, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 17, weight: .regular, design: .rounded)
        static let callout = Font.system(size: 16, weight: .regular, design: .rounded)
        static let subheadline = Font.system(size: 15, weight: .regular, design: .rounded)
        static let footnote = Font.system(size: 13, weight: .regular, design: .rounded)
        static let caption = Font.system(size: 12, weight: .regular, design: .rounded)
        
        // Custom weights
        static let bodyBold = Font.system(size: 17, weight: .semibold, design: .rounded)
        static let small = Font.system(size: 14, weight: .regular, design: .rounded)
        static let smallBold = Font.system(size: 14, weight: .semibold, design: .rounded)
    }
    
    // MARK: - Spacing
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let xxxl: CGFloat = 64
    }
    
    // MARK: - Corner Radius
    struct CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let extraLarge: CGFloat = 24
        static let pill: CGFloat = 50
    }
    
    // MARK: - Shadow
    struct Shadow {
        static let small = (color: Colors.shadow, radius: CGFloat(4), x: CGFloat(0), y: CGFloat(2))
        static let medium = (color: Colors.shadow, radius: CGFloat(8), x: CGFloat(0), y: CGFloat(4))
        static let large = (color: Colors.shadow, radius: CGFloat(16), x: CGFloat(0), y: CGFloat(8))
    }
    
    // MARK: - Animation
    struct Animation {
        static let quick = SwiftUI.Animation.easeInOut(duration: 0.2)
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.5)
        static let bounce = SwiftUI.Animation.spring(response: 0.6, dampingFraction: 0.8)
        static let splash = SwiftUI.Animation.spring(response: 1.2, dampingFraction: 0.7)
    }
}

// MARK: - Button Styles
struct MADPrimaryButtonStyle: ButtonStyle {
    let isFullWidth: Bool
    
    init(fullWidth: Bool = false) {
        self.isFullWidth = fullWidth
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MADTheme.Typography.headline)
            .foregroundColor(MADTheme.Colors.inverseText)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .padding(.horizontal, MADTheme.Spacing.lg)
            .padding(.vertical, MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(MADTheme.Colors.redGradient)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(MADTheme.Animation.quick, value: configuration.isPressed)
            .shadow(
                color: MADTheme.Shadow.medium.color,
                radius: MADTheme.Shadow.medium.radius,
                x: MADTheme.Shadow.medium.x,
                y: MADTheme.Shadow.medium.y
            )
    }
}

struct MADSecondaryButtonStyle: ButtonStyle {
    let isFullWidth: Bool
    
    init(fullWidth: Bool = false) {
        self.isFullWidth = fullWidth
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MADTheme.Typography.headline)
            .foregroundColor(MADTheme.Colors.primaryText)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .padding(.horizontal, MADTheme.Spacing.lg)
            .padding(.vertical, MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .stroke(MADTheme.Colors.madRed, lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .fill(MADTheme.Colors.cardBackground)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(MADTheme.Animation.quick, value: configuration.isPressed)
    }
}

struct MADTertiaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MADTheme.Typography.headline)
            .foregroundColor(MADTheme.Colors.madRed)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(MADTheme.Animation.quick, value: configuration.isPressed)
    }
}

// MARK: - Card Style
struct MADCardStyle: ViewModifier {
    let backgroundColor: Color
    let hasShadow: Bool
    
    init(backgroundColor: Color = MADTheme.Colors.cardBackground, hasShadow: Bool = true) {
        self.backgroundColor = backgroundColor
        self.hasShadow = hasShadow
    }
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(backgroundColor)
                    .shadow(
                        color: hasShadow ? MADTheme.Shadow.small.color : .clear,
                        radius: hasShadow ? MADTheme.Shadow.small.radius : 0,
                        x: hasShadow ? MADTheme.Shadow.small.x : 0,
                        y: hasShadow ? MADTheme.Shadow.small.y : 0
                    )
            )
    }
}

// MARK: - View Extensions
extension View {
    func madCard(backgroundColor: Color = MADTheme.Colors.cardBackground, hasShadow: Bool = true) -> some View {
        modifier(MADCardStyle(backgroundColor: backgroundColor, hasShadow: hasShadow))
    }
    
    func madPrimaryButton(fullWidth: Bool = false) -> some View {
        buttonStyle(MADPrimaryButtonStyle(fullWidth: fullWidth))
    }
    
    func madSecondaryButton(fullWidth: Bool = false) -> some View {
        buttonStyle(MADSecondaryButtonStyle(fullWidth: fullWidth))
    }
    
    func madTertiaryButton() -> some View {
        buttonStyle(MADTertiaryButtonStyle())
    }
}