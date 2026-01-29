//
//  BadgeDetailView.swift
//  Mile A Day
//

import SwiftUI

struct BadgeDetailView: View {
    let badge: Badge
    var userManager: UserManager?
    @Environment(\.dismiss) private var dismiss
    
    // Animation states
    @State private var showMedal = false
    @State private var showContent = false
    @State private var shimmerOffset: CGFloat = -300
    @State private var glowPulse = false
    @State private var ribbonDrop = false
    
    var body: some View {
        ZStack {
            // Background
            backgroundGradient
            
            // Ambient glow
            if !badge.isLocked {
                ambientGlow
            }
            
            VStack(spacing: 0) {
                // Close button
                closeButton
                
                Spacer()
                
                // Medal display
                medalSection
                    .scaleEffect(showMedal ? 1 : 0.5)
                    .opacity(showMedal ? 1 : 0)
                
                Spacer()
                    .frame(height: 40)
                
                // Details section
                detailsSection
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 30)
                
                Spacer()
            }
        }
        .onAppear {
            startAnimations()
        }
    }
    
    // MARK: - Background
    
    private var backgroundGradient: some View {
        ZStack {
            // Base gradient
            LinearGradient(
                colors: badge.isLocked ? [
                    Color(red: 0.08, green: 0.08, blue: 0.1),
                    Color(red: 0.04, green: 0.04, blue: 0.06)
                ] : backgroundColors,
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Radial accent
            if !badge.isLocked {
                RadialGradient(
                    colors: [
                        badge.rarity.color.opacity(0.15),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 50,
                    endRadius: 350
                )
                .offset(y: -100)
            }
        }
        .ignoresSafeArea()
    }
    
    private var backgroundColors: [Color] {
        switch badge.rarity {
        case .legendary:
            return [
                Color(red: 0.15, green: 0.1, blue: 0.02),
                Color(red: 0.06, green: 0.04, blue: 0.01)
            ]
        case .rare:
            return [
                Color(red: 0.1, green: 0.06, blue: 0.15),
                Color(red: 0.04, green: 0.02, blue: 0.06)
            ]
        case .common:
            return [
                Color(red: 0.06, green: 0.08, blue: 0.14),
                Color(red: 0.02, green: 0.04, blue: 0.08)
            ]
        }
    }
    
    private var ambientGlow: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        badge.rarity.color.opacity(glowPulse ? 0.35 : 0.2),
                        badge.rarity.color.opacity(0)
                    ],
                    center: .center,
                    startRadius: 60,
                    endRadius: glowPulse ? 200 : 160
                )
            )
            .frame(width: 400, height: 400)
            .offset(y: -50)
            .allowsHitTesting(false)
    }
    
    // MARK: - Close Button
    
    private var closeButton: some View {
        HStack {
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.1))
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
    
    // MARK: - Medal Section
    
    private var medalSection: some View {
        VStack(spacing: 0) {
            // Ribbon
            ribbonView
                .opacity(ribbonDrop ? 1 : 0)
                .offset(y: ribbonDrop ? 0 : -30)
            
            // Medal
            ZStack {
                // Outer glow rings
                if !badge.isLocked {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(badge.rarity.color.opacity(0.15 - Double(i) * 0.04), lineWidth: 1)
                            .frame(width: 180 + CGFloat(i * 30), height: 180 + CGFloat(i * 30))
                    }
                }
                
                // Main medal circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: badge.isLocked ? [
                                Color(white: 0.3),
                                Color(white: 0.18)
                            ] : medalGradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 150, height: 150)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: badge.isLocked ? [
                                        Color.white.opacity(0.15),
                                        Color.white.opacity(0.05)
                                    ] : [
                                        Color.white.opacity(0.6),
                                        badge.rarity.color.opacity(0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                    )
                    .shadow(
                        color: badge.isLocked ? .black.opacity(0.3) : badge.rarity.color.opacity(0.5),
                        radius: 25,
                        x: 0,
                        y: 15
                    )
                
                // Inner decorative ring
                Circle()
                    .stroke(Color.white.opacity(badge.isLocked ? 0.1 : 0.25), lineWidth: 2)
                    .frame(width: 120, height: 120)
                
                // Icon
                if badge.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 45, weight: .medium))
                        .foregroundColor(.white.opacity(0.35))
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: 55, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.85)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 3)
                }
                
                // Shimmer effect
                if !badge.isLocked {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.3), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 150, height: 150)
                        .offset(x: shimmerOffset)
                        .clipShape(Circle())
                }
            }
            .offset(y: -15)
        }
    }
    
    private var ribbonView: some View {
        VStack(spacing: 0) {
            // Ribbon top
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: badge.isLocked ? [
                            Color.gray,
                            Color.gray.opacity(0.7)
                        ] : [
                            badge.rarity.color,
                            badge.rarity.color.opacity(0.8)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 40, height: 50)
            
            // Ribbon bottom tails
            HStack(spacing: 0) {
                RibbonTail(isLeft: true, color: badge.isLocked ? .gray : badge.rarity.color)
                RibbonTail(isLeft: false, color: badge.isLocked ? .gray : badge.rarity.color)
            }
            .frame(width: 40)
        }
        .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 3)
    }
    
    private var medalGradientColors: [Color] {
        switch badge.rarity {
        case .legendary:
            return [
                Color(red: 1.0, green: 0.88, blue: 0.45),
                Color(red: 0.9, green: 0.6, blue: 0.18)
            ]
        case .rare:
            return [
                Color(red: 0.75, green: 0.55, blue: 0.95),
                Color(red: 0.55, green: 0.35, blue: 0.8)
            ]
        case .common:
            return [
                Color(red: 0.5, green: 0.7, blue: 1.0),
                Color(red: 0.35, green: 0.55, blue: 0.85)
            ]
        }
    }
    
    private var iconName: String {
        if badge.id.hasPrefix("streak_") || badge.id.hasPrefix("consistency_") { return "flame.fill" }
        if badge.id.hasPrefix("miles_") { return "figure.run" }
        if badge.id.hasPrefix("pace_") { return "bolt.fill" }
        if badge.id.hasPrefix("daily_") { return "figure.run.circle.fill" }
        if badge.id.hasPrefix("hidden_") || badge.id.hasPrefix("secret_") || badge.id.hasPrefix("special_") { return "sparkles" }
        return "star.fill"
    }
    
    // MARK: - Details Section
    
    private var detailsSection: some View {
        VStack(spacing: 20) {
            // Status pill
            statusPill
            
            // Name
            Text(badge.name)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
            // Content based on state
            if badge.isLocked && badge.isHidden {
                mysteryContent
            } else if badge.isLocked {
                lockedContent
            } else {
                unlockedContent
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 60)
    }
    
    private var statusPill: some View {
        HStack(spacing: 8) {
            if badge.isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                Text("LOCKED")
            } else if badge.isHidden {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 11))
                Text("SECRET UNLOCKED")
            } else {
                Circle()
                    .fill(badge.rarity.color)
                    .frame(width: 10, height: 10)
                Text(badge.rarity.rawValue.uppercased())
            }
        }
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .tracking(1.5)
        .foregroundColor(badge.isLocked ? .gray : (badge.isHidden ? .purple : badge.rarity.color))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(
                    (badge.isLocked ? Color.gray : (badge.isHidden ? Color.purple : badge.rarity.color))
                        .opacity(0.15)
                )
                .overlay(
                    Capsule()
                        .stroke(
                            (badge.isLocked ? Color.gray : (badge.isHidden ? Color.purple : badge.rarity.color))
                                .opacity(0.3),
                            lineWidth: 1
                        )
                )
        )
    }
    
    private var mysteryContent: some View {
        VStack(spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.diamond.fill")
                    .font(.system(size: 14))
                Text("Mystery Badge")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .foregroundColor(.purple)
            
            Text("This badge is shrouded in mystery.\nKeep running to discover its secret!")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.purple.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private var lockedContent: some View {
        VStack(spacing: 20) {
            Text(badge.description)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            
            // Your progress (when we have user stats)
            if let um = userManager {
                lockedProgressCard(user: um.currentUser)
            }
            
            // How to unlock card
            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 12))
                    Text("HOW TO UNLOCK")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .tracking(1.5)
                }
                .foregroundColor(.orange)
                
                Text(getUnlockText())
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.orange.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                    )
            )
        }
    }
    
    // MARK: - Locked Progress Card
    
    @ViewBuilder
    private func lockedProgressCard(user: User) -> some View {
        let id = badge.id
        if badge.isHidden {
            EmptyView()
        } else if (id.hasPrefix("streak_") || id.hasPrefix("consistency_")), let target = getNumber(from: id) {
            let current = user.streak
            let progress = target > 0 ? min(Double(current) / Double(target), 1.0) : 0
            let need = max(0, target - current)
            progressBlock(
                icon: "flame.fill",
                title: "Your progress",
                primary: "Your streak: \(current) day\(current == 1 ? "" : "s")",
                secondary: "Need: \(target) days",
                delta: need > 0 ? "\(need) more day\(need == 1 ? "" : "s") to go" : "Unlock by maintaining your streak!",
                progress: progress,
                useBar: true
            )
        } else if id.hasPrefix("miles_"), let target = getNumber(from: id) {
            let targetD = Double(target)
            let current = user.totalMiles
            let progress = targetD > 0 ? min(current / targetD, 1.0) : 0
            let need = max(0, targetD - current)
            progressBlock(
                icon: "figure.run",
                title: "Your progress",
                primary: "You've run \(String(format: "%.1f", current)) mi",
                secondary: "Need: \(target) mi total",
                delta: need > 0 ? "\(String(format: "%.1f", need)) more miles to go" : "Keep running to lock it in!",
                progress: progress,
                useBar: true
            )
        } else if id.hasPrefix("pace_"), let targetMin = getNumber(from: id) {
            let targetD = Double(targetMin)
            let current = user.fastestMilePace
            if current <= 0 {
                progressBlock(
                    icon: "bolt.fill",
                    title: "Your progress",
                    primary: "No mile pace recorded yet",
                    secondary: "Need: sub-\(targetMin):00 /mi",
                    delta: "Run a timed mile to see how close you are",
                    progress: 0,
                    useBar: false
                )
            } else {
                let needMin = current - targetD
                let needSec = Int(needMin * 60)
                let m = needSec / 60
                let s = needSec % 60
                let deltaStr = needMin > 0
                    ? "\(m):\(String(format: "%02d", s)) faster per mile needed"
                    : "You've hit the pace — complete a sub-\(targetMin):00 mile to unlock!"
                let progress = targetD > 0 && current >= targetD ? min(targetD / current, 1.0) : 0
                progressBlock(
                    icon: "bolt.fill",
                    title: "Your progress",
                    primary: "Your best mile: \(current.paceFormatted) /mi",
                    secondary: "Need: sub-\(targetMin):00 /mi",
                    delta: deltaStr,
                    progress: progress,
                    useBar: false
                )
            }
        } else if id.hasPrefix("daily_"), let target = dailyTargetMiles(for: id) {
            let current = user.mostMilesInOneDay
            let progress = target > 0 ? min(current / target, 1.0) : 0
            let need = max(0, target - current)
            let targetStr = dailyTargetLabel(for: id)
            progressBlock(
                icon: "figure.run.circle.fill",
                title: "Your progress",
                primary: "Your best day: \(String(format: "%.1f", current)) mi",
                secondary: "Need: \(targetStr)",
                delta: need > 0 ? "\(String(format: "%.1f", need)) more miles in a single run" : "Run \(targetStr) in one day to unlock!",
                progress: progress,
                useBar: true
            )
        } else {
            EmptyView()
        }
    }
    
    private func progressBlock(
        icon: String,
        title: String,
        primary: String,
        secondary: String,
        delta: String,
        progress: Double,
        useBar: Bool
    ) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(1.2)
            }
            .foregroundColor(.cyan)
            
            VStack(spacing: 8) {
                HStack {
                    Text(primary)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                    Text(secondary)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                if useBar {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.12))
                                .frame(height: 8)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [.cyan, .cyan.opacity(0.7)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, geo.size.width * progress), height: 8)
                        }
                    }
                    .frame(height: 8)
                }
                
                Text(delta)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.cyan.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.cyan.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }
    
    private func dailyTargetMiles(for id: String) -> Double? {
        switch id {
        case "daily_2": return 2
        case "daily_3": return 3.1
        case "daily_5": return 5
        case "daily_8": return 8
        case "daily_10": return 10
        case "daily_10k": return 6.2
        case "daily_half": return 13.1
        case "daily_15": return 15
        case "daily_20": return 20
        case "daily_marathon": return 26.2
        case "daily_50k": return 31
        case "daily_ultra": return 50
        default: return nil
        }
    }
    
    private func dailyTargetLabel(for id: String) -> String {
        switch id {
        case "daily_2": return "2+ mi"
        case "daily_3": return "5K (3.1 mi)"
        case "daily_5": return "5+ mi"
        case "daily_8": return "8+ mi"
        case "daily_10": return "10+ mi"
        case "daily_10k": return "10K (6.2 mi)"
        case "daily_half": return "half marathon (13.1 mi)"
        case "daily_15": return "15+ mi"
        case "daily_20": return "20+ mi"
        case "daily_marathon": return "marathon (26.2 mi)"
        case "daily_50k": return "50K (31 mi)"
        case "daily_ultra": return "50+ mi"
        default: return "?"
        }
    }
    
    private var unlockedContent: some View {
        VStack(spacing: 14) {
            Text(badge.description)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 12))
                Text("Earned \(badge.dateAwarded.formattedDate)")
            }
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundColor(.white.opacity(0.4))
        }
    }
    
    // MARK: - Unlock Text
    
    private func getUnlockText() -> String {
        let id = badge.id
        
        if id.hasPrefix("streak_") || id.hasPrefix("consistency_") {
            if let n = getNumber(from: id) { return "Maintain a \(n)-day running streak" }
        }
        if id.hasPrefix("miles_") {
            if let n = getNumber(from: id) { return "Run \(n) total miles" }
        }
        if id.hasPrefix("pace_") {
            if let n = getNumber(from: id) { return "Run a sub-\(n) minute mile" }
        }
        if id.hasPrefix("daily_") {
            switch id {
            case "daily_2": return "Run 2+ miles in a single day"
            case "daily_3": return "Run a 5K (3.1 mi) in one day"
            case "daily_5": return "Run 5+ miles in a single day"
            case "daily_10k": return "Run a 10K (6.2 mi) in one day"
            case "daily_8": return "Run 8+ miles in a single day"
            case "daily_10": return "Run 10+ miles in a single day"
            case "daily_half": return "Run a half marathon (13.1 mi)"
            case "daily_15": return "Run 15+ miles in a single day"
            case "daily_20": return "Run 20+ miles in a single day"
            case "daily_marathon": return "Run a marathon (26.2 mi)"
            case "daily_50k": return "Run a 50K (31 mi) in one day"
            case "daily_ultra": return "Run 50+ miles in a single day"
            default: break
            }
        }
        if id == "special_first_mile" { return "Complete your very first mile" }
        if id == "special_first_week" { return "Run every day for a week" }
        
        return badge.description
    }
    
    private func getNumber(from id: String) -> Int? {
        let digits = id.components(separatedBy: CharacterSet.decimalDigits.inverted)
        return digits.compactMap { Int($0) }.first
    }
    
    // MARK: - Animations
    
    private func startAnimations() {
        // Stagger animations for smooth entrance
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
            showMedal = true
        }
        
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.15)) {
            ribbonDrop = true
        }
        
        withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
            showContent = true
        }
        
        // Start shimmer animation
        if !badge.isLocked {
            withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false).delay(0.5)) {
                shimmerOffset = 300
            }
            
            // Start glow pulse
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true).delay(0.3)) {
                glowPulse = true
            }
        }
    }
}

// MARK: - Ribbon Tail Shape

struct RibbonTail: View {
    let isLeft: Bool
    let color: Color
    
    var body: some View {
        Path { path in
            let width: CGFloat = 20
            let height: CGFloat = 25
            
            if isLeft {
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: width, y: 0))
                path.addLine(to: CGPoint(x: width, y: height))
                path.addLine(to: CGPoint(x: width * 0.5, y: height * 0.6))
                path.addLine(to: CGPoint(x: 0, y: height))
            } else {
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: width, y: 0))
                path.addLine(to: CGPoint(x: width, y: height))
                path.addLine(to: CGPoint(x: width * 0.5, y: height * 0.6))
                path.addLine(to: CGPoint(x: 0, y: height))
            }
            path.closeSubpath()
        }
        .fill(
            LinearGradient(
                colors: [color, color.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .frame(width: 20, height: 25)
    }
}

// MARK: - Previews

#Preview("Unlocked Common") {
    BadgeDetailView(badge: Badge(id: "streak_7", name: "Week Warrior", description: "Completed a 7-day streak!"))
}

#Preview("Unlocked Rare") {
    BadgeDetailView(badge: Badge(id: "streak_30", name: "Monthly Master", description: "Completed a 30-day streak!"))
}

#Preview("Unlocked Legendary") {
    BadgeDetailView(badge: Badge(id: "streak_365", name: "Year Warrior", description: "Completed a 365-day streak!"))
}

#Preview("Locked") {
    BadgeDetailView(badge: Badge(id: "streak_100", name: "Century Club", description: "100 day streak!", isLocked: true))
}

#Preview("Mystery") {
    BadgeDetailView(badge: Badge(id: "hidden_perfect", name: "???", description: "Secret!", isLocked: true, isHidden: true))
}
