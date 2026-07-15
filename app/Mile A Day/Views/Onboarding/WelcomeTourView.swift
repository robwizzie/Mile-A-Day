import SwiftUI

/// Full-screen, paged welcome tour shown to new users on their first
/// dashboard visit (and replayable any time from Help & Support / the
/// dashboard welcome banner).
///
/// Replaces the old `DashboardTourOverlay` spotlight, which mis-highlighted
/// dashboard elements that were scrolled off-screen and only ever covered the
/// dashboard. Each page pairs a custom mini-mockup of a real feature with a
/// short explanation, walking new users through every tab and mode in the app:
/// the daily mile, syncing, streaks, challenges & medals, competitions, and
/// friends.
struct WelcomeTourView: View {
    /// Title for the final-page CTA. Defaults to the in-app replay wording;
    /// pre-sign-up onboarding passes "Get Started".
    var finishButtonTitle: String = "Start My Streak"
    /// Called when the user finishes or skips. The presenter is responsible
    /// for dismissing and (on first run) persisting the "seen" flag.
    let onComplete: () -> Void

    @State private var page = 0
    @State private var didAppear = false

    private let pages = TourPage.all

    private var isLast: Bool { page >= pages.count - 1 }
    private var accent: Color { pages[page].accent }

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea()

            // Ambient glow that shifts to the current page's accent color.
            RadialGradient(
                colors: [accent.opacity(0.30), .clear],
                center: .top,
                startRadius: 6,
                endRadius: 520
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.55), value: page)

            VStack(spacing: 0) {
                topBar

                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { index in
                        TourPageView(page: pages[index])
                            .padding(.horizontal, MADTheme.Spacing.lg)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                bottomBar
            }
            .opacity(didAppear ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.4)) { didAppear = true }
        }
    }

    // MARK: - Top Bar (page count + Skip)

    private var topBar: some View {
        HStack {
            Text("\(page + 1) / \(pages.count)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.4))
                .contentTransition(.numericText())

            Spacer()

            if !isLast {
                Button("Skip") { onComplete() }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, MADTheme.Spacing.lg)
        .padding(.top, MADTheme.Spacing.sm)
        .frame(height: 44)
    }

    // MARK: - Bottom Bar (dots + Next / Get Started)

    private var bottomBar: some View {
        VStack(spacing: MADTheme.Spacing.lg) {
            HStack(spacing: 7) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? accent : Color.white.opacity(0.22))
                        .frame(width: index == page ? 26 : 7, height: 7)
                        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: page)
                }
            }

            Button(action: advance) {
                HStack(spacing: 8) {
                    Text(isLast ? finishButtonTitle : "Next")
                    if !isLast {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .bold))
                    }
                }
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(accent)
                )
                .shadow(color: accent.opacity(0.4), radius: 14, x: 0, y: 6)
                .animation(.easeInOut(duration: 0.35), value: page)
            }
        }
        .padding(.horizontal, MADTheme.Spacing.xl)
        .padding(.top, MADTheme.Spacing.sm)
        .padding(.bottom, MADTheme.Spacing.xl)
    }

    private func advance() {
        if isLast {
            onComplete()
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                page += 1
            }
        }
    }
}

// MARK: - Single Page Layout

private struct TourPageView: View {
    let page: TourPage

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            page.visual.view
                .frame(maxWidth: .infinity)

            Spacer().frame(height: 40)

            VStack(spacing: 12) {
                Text(page.badge.uppercased())
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(1.6)
                    .foregroundColor(page.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(page.accent.opacity(0.15)))

                Text(page.title)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                Text(page.subtitle)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, MADTheme.Spacing.sm)
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Page Model

private struct TourPage {
    let badge: String
    let title: String
    let subtitle: String
    let accent: Color
    let visual: TourVisual

    static let all: [TourPage] = [
        TourPage(
            badge: "Welcome",
            title: "Mile A Day",
            subtitle: "Run or walk just one mile a day, build an unbreakable streak, and compete with friends. Here's the quick tour.",
            accent: MADTheme.Colors.madRed,
            visual: .welcome
        ),
        TourPage(
            badge: "Your Goal",
            title: "Hit Your Daily Mile",
            subtitle: "Track a run or walk right in the app, or let Apple Watch and Fitness count it for you. One mile is all it takes.",
            accent: MADTheme.Colors.madRed,
            visual: .dailyMile
        ),
        TourPage(
            badge: "Syncs Anywhere",
            title: "Log It Your Way",
            subtitle: "In-app GPS, Apple Watch, Apple Fitness, or any Health app — every workout counts and syncs automatically. Add widgets for at-a-glance stats.",
            accent: TourPalette.blue,
            visual: .track
        ),
        TourPage(
            badge: "Streaks",
            title: "Keep the Fire Going",
            subtitle: "Finish your mile every day to grow your streak. Flip to your week, trends, and personal records right from the dashboard.",
            accent: TourPalette.orange,
            visual: .streak
        ),
        TourPage(
            badge: "Challenges",
            title: "Challenges & Rivals",
            subtitle: "A fresh challenge drops every day — including head-to-head duels against a friend. Win them to unlock medals for your profile.",
            accent: TourPalette.purple,
            visual: .challenges
        ),
        TourPage(
            badge: "Compete",
            title: "Race Your Friends",
            subtitle: "Start head-to-head competitions and climb live leaderboards. A little rivalry is the best motivation.",
            accent: TourPalette.gold,
            visual: .compete
        ),
        TourPage(
            badge: "Friends",
            title: "Better Together",
            subtitle: "Add friends to follow their activity, cheer them on, and keep each other accountable.",
            accent: TourPalette.green,
            visual: .friends
        ),
        TourPage(
            badge: "Share",
            title: "Share Your Miles",
            subtitle: "Post a photo from today's run with your stats baked in, drop a story, and hype your friends' miles. The feed keeps everyone moving.",
            accent: TourPalette.blue,
            visual: .feed
        ),
        TourPage(
            badge: "Ready",
            title: "You're All Set!",
            subtitle: "Your streak starts with today's mile. Lace up and go get it.",
            accent: MADTheme.Colors.madRed,
            visual: .allSet
        )
    ]
}

private enum TourVisual {
    case welcome, dailyMile, track, streak, challenges, compete, friends, feed, allSet

    @ViewBuilder
    var view: some View {
        switch self {
        case .welcome:    TourWelcomeVisual()
        case .dailyMile:  TourDailyMileVisual()
        case .track:      TourTrackVisual()
        case .streak:     TourStreakVisual()
        case .challenges: TourChallengesVisual()
        case .compete:    TourCompeteVisual()
        case .friends:    TourFriendsVisual()
        case .feed:       TourFeedVisual()
        case .allSet:     TourAllSetVisual()
        }
    }
}

// MARK: - Shared palette / helpers

private enum TourPalette {
    static let orange = Color(red: 1.0, green: 0.52, blue: 0.0)
    static let blue   = Color(red: 0.24, green: 0.62, blue: 0.96)
    static let purple = Color(red: 0.62, green: 0.42, blue: 0.96)
    static let gold   = Color(red: 1.0, green: 0.78, blue: 0.28)
    static let green  = Color(red: 0.26, green: 0.78, blue: 0.46)
}

private extension View {
    /// Floating "card" backing used by most mockups so they read as a real
    /// piece of app UI lifted off the background.
    func tourPanel(cornerRadius: CGFloat = 26) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 14)
    }
}

/// Small initialed avatar circle used in the friends / leaderboard mockups.
private struct TourAvatar: View {
    let initials: String
    let color: Color
    var size: CGFloat = 34

    var body: some View {
        Circle()
            .fill(
                LinearGradient(colors: [color, color.opacity(0.7)],
                               startPoint: .top, endPoint: .bottom)
            )
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            )
    }
}

// MARK: - Visual: Welcome

private struct TourWelcomeVisual: View {
    @State private var float = false

    var body: some View {
        ZStack {
            Circle()
                .fill(MADTheme.Colors.madRed.opacity(0.18))
                .frame(width: 220, height: 220)
                .blur(radius: 32)

            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .fill(MADTheme.Colors.redGradient)
                .frame(width: 150, height: 150)
                .overlay(
                    Image(systemName: "figure.run")
                        .font(.system(size: 74, weight: .bold))
                        .foregroundColor(.white)
                )
                .shadow(color: MADTheme.Colors.madRed.opacity(0.5), radius: 24, x: 0, y: 12)
                .offset(y: float ? -6 : 6)

            chip("flame.fill", TourPalette.orange).offset(x: -104, y: -74)
            chip("trophy.fill", TourPalette.gold).offset(x: 108, y: -42)
            chip("medal.fill", TourPalette.purple).offset(x: 100, y: 76)
            chip("person.2.fill", TourPalette.green).offset(x: -98, y: 70)
        }
        .frame(height: 240)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                float = true
            }
        }
    }

    private func chip(_ icon: String, _ color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(color)
            .frame(width: 46, height: 46)
            .background(
                Circle()
                    .fill(Color(red: 0.13, green: 0.12, blue: 0.14))
                    .overlay(Circle().strokeBorder(color.opacity(0.4), lineWidth: 1))
            )
            .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
            .offset(y: float ? 5 : -5)
    }
}

// MARK: - Visual: Daily Mile (progress ring)

private struct TourDailyMileVisual: View {
    @State private var progress: CGFloat = 0

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: 16)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        MADTheme.Colors.redGradient,
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("0.62")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("of 1.0 mi")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .frame(width: 168, height: 168)

            HStack(spacing: 7) {
                Image(systemName: "figure.run")
                    .font(.system(size: 14, weight: .bold))
                Text("Start Mile")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
            .background(Capsule().fill(MADTheme.Colors.madRed))
            .shadow(color: MADTheme.Colors.madRed.opacity(0.4), radius: 10, x: 0, y: 5)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 36)
        .tourPanel()
        .onAppear {
            withAnimation(.easeOut(duration: 1.0).delay(0.2)) {
                progress = 0.62
            }
        }
    }
}

// MARK: - Visual: Track anywhere (sources grid)

private struct TourTrackVisual: View {
    private let sources: [(icon: String, label: String, color: Color)] = [
        ("figure.run", "In-App GPS", MADTheme.Colors.madRed),
        ("applewatch", "Apple Watch", TourPalette.blue),
        ("heart.fill", "Apple Fitness", TourPalette.green),
        ("square.grid.2x2.fill", "Widgets", TourPalette.purple)
    ]

    var body: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(sources, id: \.label) { source in
                VStack(spacing: 10) {
                    Image(systemName: source.icon)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(source.color)
                        .frame(height: 30)
                    Text(source.label)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(source.color.opacity(0.25), lineWidth: 1)
                        )
                )
            }
        }
        .padding(18)
        .tourPanel()
        .frame(maxWidth: 300)
    }
}

// MARK: - Visual: Streak (flame + week dots)

private struct TourStreakVisual: View {
    @State private var glow = false
    private let days = ["S", "M", "T", "W", "T", "F", "S"]
    private let done = [true, true, true, true, true, false, false] // today = index 4

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(TourPalette.orange.opacity(glow ? 0.35 : 0.18))
                        .frame(width: 72, height: 72)
                        .blur(radius: 12)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 50, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(colors: [TourPalette.orange, MADTheme.Colors.madRed],
                                           startPoint: .top, endPoint: .bottom)
                        )
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text("12")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("day streak")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                }
            }

            HStack(spacing: 8) {
                ForEach(days.indices, id: \.self) { i in
                    VStack(spacing: 6) {
                        Text(days[i])
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.45))
                        Circle()
                            .fill(done[i]
                                  ? AnyShapeStyle(LinearGradient(colors: [TourPalette.orange, MADTheme.Colors.madRed], startPoint: .top, endPoint: .bottom))
                                  : AnyShapeStyle(Color.white.opacity(0.10)))
                            .frame(width: 26, height: 26)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundColor(.white)
                                    .opacity(done[i] ? 1 : 0)
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(i == 4 ? Color.white.opacity(0.8) : Color.clear, lineWidth: 2)
                            )
                    }
                }
            }
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 24)
        .tourPanel()
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }
}

// MARK: - Visual: Challenges & Medals

private struct TourChallengesVisual: View {
    @State private var fill: CGFloat = 0

    var body: some View {
        VStack(spacing: 16) {
            // Challenge card
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(TourPalette.gold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Today's Challenge")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                        Text("Run 1.5 miles")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    Spacer()
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.10))
                        Capsule()
                            .fill(LinearGradient(colors: [TourPalette.gold, TourPalette.orange],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * fill)
                    }
                }
                .frame(height: 8)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(TourPalette.gold.opacity(0.25), lineWidth: 1)
                    )
            )

            // Medals row
            HStack(spacing: 12) {
                medal("medal.fill", TourPalette.gold, locked: false)
                medal("flame.fill", MADTheme.Colors.madRed, locked: false)
                medal("bolt.fill", TourPalette.blue, locked: false)
                medal("lock.fill", .gray, locked: true)
            }
        }
        .padding(18)
        .tourPanel()
        .frame(maxWidth: 300)
        .onAppear {
            withAnimation(.easeOut(duration: 1.1).delay(0.2)) { fill = 0.7 }
        }
    }

    private func medal(_ icon: String, _ color: Color, locked: Bool) -> some View {
        Image(systemName: icon)
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(locked ? .white.opacity(0.3) : .white)
            .frame(width: 52, height: 52)
            .background(
                Circle()
                    .fill(locked
                          ? AnyShapeStyle(Color.white.opacity(0.06))
                          : AnyShapeStyle(LinearGradient(colors: [color, color.opacity(0.65)], startPoint: .top, endPoint: .bottom)))
            )
            .overlay(
                Circle().strokeBorder(Color.white.opacity(locked ? 0.08 : 0.25), lineWidth: 1)
            )
            .shadow(color: locked ? .clear : color.opacity(0.4), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Visual: Compete (leaderboard)

private struct TourCompeteVisual: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(TourPalette.gold)
                Text("Office Mile Battle")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Text("3 days left")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
            }
            .padding(.bottom, 14)

            row(rank: 1, initials: "YO", name: "You", miles: "14.2", color: MADTheme.Colors.madRed, highlight: true)
            divider
            row(rank: 2, initials: "AL", name: "Alex", miles: "12.8", color: TourPalette.blue, highlight: false)
            divider
            row(rank: 3, initials: "SM", name: "Sam", miles: "9.1", color: TourPalette.green, highlight: false)
        }
        .padding(18)
        .tourPanel()
        .frame(maxWidth: 300)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1).padding(.vertical, 9)
    }

    private func row(rank: Int, initials: String, name: String, miles: String, color: Color, highlight: Bool) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(rank == 1 ? TourPalette.gold : .white.opacity(0.45))
                .frame(width: 18)

            TourAvatar(initials: initials, color: color, size: 32)

            Text(name)
                .font(.system(size: 15, weight: highlight ? .bold : .semibold, design: .rounded))
                .foregroundColor(.white)

            Spacer()

            Text("\(miles) mi")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(highlight ? MADTheme.Colors.madRed : .white.opacity(0.7))
        }
        .padding(.horizontal, highlight ? 10 : 0)
        .padding(.vertical, highlight ? 8 : 0)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(highlight ? MADTheme.Colors.madRed.opacity(0.12) : Color.clear)
        )
    }
}

// MARK: - Visual: Friends

private struct TourFriendsVisual: View {
    var body: some View {
        VStack(spacing: 12) {
            activityRow(initials: "MA", name: "Maya", action: "finished her mile", color: TourPalette.purple, trailingIcon: "flame.fill", trailingColor: TourPalette.orange)
            activityRow(initials: "JO", name: "Jordan", action: "logged 2.3 mi", color: TourPalette.blue, trailingIcon: "checkmark.circle.fill", trailingColor: TourPalette.green)

            HStack(spacing: 7) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 14, weight: .bold))
                Text("Add Friends")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Capsule().fill(TourPalette.green))
            .shadow(color: TourPalette.green.opacity(0.35), radius: 10, x: 0, y: 5)
            .padding(.top, 2)
        }
        .padding(18)
        .tourPanel()
        .frame(maxWidth: 300)
    }

    private func activityRow(initials: String, name: String, action: String, color: Color, trailingIcon: String, trailingColor: Color) -> some View {
        HStack(spacing: 12) {
            TourAvatar(initials: initials, color: color, size: 38)
            (
                Text(name).font(.system(size: 15, weight: .bold, design: .rounded))
                + Text("  \(action)").font(.system(size: 14, weight: .regular, design: .rounded))
            )
            .foregroundColor(.white.opacity(0.9))
            Spacer()
            Image(systemName: trailingIcon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(trailingColor)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }
}

// MARK: - Visual: Feed (share a run)

private struct TourFeedVisual: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            // Post header
            HStack(spacing: 10) {
                TourAvatar(initials: "MA", color: TourPalette.purple, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Maya")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("just now")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.45))
                }
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.bottom, 12)

            // "Photo" with a stats sticker overlaid — nods to the shareable run cards.
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [TourPalette.blue.opacity(0.55), TourPalette.purple.opacity(0.55)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 128)
                    .overlay(
                        Image(systemName: "figure.run")
                            .font(.system(size: 54, weight: .bold))
                            .foregroundColor(.white.opacity(0.25))
                    )

                HStack(spacing: 10) {
                    statChip(value: "1.42", unit: "mi")
                    statChip(value: "9:12", unit: "/mi")
                    statChip(value: "13:04", unit: "time")
                }
                .padding(10)
            }
            .padding(.bottom, 12)

            // Hype row
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(TourPalette.orange)
                        .scaleEffect(pulse ? 1.15 : 1.0)
                    Text("12")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                }
                Image(systemName: "bubble.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
                Spacer()
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .padding(16)
        .tourPanel()
        .frame(maxWidth: 300)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private func statChip(value: String, unit: String) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(unit.uppercased())
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.35))
        )
    }
}

// MARK: - Visual: All set

private struct TourAllSetVisual: View {
    @State private var pop = false

    var body: some View {
        ZStack {
            Circle()
                .fill(MADTheme.Colors.madRed.opacity(0.22))
                .frame(width: 200, height: 200)
                .blur(radius: 30)

            Circle()
                .fill(MADTheme.Colors.redGradient)
                .frame(width: 130, height: 130)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 64, weight: .black))
                        .foregroundColor(.white)
                )
                .shadow(color: MADTheme.Colors.madRed.opacity(0.5), radius: 24, x: 0, y: 12)
                .scaleEffect(pop ? 1 : 0.6)
                .opacity(pop ? 1 : 0)

            sparkle(TourPalette.gold).offset(x: -96, y: -64)
            sparkle(TourPalette.orange).offset(x: 100, y: -40)
            sparkle(TourPalette.purple).offset(x: 86, y: 78)
        }
        .frame(height: 240)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { pop = true }
        }
    }

    private func sparkle(_ color: Color) -> some View {
        Image(systemName: "sparkle")
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(color)
            .opacity(pop ? 1 : 0)
            .scaleEffect(pop ? 1 : 0.2)
            .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.25), value: pop)
    }
}

#Preview {
    WelcomeTourView(onComplete: {})
        .preferredColorScheme(.dark)
}
