import SwiftUI

/// A walk/run the user did on today's calendar day in a previous year — or a
/// past post photo (a week / a month / years ago) resurfaced from the server.
struct MemoryItem: Identifiable {
    let id = UUID()
    let date: Date
    let yearsAgo: Int
    let miles: Double
    let workoutType: String
    let durationSeconds: Double
    /// The story/feed photo from that day, when one exists. Expired stories
    /// live on here — the photo outlasts its 24 hours.
    var photoURL: URL? = nil
    /// Overrides the "N years ago" label for sub-year memories ("1 week ago").
    var agoOverride: String? = nil

    var yearsAgoText: String {
        if let agoOverride { return agoOverride }
        return yearsAgo == 1 ? "1 year ago" : "\(yearsAgo) years ago"
    }
}

/// Builds "On this day" memories from the locally-cached HealthKit workout
/// index — no network needed. Future: attach a post photo when one exists for
/// that date, and surface memories as a leading story ring.
enum MemoriesService {
    static func onThisDay(using hk: HealthKitManager) -> [MemoryItem] {
        guard let index = hk.workoutIndex else { return [] }
        let cal = Calendar.current
        let today = cal.dateComponents([.month, .day, .year], from: Date())
        guard let month = today.month, let day = today.day, let curYear = today.year else { return [] }

        var out: [MemoryItem] = []
        for (_, records) in index.workoutsByDate {
            guard let first = records.first else { continue }
            let comps = cal.dateComponents([.month, .day, .year], from: first.localDate)
            guard comps.month == month, comps.day == day, let year = comps.year, year < curYear else { continue }
            let miles = records.reduce(0.0) { $0 + $1.distance }
            guard miles >= 0.95 else { continue }
            let topType = records.max(by: { $0.distance < $1.distance })?.workoutType ?? "running"
            let duration = records.reduce(0.0) { $0 + $1.duration }
            out.append(MemoryItem(
                date: first.localDate,
                yearsAgo: curYear - year,
                miles: miles,
                workoutType: topType,
                durationSeconds: duration
            ))
        }
        return out.sorted { $0.yearsAgo < $1.yearsAgo }
    }

    /// Blend the server's photo memories (this day in past years, a week ago,
    /// a month ago) into the local HealthKit ones: matching days get the photo
    /// attached; days we have no workout record for become photo-only items.
    static func mergingPostMemories(_ posts: [PostItem], into items: [MemoryItem]) -> [MemoryItem] {
        var merged = items
        let cal = Calendar.current
        let parser: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f
        }()
        let today = cal.startOfDay(for: Date())

        for post in posts {
            guard let localDate = post.local_date, let date = parser.date(from: localDate),
                  let photoURL = post.mediaURL else { continue }
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: today).day ?? 0
            guard days > 0 else { continue }

            // Bucket by RANGE, not exact day counts — the server computes "a
            // week/month ago" against its own date, and timezone or midnight
            // drift makes the client's day math land on 6/8 or 29/31.
            let ago: String? = {
                if (5...9).contains(days) { return "1 week ago" }
                if (25...45).contains(days) { return "1 month ago" }
                return nil // exact-year memories use the standard label
            }()
            let years = cal.dateComponents([.year], from: date, to: today).year ?? 0

            if let idx = merged.firstIndex(where: { cal.isDate($0.date, inSameDayAs: date) }) {
                if merged[idx].photoURL == nil { merged[idx].photoURL = photoURL }
                if merged[idx].agoOverride == nil, let ago { merged[idx].agoOverride = ago }
            } else {
                merged.append(MemoryItem(
                    date: date,
                    yearsAgo: max(years, 0),
                    miles: post.stats_snapshot?.distance ?? 0,
                    workoutType: "running",
                    durationSeconds: post.stats_snapshot?.duration ?? 0,
                    photoURL: photoURL,
                    agoOverride: ago
                ))
            }
        }
        // Freshest memories first: sub-year (week/month) photos, then by years.
        return merged.sorted {
            if ($0.agoOverride != nil) != ($1.agoOverride != nil) { return $0.agoOverride != nil }
            return $0.yearsAgo < $1.yearsAgo
        }
    }
}

/// Compact "On this day" card shown at the top of the feed when memories exist.
/// Scales from one memory to many: stacked photo thumbnails when photos exist,
/// and a summary line that says how many there are instead of a bare "+N".
struct MemoriesCardView: View {
    let memories: [MemoryItem]
    let onTap: () -> Void

    private var photoURLs: [URL] {
        memories.compactMap(\.photoURL)
    }

    private var subtitle: String {
        guard let top = memories.first else { return "" }
        if memories.count == 1 {
            return "\(top.yearsAgoText) · \(String(format: "%.2f", top.miles)) mi \(ActivityCardView.verb(top.workoutType).lowercased())"
        }
        return "\(memories.count) memories · \(top.yearsAgoText) and more"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: MADTheme.Spacing.md) {
                leadingThumbnails

                VStack(alignment: .leading, spacing: 2) {
                    Text("On this day")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                        .foregroundColor(.white.opacity(0.6))
                    Text(subtitle)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                            .strokeBorder(MADTheme.Colors.madRed.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    /// Up to three overlapping photo thumbnails, or the clock badge when the
    /// memories have no photos.
    @ViewBuilder
    private var leadingThumbnails: some View {
        let urls = Array(photoURLs.prefix(3))
        if urls.isEmpty {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(MADTheme.Colors.redGradient))
        } else {
            ZStack {
                ForEach(Array(urls.enumerated().reversed()), id: \.offset) { index, url in
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Color.white.opacity(0.06)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color(red: 0.09, green: 0.07, blue: 0.08), lineWidth: 1.5)
                    )
                    .offset(x: CGFloat(index) * 10)
                }
            }
            // Reserve the stack's real footprint so the text column doesn't
            // overlap the offset thumbnails.
            .frame(width: 44 + CGFloat(max(0, urls.count - 1)) * 10, height: 44, alignment: .leading)
        }
    }
}

/// Today's memories across past years, presented as full feed-style cards:
/// a header ("2 years ago · June 4, 2024"), the day's photo when one exists
/// (or a branded distance hero when not), and a stat chip strip — the same
/// visual language as the main feed.
struct MemoriesDetailView: View {
    let memories: [MemoryItem]
    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        return f
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()
                if memories.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: MADTheme.Spacing.md) {
                            ForEach(memories) { memory in
                                memoryCard(memory)
                            }
                        }
                        .padding(MADTheme.Spacing.md)
                        .padding(.bottom, MADTheme.Spacing.xl)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("On this day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(MADTheme.Colors.madRed)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.3))
            Text("No memories today")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }

    // MARK: - Feed-style memory card

    private func memoryCard(_ memory: MemoryItem) -> some View {
        let accent = ActivityCardView.color(memory.workoutType)
        return VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            // Header — mirrors the feed card's author row, with the memory's
            // age standing in for the author.
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(MADTheme.Colors.redGradient))
                VStack(alignment: .leading, spacing: 1) {
                    Text(memory.yearsAgoText)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(Self.dateFormatter.string(from: memory.date))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                Image(systemName: ActivityCardView.icon(memory.workoutType))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(accent)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(accent.opacity(0.15)))
            }

            if let photoURL = memory.photoURL {
                photoSlide(photoURL)
            } else if memory.miles > 0 {
                distanceHero(memory, accent: accent)
            }

            statStrip(memory)
        }
        .padding(MADTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    /// The day's photo, full-width 4:5 like a feed post slide.
    private func photoSlide(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                ZStack {
                    Color.white.opacity(0.05)
                    Image(systemName: "photo").foregroundColor(.white.opacity(0.3))
                }
            default:
                ZStack {
                    Color.white.opacity(0.05)
                    ProgressView().tint(.white)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))
    }

    /// Photo-less memories get a compact branded hero — the distance as the
    /// moment, in the same gradient language as the feed's workout card.
    private func distanceHero(_ memory: MemoryItem, accent: Color) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.09, green: 0.09, blue: 0.12), .black],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [accent.opacity(0.35), .clear],
                center: .init(x: 0.5, y: 0.4), startRadius: 8, endRadius: 180
            )
            VStack(spacing: 2) {
                Text(String(format: "%.2f", memory.miles))
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .shadow(color: .black.opacity(0.4), radius: 5, y: 2)
                Text("MILES \(ActivityCardView.verb(memory.workoutType).uppercased())")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(4)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))
    }

    /// Miles / time / pace chips, same grammar as the feed's activity card.
    @ViewBuilder
    private func statStrip(_ memory: MemoryItem) -> some View {
        let items = statItems(memory)
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items, id: \.0) { item in
                        HStack(spacing: 5) {
                            Image(systemName: item.1)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.orange)
                            Text(item.2)
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.07)))
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func statItems(_ memory: MemoryItem) -> [(String, String, String)] {
        var out: [(String, String, String)] = []
        if memory.miles > 0 {
            out.append(("miles", ActivityCardView.icon(memory.workoutType),
                        String(format: "%.2f mi", memory.miles)))
        }
        if memory.durationSeconds > 0 {
            out.append(("time", "clock.fill", RunStatsStickerView.durationText(memory.durationSeconds)))
            if memory.miles > 0 {
                out.append(("pace", "speedometer",
                            "\(RunStatsStickerView.paceText(memory.durationSeconds / memory.miles)) /mi"))
            }
        }
        return out
    }
}
