import SwiftUI

// MARK: - Where a medal / challenge notification goes

/// The screens a medal or challenge notification opens — the thing the
/// notification is ABOUT, never a tab it happens to live on.
///
/// Every one of these used to land somewhere adjacent: your own medal opened
/// the Dashboard with the inbox over it (or the Profile tab, from the inbox),
/// today's challenge opened the Dashboard, and a friend's medal or finished
/// challenge opened their whole profile — so "Sam earned Elite Runner" became
/// a hunt for one medal on someone else's shelf.
enum NotificationDestination: Identifiable, Equatable {
    /// One of your medals. `count > 1` = a burst ("3 Medals Unlocked"),
    /// which opens the shelf on its new ones rather than one of them.
    case myMedal(badgeId: String, count: Int)
    /// The daily challenge screen (today's challenge, its history, a duel's
    /// verdict).
    case challenges
    case friendMedal(FriendMedalRef)
    case friendChallenge(FriendChallengeRef)

    var id: String {
        switch self {
        case .myMedal(let id, let count): return "my-medal-\(id)-\(count)"
        case .challenges: return "challenges"
        case .friendMedal(let ref): return "friend-medal-\(ref.userId)-\(ref.badgeId)"
        case .friendChallenge(let ref): return "friend-challenge-\(ref.userId)-\(ref.localDate ?? "")"
        }
    }

    /// The destination for a notification, or nil when this type keeps its
    /// existing routing. One table, read by the live tap, the cold launch and
    /// the inbox row, so the three can't disagree.
    static func from(type: String, data: [String: String]) -> NotificationDestination? {
        switch type {
        case "badge_earned":
            guard let badgeId = data["badge_id"], !badgeId.isEmpty else { return nil }
            return .myMedal(badgeId: badgeId, count: Int(data["count"] ?? "") ?? 1)
        case "challenge_won":
            return .challenges
        case "daily_reminder":
            // Only the reminder that NAMES today's challenge; a plain, duel or
            // win-back reminder keeps going to the Dashboard.
            return data["kind"] == "challenge" ? .challenges : nil
        case "friend_badge_earned":
            guard let userId = data["sender_id"], !userId.isEmpty,
                  let badgeId = data["badge_id"], !badgeId.isEmpty else { return nil }
            return .friendMedal(FriendMedalRef(
                userId: userId, badgeId: badgeId,
                badgeName: data["badge_name"], rarity: data["rarity"]))
        case "friend_challenge_completed":
            guard let userId = data["sender_id"], !userId.isEmpty else { return nil }
            return .friendChallenge(FriendChallengeRef(
                userId: userId, challengeKey: data["challenge_key"],
                title: data["challenge_title"], localDate: data["local_date"]))
        default:
            return nil
        }
    }
}

struct FriendMedalRef: Equatable {
    let userId: String
    let badgeId: String
    let badgeName: String?
    let rarity: String?
}

struct FriendChallengeRef: Equatable {
    let userId: String
    let challengeKey: String?
    let title: String?
    let localDate: String?
}

/// Presented once, at MainTabView root (`notificationDestinationHost()`), so a
/// tap from any tab — or from a cold launch — lands on the same screen.
@MainActor
final class NotificationDestinationLink: ObservableObject {
    static let shared = NotificationDestinationLink()
    private init() {}

    @Published var pending: NotificationDestination?

    func open(_ destination: NotificationDestination) { pending = destination }

    /// For callers dismissing their OWN sheet first (the inbox): two
    /// presentations in one transaction race and SwiftUI drops one.
    func openAfterDismiss(_ destination: NotificationDestination) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.pending = destination
        }
    }
}

extension View {
    func notificationDestinationHost() -> some View {
        modifier(NotificationDestinationHost())
    }
}

private struct NotificationDestinationHost: ViewModifier {
    @ObservedObject private var link = NotificationDestinationLink.shared

    func body(content: Content) -> some View {
        content.sheet(item: $link.pending) { destination in
            NotificationDestinationScreen(destination: destination)
        }
    }
}

// MARK: - The screen

private struct NotificationDestinationScreen: View {
    let destination: NotificationDestination
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch destination {
                case .myMedal(let badgeId, let count):
                    MyMedalDestination(badgeId: badgeId, count: count)
                case .challenges:
                    DailyChallengesView(healthManager: .shared, userManager: .shared)
                case .friendMedal(let ref):
                    FriendMedalView(ref: ref)
                case .friendChallenge(let ref):
                    FriendChallengeView(ref: ref)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Your medal, by id. The push can beat the shelf (it's sent the moment the
/// medal is awarded), so a miss refreshes from the server once before falling
/// back to the whole shelf.
private struct MyMedalDestination: View {
    let badgeId: String
    let count: Int
    @ObservedObject private var userManager = UserManager.shared
    @State private var didRefresh = false

    private var badge: Badge? {
        userManager.currentUser.badges.first { $0.id == badgeId && !$0.isLocked }
    }

    var body: some View {
        Group {
            if count > 1 {
                BadgesView(userManager: userManager, initialBadge: nil)
            } else if let badge {
                BadgeDetailView(badge: badge, userManager: userManager)
            } else if didRefresh {
                BadgesView(userManager: userManager, initialBadge: nil)
            } else {
                ProgressView().tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(MADTheme.Colors.appBackgroundGradient.ignoresSafeArea())
            }
        }
        .task {
            guard badge == nil else { return }
            await userManager.refreshBadgesFromServer(celebrateNew: false)
            didRefresh = true
        }
    }
}

// MARK: - Shared friend chrome

/// Who it's about, loaded once: the push only carries their id.
@MainActor
private final class FriendHeaderModel: ObservableObject {
    @Published var user: BackendUser?

    func load(_ userId: String) async {
        guard user == nil else { return }
        user = try? await APIClient.fancyFetch(endpoint: "/users/\(userId)", responseType: BackendUser.self)
    }
}

/// The friend's face and name over a short line — the top of both screens.
private struct FriendHeader: View {
    let user: BackendUser?
    let line: String

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(name: user?.displayName ?? "Friend", imageURL: user?.profile_image_url, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(user?.displayName ?? " ")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(line)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Hype + their profile — the two things worth doing about a friend's news.
private struct FriendActions: View {
    let userId: String
    let username: String?
    let hype: HypeContext
    @Environment(\.dismiss) private var dismiss
    @State private var hyped = false
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 10) {
            Button {
                guard !hyped, !sending else { return }
                sending = true
                MADHaptics.action()
                Task {
                    do {
                        _ = try await HypeService.sendHype(targetUserId: userId, context: hype)
                        hyped = true
                        MADHaptics.success()
                    } catch {
                        self.error = "Couldn't send that hype — try again."
                    }
                    sending = false
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: hyped ? "checkmark" : "hands.clap.fill")
                        .accessibilityHidden(true)
                    Text(hyped ? "Hyped!" : "Send hype")
                }
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(hyped ? MADTheme.Colors.success : MADTheme.Colors.madRed)
                )
            }
            .buttonStyle(.plain)
            .disabled(hyped || sending)

            if let username, !username.isEmpty {
                Button {
                    MADHaptics.tap()
                    dismiss()
                    // After the sheet is gone, the Friends tab opens their
                    // profile (it resolves the parked username itself).
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        DeepLinkRouter.shared.pendingProfileUsername = username.lowercased()
                        NotificationCenter.default.post(
                            name: NSNotification.Name("MAD_SwitchTab"), object: nil, userInfo: ["tab": 3])
                    }
                } label: {
                    Text("View profile")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
            }

            if let error {
                Text(error)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(MADTheme.Colors.warning)
            }
        }
    }
}

// MARK: - A friend's medal

/// "Sam earned Elite Runner" — the medal itself, how they earned it, and
/// where YOU stand on the same medal.
struct FriendMedalView: View {
    let ref: FriendMedalRef
    @StateObject private var header = FriendHeaderModel()
    @ObservedObject private var userManager = UserManager.shared
    @State private var theirs: BadgeAPIService.UserBadgeDTO?
    @State private var loaded = false

    /// Their copy when it loaded, else what the push said — so the screen is
    /// whole even when the shelf read fails.
    private var badge: Badge {
        Badge(
            id: ref.badgeId,
            name: theirs?.name ?? ref.badgeName ?? "Medal",
            description: theirs?.description ?? "",
            dateAwarded: theirs?.earnedAt ?? Date(),
            isNew: false,
            isLocked: false
        )
    }

    private var mine: Badge? {
        userManager.currentUser.badges.first { $0.id == ref.badgeId && !$0.isLocked }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                FriendHeader(user: header.user, line: "earned a medal")
                    .padding(.top, 8)

                TiltableMedal(badge: badge, size: 150)
                    .padding(.vertical, 8)

                VStack(spacing: 8) {
                    Text(badge.rarity.rawValue.uppercased())
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.4)
                        .foregroundColor(badge.rarity.color)
                    Text(badge.name)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    if !badge.description.isEmpty {
                        Text(badge.description)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                }

                VStack(spacing: 0) {
                    if let summary = theirs?.detail?.summary, !summary.isEmpty {
                        infoRow(icon: "figure.run", text: summary)
                        Divider().background(Color.white.opacity(0.1))
                    }
                    if let earned = theirs?.earnedAt {
                        infoRow(icon: "calendar", text: "Earned \(Self.dateFormatter.string(from: earned))")
                        Divider().background(Color.white.opacity(0.1))
                    }
                    infoRow(
                        icon: mine == nil ? "lock.fill" : "checkmark.seal.fill",
                        text: mine.map { "You have it too — since \(Self.dateFormatter.string(from: $0.dateAwarded))" }
                            ?? "You haven't earned this one yet",
                        tint: mine == nil ? .white.opacity(0.6) : MADTheme.Colors.success
                    )
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                )

                FriendActions(
                    userId: ref.userId,
                    username: header.user?.username,
                    hype: HypeContext(contextType: "badge", contextId: ref.badgeId, contextLabel: badge.name)
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(MADTheme.Colors.appBackgroundGradient.ignoresSafeArea())
        .navigationTitle("Medal")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            async let user: Void = header.load(ref.userId)
            async let shelf = try? BadgeAPIService.fetchUserBadges(userId: ref.userId)
            theirs = await shelf?.first { $0.badgeId == ref.badgeId }
            _ = await user
            loaded = true
        }
    }

    private func infoRow(icon: String, text: String, tint: Color = .white.opacity(0.7)) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - A friend's finished challenge

/// "Sam finished today's challenge" — the challenge, that it's done, and
/// where you stand on YOUR challenge today, with the way to go do it.
struct FriendChallengeView: View {
    let ref: FriendChallengeRef
    @StateObject private var header = FriendHeaderModel()
    @State private var theirToday: RemoteChallengeService.FriendTodayDTO?
    @State private var openMine = false

    private var myToday: DailyChallenge? {
        (ChallengeService.shared as? RemoteChallengeService)?.todayChallenge
    }

    private var myTodayDone: Bool {
        (ChallengeService.shared as? RemoteChallengeService)?.todayCompleted ?? false
    }

    /// Their challenge's look: the server's today read when it's the same day
    /// and challenge, else the push's title on the default colours.
    private var title: String {
        theirToday?.challengeTitle ?? ref.title ?? "Today's challenge"
    }
    private var icon: String { theirToday?.challengeIcon ?? "checkmark.seal.fill" }
    private var gradient: [Color] {
        if let a = theirToday?.gradientStart, let b = theirToday?.gradientEnd {
            return [Color(hex: a), Color(hex: b)]
        }
        return [.orange, MADTheme.Colors.madRed]
    }

    private var whenLine: String {
        guard let day = ref.localDate, let date = Self.dayParser.date(from: day) else {
            return "finished their challenge"
        }
        if Calendar.current.isDateInToday(date) { return "finished today's challenge" }
        if Calendar.current.isDateInYesterday(date) { return "finished yesterday's challenge" }
        return "finished a challenge"
    }

    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                FriendHeader(user: header.user, line: whenLine)
                    .padding(.top, 8)

                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 96, height: 96)
                            .shadow(color: (gradient.first ?? .orange).opacity(0.5), radius: 18)
                        Image(systemName: icon)
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(.white)
                            .accessibilityHidden(true)
                    }
                    Text(title)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Label("Completed", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(MADTheme.Colors.success)
                }
                .padding(.vertical, 8)

                if let mine = myToday {
                    Button {
                        MADHaptics.tap()
                        openMine = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: mine.icon)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(LinearGradient(colors: mine.gradient,
                                                                          startPoint: .topLeading, endPoint: .bottomTrailing)))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("YOUR CHALLENGE TODAY")
                                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                                    .tracking(1.2)
                                    .foregroundColor(.white.opacity(0.5))
                                Text(mine.title)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Text(myTodayDone ? "Done" : "Go")
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundColor(myTodayDone ? MADTheme.Colors.success : .white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.white.opacity(myTodayDone ? 0.08 : 0.16)))
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                }

                FriendActions(
                    userId: ref.userId,
                    username: header.user?.username,
                    hype: HypeContext(
                        contextType: "challenge",
                        // Same key the inbox's hype-back uses for this event.
                        contextId: "\(ref.userId):\(ref.localDate ?? "")",
                        contextLabel: title
                    )
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(MADTheme.Colors.appBackgroundGradient.ignoresSafeArea())
        .navigationTitle("Challenge")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $openMine) {
            DailyChallengesView(healthManager: .shared, userManager: .shared)
        }
        .task {
            async let user: Void = header.load(ref.userId)
            // Their challenge's icon and colours — only meaningful when the
            // notification is about the day the server calls their today.
            if let today = try? await RemoteChallengeService.fetchFriendToday(userId: ref.userId),
               ref.localDate == nil || today.localDate == ref.localDate,
               ref.challengeKey == nil || today.challengeKey == ref.challengeKey {
                theirToday = today
            }
            _ = await user
        }
    }
}
