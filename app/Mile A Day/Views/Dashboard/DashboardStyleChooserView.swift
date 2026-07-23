import SwiftUI

struct DashboardStyleChooserView: View {
    let onChoose: (DashboardStyle) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Choose your dashboard")
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("You can switch anytime in Dashboard Settings.")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.58))
                    }
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white.opacity(0.72))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Keep Modern dashboard")
                }

                HStack(spacing: 12) {
                    styleCard(.fun)
                    styleCard(.modern)
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color(red: 0.065, green: 0.065, blue: 0.075))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            )
            .padding(18)
        }
    }

    private func styleCard(_ style: DashboardStyle) -> some View {
        Button {
            onChoose(style)
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(style == .fun ? Color(red: 0.18, green: 0.05, blue: 0.06) : Color(red: 0.09, green: 0.09, blue: 0.10))
                        .frame(height: 132)
                    if style == .fun {
                        FlameBuddyView(health: .healthy, size: 106)
                    } else {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.12), lineWidth: 12)
                                .frame(width: 92, height: 92)
                            Circle()
                                .trim(from: 0, to: 0.72)
                                .stroke(LinearGradient(colors: [.orange, MADTheme.Colors.madRed], startPoint: .topLeading, endPoint: .bottomTrailing), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                                .frame(width: 92, height: 92)
                                .rotationEffect(.degrees(-90))
                            Image(systemName: "flame.fill")
                                .font(.system(size: 23, weight: .bold))
                                .foregroundColor(.orange)
                        }
                    }
                }

                VStack(spacing: 3) {
                    Text(style.title)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text(style.subtitle)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white.opacity(0.54))
                        .lineLimit(2)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.055))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
}
