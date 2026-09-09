import SwiftUI
import CoreLocation

// MARK: - Story share canvas
//
// The app's share images are 4:5 (1080×1350) and 2:3 (1800×2700). An Instagram
// Story is 9:16 (1080×1920), so every one of them lands letterboxed with about
// a third of the screen as empty bar — which is most of why a good share card
// still doesn't get posted. This is the one canvas built for that shape.
//
// Four faces over the same geometry, so they can't drift: the route (the thing
// a walk looks like), the walker's own photo, the streak, and a transparent
// sticker for placing over somebody else's story.
//
// Two rules hold on every face:
//   * The footer lockup — wordmark + mileaday.run — is not decoration. A story
//     link isn't tappable for most accounts, so the URL baked into the picture
//     is the only thing that can turn a share into a download.
//   * The STREAK rides along wherever we have one. It is the number Strava
//     structurally cannot show, and the one most likely to make a viewer ask
//     what app this is.

enum MADStoryFace: String, CaseIterable, Identifiable {
    case route, photo, streak, sticker

    var id: String { rawValue }

    var title: String {
        switch self {
        case .route: return "Route"
        case .photo: return "Photo"
        case .streak: return "Streak"
        case .sticker: return "Sticker"
        }
    }

    var icon: String {
        switch self {
        case .route: return "point.topleft.down.curvedto.point.bottomright.up"
        case .photo: return "photo"
        case .streak: return "flame.fill"
        case .sticker: return "square.on.square"
        }
    }

    /// The sticker is not a story frame — it's a thing you drop ON one, so it
    /// carries its own aspect and a transparent surround.
    var designSize: CGSize {
        self == .sticker
            ? CGSize(width: 320, height: 200)
            : CGSize(width: 360, height: 640)
    }

    var isTransparent: Bool { self == .sticker }
}

/// Everything a story face can draw. Built by the caller from whatever it has —
/// every field is optional, and a face simply omits what it wasn't given rather
/// than printing a zero.
struct MADStoryContent: Identifiable {
    let id = UUID()
    var distanceMiles: Double?
    var paceSecondsPerMile: Double?
    var durationSeconds: Double?
    var streak: Int?
    var totalMiles: Double?
    /// When the walk happened — drives `RouteArtView`'s time-of-day cast.
    var date: Date?
    /// Already-formatted date, for callers holding the server's string rather
    /// than a Date (`PostStats.date`). Preferred over formatting `date`.
    var dateText: String?
    var coordinates: [CLLocationCoordinate2D] = []
    var routeColor: Color = MADTheme.Colors.madRed
    var photo: UIImage?
    var avatar: RouteArtAvatar?

    var hasRoute: Bool { coordinates.count >= 2 }
    var hasPhoto: Bool { photo != nil }

    /// Which faces this walk can actually draw. Never offer a Route tab for an
    /// indoor walk — an empty canvas reads as the feature being broken.
    var availableFaces: [MADStoryFace] {
        var out: [MADStoryFace] = []
        if hasPhoto { out.append(.photo) }
        if hasRoute { out.append(.route) }
        if (streak ?? 0) > 0 { out.append(.streak) }
        out.append(.sticker)
        return out
    }

    /// Photo first when there is one: a face gets engagement, a map doesn't,
    /// and the whole point is that this actually gets posted.
    var defaultFace: MADStoryFace { availableFaces.first ?? .sticker }
}

// MARK: - The card

struct MADStoryCard: View {
    let content: MADStoryContent
    let face: MADStoryFace

    var body: some View {
        Group {
            switch face {
            case .route: routeFace
            case .photo: photoFace
            case .streak: streakFace
            case .sticker: stickerFace
            }
        }
        .frame(width: face.designSize.width, height: face.designSize.height)
    }

    // MARK: Faces

    private var routeFace: some View {
        ZStack {
            storyBackground(glow: content.routeColor)
            VStack(alignment: .leading, spacing: 0) {
                wordmark
                    .padding(.horizontal, 26)
                    .padding(.top, 26)

                RouteArtView.still(
                    coordinates: content.coordinates,
                    routeColor: content.routeColor,
                    authorAvatar: content.avatar,
                    showsMileMarkers: true,
                    paletteDate: content.date,
                    size: CGSize(width: 360, height: 300)
                )
                .frame(height: 300)

                Spacer(minLength: 0)
                statBlock
                    .padding(.horizontal, 26)
                footer
            }
        }
    }

    private var photoFace: some View {
        ZStack {
            storyBackground(glow: content.routeColor)
            if let photo = content.photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 360, height: 640)
                    .clipped()
                // The stats sit over the lower third, so it has to be readable
                // whatever the photo is doing down there.
                LinearGradient(
                    colors: [.black.opacity(0.45), .clear, .clear, .black.opacity(0.88)],
                    startPoint: .top, endPoint: .bottom
                )
            }
            VStack(alignment: .leading, spacing: 0) {
                wordmark
                    .padding(.horizontal, 26)
                    .padding(.top, 26)
                Spacer(minLength: 0)
                statBlock
                    .padding(.horizontal, 26)
                footer
            }
        }
    }

    private var streakFace: some View {
        ZStack {
            storyBackground(glow: MADTheme.Colors.warning)
            VStack(alignment: .leading, spacing: 0) {
                wordmark
                    .padding(.horizontal, 26)
                    .padding(.top, 26)

                Spacer(minLength: 0)
                VStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 78))
                        .foregroundStyle(
                            LinearGradient(colors: [Color(red: 1, green: 0.78, blue: 0.32),
                                                    MADTheme.Colors.warning],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .shadow(color: MADTheme.Colors.warning.opacity(0.5), radius: 22)
                        .accessibilityHidden(true)
                    Text("\(content.streak ?? 0)")
                        .font(.system(size: 96, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                    Text("DAY STREAK")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .tracking(4)
                        .foregroundColor(Color(red: 1, green: 0.75, blue: 0.38))
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)

                HStack(spacing: 0) {
                    ForEach(streakStats, id: \.0) { stat in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stat.0)
                                .font(.system(size: 11, weight: .black, design: .rounded))
                                .tracking(1.4)
                                .foregroundColor(.white.opacity(0.4))
                            Text(stat.1)
                                .font(.system(size: 19, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 4)
                footer
            }
        }
    }

    /// Transparent by design — this one is handed to Instagram as a sticker the
    /// walker drags onto a story they're already making.
    private var stickerFace: some View {
        VStack(alignment: .leading, spacing: 10) {
            wordmark
            Text(distanceText)
                .font(.system(size: 54, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: 18) {
                ForEach(compactStats, id: \.0) { stat in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(stat.0)
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .tracking(1.2)
                            .foregroundColor(.white.opacity(0.42))
                        Text(stat.1)
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.66))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
        )
    }

    // MARK: Shared chrome

    private func storyBackground(glow: Color) -> some View {
        ZStack {
            // The app's own ground, so a story reads as Mile A Day before a
            // single word is read.
            LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.08, blue: 0.10),
                    Color(red: 0.12, green: 0.06, blue: 0.08),
                    Color(red: 0.08, green: 0.04, blue: 0.06),
                    Color(red: 0.05, green: 0.02, blue: 0.04),
                ],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [glow.opacity(0.42), glow.opacity(0.10), .clear],
                center: UnitPoint(x: 0.82, y: 0.10),
                startRadius: 10, endRadius: 300
            )
        }
        .ignoresSafeArea()
    }

    private var wordmark: some View {
        HStack(spacing: 8) {
            MADLogoMark(size: 26, shadow: false)
            Text("MILE A DAY")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .tracking(2.4)
                .foregroundColor(.white)
        }
    }

    @ViewBuilder
    private var statBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            if content.distanceMiles != nil {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(distanceText)
                        .font(.system(size: 74, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                    Text("MI")
                        .font(.system(size: 21, weight: .black, design: .rounded))
                        .tracking(1)
                        .foregroundColor(.white.opacity(0.55))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }

            if !secondaryStats.isEmpty {
                HStack(spacing: 26) {
                    ForEach(secondaryStats, id: \.0) { stat in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stat.0)
                                .font(.system(size: 11, weight: .black, design: .rounded))
                                .tracking(1.4)
                                .foregroundColor(.white.opacity(0.4))
                            Text(stat.1)
                                .font(.system(size: 21, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.white)
                        }
                    }
                }
            }

            if let streak = content.streak, streak > 0 {
                streakChip(streak)
            }
        }
    }

    private func streakChip(_ streak: Int) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "flame.fill")
                .font(.system(size: 15, weight: .bold))
                .accessibilityHidden(true)
            Text("\(streak) DAY STREAK")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .tracking(0.6)
                .monospacedDigit()
        }
        .foregroundColor(Color(red: 1, green: 0.77, blue: 0.4))
        .padding(.horizontal, 15)
        .padding(.vertical, 8)
        .background(Capsule().fill(MADTheme.Colors.warning.opacity(0.17)))
        .overlay(Capsule().stroke(MADTheme.Colors.warning.opacity(0.55), lineWidth: 1.5))
        .fixedSize()
    }

    /// The download driver. A story link isn't tappable for most accounts, so
    /// this is the only route back to the app from a screenshot.
    private var footer: some View {
        HStack {
            wordmark
            Spacer()
            Text("mileaday.run")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
        }
        .padding(.horizontal, 26)
        .padding(.top, 18)
        .padding(.bottom, 28)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.11))
                .frame(height: 1)
                .padding(.horizontal, 26)
        }
    }

    // MARK: Values

    private var distanceText: String {
        (content.distanceMiles ?? 0).milesText
    }

    private var secondaryStats: [(String, String)] {
        var out: [(String, String)] = []
        if let pace = content.paceSecondsPerMile, pace > 0 {
            out.append(("PACE", RunStatsStickerView.paceText(pace)))
        }
        if let duration = content.durationSeconds, duration > 0 {
            out.append(("TIME", RunStatsStickerView.durationText(duration)))
        }
        if let text = displayDate {
            out.append(("DATE", text))
        }
        return out
    }

    private var compactStats: [(String, String)] {
        var out: [(String, String)] = []
        if let pace = content.paceSecondsPerMile, pace > 0 {
            out.append(("PACE", RunStatsStickerView.paceText(pace)))
        }
        if let streak = content.streak, streak > 0 {
            out.append(("STREAK", "\(streak)"))
        }
        return out
    }

    private var streakStats: [(String, String)] {
        var out: [(String, String)] = []
        if let distance = content.distanceMiles {
            out.append(("TODAY", "\(distance.milesText) mi"))
        }
        if let pace = content.paceSecondsPerMile, pace > 0 {
            out.append(("PACE", RunStatsStickerView.paceText(pace)))
        }
        if let total = content.totalMiles, total > 0 {
            out.append(("TOTAL", "\(Int(total)) mi"))
        }
        return out
    }

    private var displayDate: String? {
        if let text = content.dateText, !text.isEmpty { return text }
        if let date = content.date { return Self.dateFormatter.string(from: date) }
        return nil
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}

// MARK: - Rendering

extension MADStoryCard {
    /// The image handed to Instagram (or the share sheet).
    ///
    /// Scale 3 over the design size, so a story frame lands at exactly the
    /// 1080×1920 Instagram wants and the sticker at 960×600. Opaque for the
    /// full-frame faces and transparent for the sticker — a sticker with a
    /// black rectangle behind it is not a sticker.
    @MainActor
    static func render(content: MADStoryContent, face: MADStoryFace) -> UIImage? {
        let renderer = ImageRenderer(
            content: MADStoryCard(content: content, face: face)
        )
        renderer.scale = 3.0
        renderer.isOpaque = !face.isTransparent
        return renderer.uiImage
    }
}
