//
//  InAppNotificationBanner.swift
//  Mile A Day
//
//  A branded, top-aligned banner shown when a push/local notification arrives
//  while the app is in the foreground. iOS suppresses (or shows a generic)
//  system banner in this case, so we present our own — styled to match the app
//  and tappable to route exactly like a tapped system notification.
//
//  Flow: MADNotificationService.willPresent(...) → InAppBannerManager.shared.show(...)
//  → this view (mounted as a top overlay in MainTabView).
//

import SwiftUI

// MARK: - Presenter

/// Holds the currently-visible in-app banner. Drive it from
/// `InAppBannerManager.shared.show(...)`. MainActor-isolated because it mutates
/// `@Published` state consumed by SwiftUI.
@MainActor
final class InAppBannerManager: ObservableObject {
    static let shared = InAppBannerManager()
    private init() {}

    struct Banner: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let body: String
        let type: String?
        let data: [String: String]
    }

    @Published var current: Banner?

    private var dismissTask: Task<Void, Never>?

    /// How long a banner stays on screen before auto-dismissing.
    private let visibleDuration: UInt64 = 4_500_000_000 // 4.5s

    func show(title: String, body: String, type: String?, data: [String: String]) {
        // Silent pushes carry no user-facing content — never show an empty bar.
        guard !title.isEmpty || !body.isEmpty else { return }

        let banner = Banner(title: title, body: body, type: type, data: data)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            current = banner
        }
        scheduleAutoDismiss(for: banner.id)
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            current = nil
        }
    }

    /// Routes the tapped banner the same way a tapped system notification would
    /// (via `.didTapPushNotification`), then dismisses. Banners without a `type`
    /// (e.g. the daily reminder) simply dismiss.
    func handleTap() {
        guard let banner = current else { return }
        if let type = banner.type {
            NotificationCenter.default.post(
                name: .didTapPushNotification,
                object: nil,
                userInfo: ["type": type, "data": banner.data]
            )
        }
        dismiss()
    }

    private func scheduleAutoDismiss(for id: UUID) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.visibleDuration ?? 4_500_000_000)
            guard !Task.isCancelled else { return }
            // Only dismiss if a newer banner hasn't replaced this one.
            guard let self, self.current?.id == id else { return }
            self.dismiss()
        }
    }
}

// MARK: - View

/// Floating top banner. Mount once as an overlay above the main UI.
struct InAppNotificationBanner: View {
    @ObservedObject private var manager = InAppBannerManager.shared
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        Group {
            if let banner = manager.current {
                bannerContent(banner)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: manager.current)
    }

    @ViewBuilder
    private func bannerContent(_ banner: InAppBannerManager.Banner) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(MADTheme.Colors.madRed.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: icon(for: banner.type))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(MADTheme.Colors.madRed)
            }

            VStack(alignment: .leading, spacing: 2) {
                if !banner.title.isEmpty {
                    Text(banner.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                if !banner.body.isEmpty {
                    Text(banner.body)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .madLiquidGlassProminent(cornerRadius: 20)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Only track upward drags (the dismiss direction).
                    if value.translation.height < 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height < -30 {
                        manager.dismiss()
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        dragOffset = 0
                    }
                }
        )
        .onTapGesture {
            manager.handleTap()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-tap to open, swipe up to dismiss")
    }

    /// Maps a notification `type` to an SF Symbol, mirroring how the app
    /// categorises notifications elsewhere. Falls back to a bell.
    private func icon(for type: String?) -> String {
        guard let type else { return "bell.fill" }
        switch type {
        case let t where t.hasPrefix("competition"):
            return "trophy.fill"
        case let t where t.hasPrefix("friend"):
            return "person.2.fill"
        case "badge_earned":
            return "rosette"
        case "streak_broken":
            return "flame.fill"
        case "personal_best":
            return "star.fill"
        case "lead_change", "clash_tie":
            return "chart.line.uptrend.xyaxis"
        default:
            return "bell.fill"
        }
    }
}

#Preview {
    ZStack {
        MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()
        InAppNotificationBanner()
    }
    .onAppear {
        InAppBannerManager.shared.show(
            title: "🔥 Alex completed their mile!",
            body: "Send them some hype to keep the streak alive.",
            type: "friend_activity",
            data: [:]
        )
    }
}
