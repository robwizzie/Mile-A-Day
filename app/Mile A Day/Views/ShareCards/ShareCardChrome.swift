import SwiftUI

// Card chrome still used by the Monthly Recap's image (MonthlyRecapView).
// The six dashboard sticker cards that also lived here went with the old
// stats builder: the dashboard heroes open the Share Studio now.

// MARK: - Shared Components

/// Reusable background for share cards
struct ShareCardBackground: View {
    let accentColor: Color
    let isDarkMode: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 80)
                .fill(isDarkMode ? Color.black.opacity(0.95) : Color.white.opacity(0.2))

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

            RoundedRectangle(cornerRadius: 80)
                .fill(Color.clear)
                .shadow(color: accentColor.opacity(0.7), radius: 40, x: 0, y: 0)
        }
    }
}

/// Reusable footer for share cards (MAD logo + slogan)
struct ShareCardFooter: View {
    var body: some View {
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
