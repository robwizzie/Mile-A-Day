import SwiftUI
import CoreLocation

/// "Walks Together" on your own profile — the front door to the buddy history.
///
/// It lives on the profile because that is where the app already keeps the
/// things you've DONE (streak hall, ghost races, route heatmap), and a shared
/// walk is exactly that. The alternative homes were both worse: inside the
/// start sheet it's only findable by someone already setting up a walk, and in
/// the feed it scrolls away in a day.
///
/// Shows itself even with nothing in it, unlike the partners list in the start
/// sheet. An empty panel on a stats screen is discouraging, but this one is a
/// pitch: a user who has never done a buddy walk is precisely the person the
/// prompt is for, and there is nowhere else in the app that explains what one
/// is outside the sheet that creates it.
///
/// Self-contained like `GhostRacesSection` beside it — owns its fetch and its
/// state, so the parent just drops it in.
struct BuddyWalksSection: View {
    @ObservedObject private var buddy = BuddySessionService.shared

    @State private var walks: [BuddyWalkRecord] = []
    @State private var totals: BuddyHistoryTotals?
    @State private var isLoading = true
    @State private var showHistory = false
    /// A tile's walk — opens the same detail the history's cards open.
    @State private var detailWalk: BuddyWalkRecord?
    /// Route thumbnails for tiles without a picture, keyed by walk id — read
    /// off the walk's post (the poster's line, else the first crew line), one
    /// fetch per tile that needs it, three tiles at most.
    @State private var tileRoutes: [String: [CLLocationCoordinate2D]] = [:]

    private var viewerId: String? { buddy.currentUserId }

    /// The most recent walk's colour, so a run history reads red and a walk
    /// history blue — same rule as everywhere else.
    private var accent: Color {
        walks.first?.accentColor ?? MADTheme.workoutColor("walking")
    }

    var body: some View {
        // ONE card with the label inside it, like every other Activity block —
        // the label used to float above a card of its own, which read as a
        // stray heading next to Hall of Streaks and Last 7 Days.
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            header

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MADTheme.Spacing.md)
            } else if walks.isEmpty {
                pitch
            } else {
                VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                    // Each tile is ITS walk; the line under them is the archive.
                    tileStrip
                    Button {
                        MADHaptics.tap()
                        showHistory = true
                    } label: {
                        summaryLine
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(MADTheme.Spacing.md)
        .profileCard()
        .task { await load() }
        .sheet(isPresented: $showHistory) {
            BuddyWalksHistoryView()
        }
        // Its own node — a second `.sheet` on the one above would be dropped.
        .background(
            Color.clear.sheet(item: $detailWalk) { walk in
                BuddyWalkDetailView(walk: walk)
            }
        )
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: MADTheme.Spacing.sm) {
            ProfileCardLabel(text: "WALKS TOGETHER")
            Spacer()
            if !walks.isEmpty {
                Button {
                    MADHaptics.tap()
                    showHistory = true
                } label: {
                    HStack(spacing: 3) {
                        Text("See all")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The last few walks as square tiles: the photo when there is one, the
    /// mode's crest when there isn't. This is the whole reason the section is
    /// worth a slot — a strip of pictures from walks you took with people is
    /// the thing that gets tapped.
    /// Tiles at the feed's 4:5, side-scrolling so three of them can never be
    /// squeezed by a narrow screen — a squeezed HStack crops whatever is in
    /// it, which is how the pictures were getting cut off.
    private var tileStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MADTheme.Spacing.sm) {
                ForEach(walks.prefix(3)) { walk in
                    Button {
                        MADHaptics.tap()
                        detailWalk = walk
                    } label: {
                        tile(walk)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(walk.crewText(excluding: viewerId)), \(walk.dayText)")
                }
            }
            .padding(.horizontal, 1)
        }
        // Sideways inside a vertical scroll: must not be able to widen the page.
        .frame(maxWidth: .infinity)
    }

    /// 4:5, like a feed slide, so a photo is cropped no harder here than there.
    private static let tileSize = CGSize(width: 108, height: 135)

    private func tile(_ walk: BuddyWalkRecord) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                .fill(walk.accentColor.opacity(0.16))

            if let photo = walk.photos.first {
                BuddyHistoryTileImage(url: photo.url)
            } else if let coords = tileRoutes[walk.id] {
                // The walk's actual line, the way the feed draws it.
                RouteArtView(
                    coordinates: coords,
                    routeColor: walk.accentColor,
                    showsMileMarkers: false,
                    paletteDate: walk.startedAtDate
                )
                .allowsHitTesting(false)
            } else {
                VStack(spacing: 4) {
                    // A walk with a map but no picture wears the map glyph, so
                    // the tile promises what the tap delivers.
                    Image(systemName: walk.hasAnyRoute ? "map.fill" : walk.mode.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(walk.accentColor)
                    Text("\(walk.groupDistanceMiles.milesText) mi")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.75))
                }
            }
        }
        .frame(width: Self.tileSize.width, height: Self.tileSize.height)
        .overlay(alignment: .topTrailing) {
            // More pictures inside than the one on the tile.
            if walk.photos.count > 1 {
                Text("\(walk.photos.count)")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(MADTheme.Colors.madWhite)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.5)))
                    .padding(4)
            }
        }
        .clipShape(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            // Who it was with, on the tile itself: the faces are what make the
            // strip legible at a glance, not the distances.
            HStack(spacing: -6) {
                ForEach(walk.others(excluding: viewerId).prefix(2)) { person in
                    AvatarView(
                        name: person.displayName,
                        imageURL: person.profileImageUrl,
                        size: 20
                    )
                    .overlay(
                        Circle().strokeBorder(Color.black.opacity(0.45), lineWidth: 1.5))
                }
            }
            .padding(5)
        }
    }

    /// "14.2 mi together · 12 walks · 3 friends". Totals, not the page — the
    /// strip above is a sample, and a number that grew as you scrolled the
    /// history would contradict it.
    private var summaryLine: some View {
        let miles = (totals?.miles ?? 0).milesText
        let walkCount = totals?.walks ?? walks.count
        let partnerCount = totals?.partners ?? 0
        var parts = ["\(miles) mi together"]
        parts.append("\(walkCount) \(walkCount == 1 ? "walk" : "walks")")
        if partnerCount > 0 {
            parts.append("\(partnerCount) \(partnerCount == 1 ? "friend" : "friends")")
        }
        return HStack(spacing: MADTheme.Spacing.sm) {
            Text(parts.joined(separator: " · "))
                .font(MADTheme.Typography.smallBold)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.35))
        }
    }

    /// What a buddy walk IS, for someone who has never done one, plus the one
    /// tap that starts it.
    private var pitch: some View {
        Button {
            MADHaptics.action()
            showHistory = true
        } label: {
            HStack(spacing: MADTheme.Spacing.md) {
                ZStack {
                    Circle().fill(accent.opacity(0.18)).frame(width: 44, height: 44)
                    Image(systemName: "figure.2")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Walk with a friend")
                        .font(MADTheme.Typography.smallBold)
                        .foregroundStyle(MADTheme.Colors.madWhite)
                    Text("Move at the same time, see each other's miles — it all lands here")
                        .font(MADTheme.Typography.caption)
                        .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.35))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        // Three is what the strip shows; asking for more would be paying for
        // rows nobody sees.
        do {
            let response = try await buddy.loadHistory(limit: 3)
            walks = response.sessions
            totals = response.totals
            await loadTileRoutes()
        } catch {
            // Silent, and keeps whatever we had: this is a nice-to-have panel
            // and blanking it on a blip would make a real history look lost.
            print("[BuddyWalksSection] load failed: \(error)")
        }
        isLoading = false
    }

    /// A tile with no picture shows its route instead — from the post, which
    /// carries everyone's line in one read. Walks nobody posted keep the crest.
    private func loadTileRoutes() async {
        for walk in walks.prefix(3) where walk.photos.isEmpty && tileRoutes[walk.id] == nil {
            guard let postId = walk.postId,
                  let entry = try? await PostService.fetchPost(postId: postId),
                  let item = entry.asPostItem() else { continue }
            let coords = item.routeCoordinates
                ?? item.acceptedCoauthors.compactMap(\.routeCoordinates).first
            if let coords, coords.count >= 2 {
                tileRoutes[walk.id] = coords
            }
        }
    }
}

// MARK: - Friend profile row

/// "12 walks together · 14.2 mi of yours" on a friend's profile.
///
/// The single highest-value place this history can appear: you are already
/// looking at the person, so the number and the next invitation are one tap
/// apart. With no shared history yet it says so and opens the same screen,
/// whose empty state explains what a buddy walk is — on a friend's profile
/// that reads as an invitation rather than a reproach, and it is the one place
/// in the app where the idea arrives next to a specific person to do it with.
///
/// Always renders SOMETHING, deliberately: a view whose body resolves to
/// `EmptyView` gets no lifecycle, so a `.task` hanging off a "hide until
/// loaded" branch never fires and the row can never appear at all (ios.md).
/// Both states are the same shape, so the swap when totals land is invisible.
struct BuddyWalksTogetherRow: View {
    let userId: String
    let displayName: String

    @ObservedObject private var buddy = BuddySessionService.shared

    @State private var totals: BuddyHistoryTotals?
    @State private var latest: BuddyWalkRecord?
    @State private var showHistory = false

    private var accent: Color {
        latest?.accentColor ?? MADTheme.workoutColor("walking")
    }

    private var walkCount: Int { totals?.walks ?? 0 }

    var body: some View {
        Button {
            MADHaptics.tap()
            showHistory = true
        } label: {
            row
        }
        .buttonStyle(.plain)
        .task(id: userId) { await load() }
        .sheet(isPresented: $showHistory) {
            BuddyWalksHistoryView(friendId: userId, friendName: displayName)
        }
    }

    private var row: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            ZStack {
                Circle().fill(accent.opacity(0.18)).frame(width: 44, height: 44)
                Image(systemName: "figure.2")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(MADTheme.Typography.smallBold)
                    .foregroundStyle(MADTheme.Colors.madWhite)
                    .lineLimit(1)
                Text(subtitle)
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.35))
        }
        .padding(MADTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(MADTheme.Colors.madWhite.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .strokeBorder(
                    accent.opacity(walkCount > 0 ? 0.25 : 0.12), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    private var title: String {
        guard walkCount > 0 else { return "Walk together" }
        return "\(walkCount) \(walkCount == 1 ? "walk" : "walks") together"
    }

    /// The miles are YOURS across those walks, matching every other
    /// shared-history number in the app — a pooled figure double-counts the
    /// same walk from each side, so the two of you would see different totals.
    private var subtitle: String {
        guard let totals, totals.walks > 0 else {
            return "Move at the same time and see each other's miles"
        }
        var parts = ["\(totals.miles.milesText) mi of yours"]
        if let latest { parts.append("last \(latest.dayText.lowercased())") }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        do {
            let response = try await buddy.loadHistory(friendId: userId, limit: 1)
            totals = response.totals
            latest = response.sessions.first
        } catch {
            print("[BuddyWalksTogetherRow] load failed: \(error)")
        }
    }
}

/// A history tile's photo, backed by the feed's shared image cache — see
/// `BuddyWalksHistoryView` for why the binding is parked in local state.
private struct BuddyHistoryTileImage: View {
    let url: URL?
    @State private var image: UIImage?

    var body: some View {
        FeedImageView(url: url, loadedImage: $image)
    }
}
