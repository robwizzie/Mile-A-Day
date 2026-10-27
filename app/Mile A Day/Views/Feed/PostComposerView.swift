import SwiftUI
import CoreLocation
import HealthKit

/// Run stats handed to the composer to seed the overlay sticker. Carries every
/// stat we can show; `datum(for:)` formats one and returns nil when there's no
/// data, so unavailable stats simply don't appear (and aren't offered as toggles).
struct RunStatsInput: Equatable {
    var distance: Double
    var paceSecondsPerMile: Double?
    var durationSeconds: Double?
    var streak: Int?
    /// The competition the poster can put on the photo — name, standing and
    /// podium — resolved by `RunPostService` from the competitions they're in
    /// TODAY. Nil on a day with none, which is what keeps the toggle out of
    /// the tray. Never shown unless the poster switches it on: a competition
    /// is a closed group, so announcing one is the poster's call, not the
    /// card's.
    /// Declared HERE, between streak and calories, because the memberwise
    /// initialiser takes arguments in declaration order and the builders
    /// pass it right after `streak:`.
    var competition: CompetitionStickerData? = nil
    var calories: Double?
    var steps: Int?
    var workoutId: String?
    var dateText: String?
    /// Post-goal bonus workout: the sticker bakes the distance as "+0.14 mi"
    /// so a short extra walk reads as ADDED miles, not the whole day.
    var isExtra: Bool = false
    /// Ghost race, set only when this workout BEAT its ghost. Read straight off
    /// the HKWorkout's metadata, so it's keyed to the right workout by
    /// construction — no separate stash to fall out of sync.
    /// Six of the eight `RunStatsInput` call sites don't pass these. A `var`
    /// optional already gets an implicit nil in the memberwise init, so the
    /// `= nil` is for the reader, not the compiler — unlike a `let` optional,
    /// which is genuinely required (that's what broke the celebration's
    /// #Preview when `GhostRaceWin.friendUserId` was added).
    var ghostMarginSeconds: Double? = nil
    var ghostTargetSeconds: Double? = nil

    var snapshot: PostStats {
        PostStats(
            distance: distance,
            pace: paceSecondsPerMile,
            duration: durationSeconds,
            streak: streak,
            date: dateText,
            calories: calories,
            steps: steps,
            ghost_margin_seconds: ghostMarginSeconds,
            ghost_target_seconds: ghostTargetSeconds
        )
    }

    /// Stats that actually have data, in a stable display order.
    func availableStats() -> [RunStatKind] {
        RunStatKind.allCases.filter { datum(for: $0) != nil }
    }

    func datum(for kind: RunStatKind) -> RunStatDatum? {
        switch kind {
        case .distance:
            let miles = distance.milesText
            return RunStatDatum(kind: .distance, value: isExtra ? "+\(miles) mi" : "\(miles) mi")
        case .pace:
            guard let p = paceSecondsPerMile, p > 0 else { return nil }
            return RunStatDatum(kind: .pace, value: "\(RunStatsStickerView.paceText(p)) /mi")
        case .duration:
            guard let d = durationSeconds, d > 0 else { return nil }
            return RunStatDatum(kind: .duration, value: RunStatsStickerView.durationText(d))
        case .streak:
            guard let s = streak, s > 0 else { return nil }
            return RunStatDatum(kind: .streak, value: "\(s)")
        case .calories:
            guard let c = calories, c > 0 else { return nil }
            return RunStatDatum(kind: .calories, value: "\(Int(c.rounded())) cal")
        case .steps:
            guard let st = steps, st > 0 else { return nil }
            return RunStatDatum(kind: .steps, value: "\(Self.grouped(st))")
        case .date:
            guard let d = dateText, !d.isEmpty else { return nil }
            return RunStatDatum(kind: .date, value: d)
        case .competition:
            // The value is the tray's label — the sticker itself draws the
            // podium rather than this string (`competitionBlock`).
            guard let c = competition else { return nil }
            return RunStatDatum(kind: .competition, value: c.inlineText)
        }
    }

    /// Shared decimal formatter — allocating a `NumberFormatter` per render was
    /// a needless per-frame cost. Rendering is @MainActor, so sharing is safe.
    private static let stepsFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    private static func grouped(_ n: Int) -> String {
        stepsFormatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

/// Where a post goes. Stories are the ephemeral 24h moment; the feed is the
/// permanent record. Cross-posting is a deliberate "Both" choice, not the default.
enum PostDestination: String, CaseIterable, Identifiable {
    case story, feed, both
    var id: String { rawValue }

    var title: String {
        switch self {
        case .story: return "Story"
        case .feed: return "Feed"
        case .both: return "Both"
        }
    }

    var icon: String {
        switch self {
        case .story: return "circle.dashed"
        case .feed: return "square.stack"
        case .both: return "square.on.circle"
        }
    }

    var footnote: String {
        switch self {
        case .story: return "Your friends can watch it for 24 hours — once they've done their own mile today."
        case .feed: return "Stays on your profile and in your friends' feeds. Today's photo unlocks for each friend once they've done their mile."
        case .both: return "Your story for 24 hours, plus your profile and your friends' feeds. Friends see the photo once they've done their mile."
        }
    }

    var toStory: Bool { self != .feed }
    var toFeed: Bool { self != .story }
}

/// What the composer did, reported back to the presenter.
enum PostComposeOutcome {
    case cancelled
    case published(toFeed: Bool, toStory: Bool)
    /// No connection: the finished post is waiting in `PostDraftStore` and
    /// posts itself when the signal is back.
    case savedDraft(toFeed: Bool, toStory: Bool)
}

/// Where the photo on the canvas came from. Declared to the server, which holds
/// the two sources to two different clocks: a live capture to the ten minutes
/// after the walk, a camera-roll pick to the rest of the day (it's already
/// proven to be FROM the walk by when it was shot — see
/// `WorkoutPhotoImportPicker`). Mirrors `PostPhotoSource` in postService.ts.
enum PostPhotoSource: String {
    case camera
    case library
    /// A photo that's already been posted, being promoted onto the feed.
    case existing
}

@MainActor
final class PostComposerViewModel: ObservableObject {
    @Published var pickedImage: UIImage?
    /// FRONT & BACK: the other camera's frame. `pickedImage` is always the one
    /// shown LARGE, so swapping which is which is a straight exchange of these
    /// two — the editor, the flatten and the published card then all describe
    /// the same arrangement without anyone tracking a separate "which is big"
    /// flag that could disagree with the pictures.
    ///
    /// nil on every ordinary post, which is what makes the whole feature
    /// inert until someone chooses it.
    @Published var dualSecondary: UIImage?
    /// Whether the LARGE frame is the selfie. Flips with every swap, and is
    /// read only by `dualHint` — which is the point: the line under the
    /// canvas names what is actually in the corner right now, so the effect
    /// of the tap is legible before anyone makes it.
    @Published var dualPrimaryWasFront = false
    /// Which corner the inset is baked into. The poster drags it there, and
    /// it rides the post so the feed card can put its tap target on the
    /// picture rather than where the picture used to be.
    @Published var dualInsetCorner: DualInsetCorner = .topTrailing
    /// How `pickedImage` was obtained, so publish can declare it. Set by
    /// whichever affordance produced the photo; seeded to `.camera` for an
    /// `initialImage`, which is always a mid-run snap taken with our camera.
    @Published var photoSource: PostPhotoSource = .camera
    @Published var caption: String = ""
    /// Where the post goes. Starts nil ON PURPOSE — the user must make the
    /// story/feed/both choice themselves before Share enables, so nobody
    /// posts somewhere they didn't mean to.
    @Published var destination: PostDestination?
    /// The stickers on the photo, bottom to top. On a FRONT & BACK with
    /// `separateViewStickers` on, these are the BACK view's (the arrangement
    /// with the back camera large); otherwise they're on every view.
    @Published var stickers: [PlacedSticker] = []
    /// The FRONT view's own stickers. Read only while `separateViewStickers`
    /// is on and the post is a pair — `layer(frontView:)` is the one reader.
    @Published var frontStickers: [PlacedSticker] = []
    /// FRONT & BACK: each view (back camera large / front camera large) gets
    /// its own stickers, so tapping to swap on the feed reveals a different
    /// set. Off by default — one set on both is what nearly everyone wants.
    @Published var separateViewStickers = false
    /// The run-stats sticker's style, accent and stats. Shared by both views:
    /// what differs per view is whether it's there and where.
    @Published var config: StickerConfig
    /// The last post's stickers (`StickerMemory`), read once at open: they
    /// give a re-added kind its remembered spot. Never put back on by
    /// themselves — a new photo starts with the stats sticker only.
    private let memory: StickerMemory?
    /// The sticker last tapped on the photo. A second tap on it cycles its
    /// style; the tray follows it to its tab.
    @Published var selectedStickerId: UUID?
    /// Just dropped on the bin, kept for the undo toast.
    @Published var removedSticker: RemovedSticker?
    /// Saliency + brightness per photo on the canvas, keyed by image identity
    /// and pruned to the current frames (so a freed image's address can never
    /// match a stale entry).
    @Published private(set) var photoAnalyses: [ObjectIdentifier: PhotoAnalysis] = [:]
    @Published var isPublishing = false
    /// `publish()` couldn't reach the server and kept the post in
    /// `PostDraftStore` instead. It returned true — the post is made, just
    /// not delivered — and the view reports `.savedDraft`.
    @Published var savedAsDraft = false
    @Published var errorMessage: String?
    /// Whether the linked workout has a GPS route to offer alongside the photo.
    @Published var hasRoute = false
    /// User choice: show the route map with this post (carousel slide 2).
    ///
    /// Seeded from the standing preference rather than hardcoded to true. The
    /// toggle is unchanged and still wins for this post — this only decides
    /// where it opens, so someone whose walks all start at their front door
    /// stops re-making the same decision every day and only has to remember
    /// once. `.ask` (the default) is exactly the old behaviour.
    @Published var includeRoute = RouteSharingDefault.current.initialIncludeRoute
    /// The run's actual GPS trace, so the share step can show the map that's
    /// about to be posted rather than asking people to take the toggle on
    /// faith. Read from HealthKit — the same samples the sync ships to the
    /// server, so the preview and the published slide draw the same path.
    @Published var routePreview: [CLLocationCoordinate2D]?
    @Published var isLoadingRoutePreview = false
    /// The route sticker's trace — the whole of `routePreview`, projected
    /// once. nil = no route sticker to offer.
    @Published var routeSticker: RouteStickerTrace?
    /// The walk has a route the route STICKER can draw. Unlike `hasRoute`
    /// (the map slide), this ignores "Share route maps": the sticker is a
    /// line with no map under it, the poster's own per-post choice. Stealth
    /// Mode still wins, because that walk's trace never leaves the phone.
    @Published var routeStickerAvailable = false
    /// One-shot guard: a run whose route enumerates to nothing must not
    /// re-query on every re-render (`routePreview == nil` can't tell "not
    /// loaded yet" from "loaded, and there's nothing to draw").
    private var hasLoadedRoutePreview = false
    /// Workout type behind the route ("running"/"walking"/…), so the preview
    /// uses the same accent colour the feed card will.
    @Published var routeWorkoutType = "running"
    /// Collab post: the friends this mile was run with, in pick order.
    ///
    /// A list, not one person: a walk with three people on it is the ordinary
    /// case here, and the one-slot picker meant two of them went uncredited
    /// (or, worse, opened their own posts for the same walk). The server has
    /// carried multiple credited people since Buddy Walks — `post_coauthors`
    /// plus a legacy scalar mirroring the first, so a shipped client still
    /// renders a coherent two-person collab — this is the manual path finally
    /// using it. Capped at `maxCoauthors`, matching the server's cap.
    @Published var coauthors: [BackendUser] = []

    /// The server's MAX_POST_COAUTHORS. Enforced there; mirrored here only so
    /// the picker can stop offering rather than have picks silently dropped.
    static let maxCoauthors = 8
    /// Buddy Walk context, set when the composer is opened from the recap's
    /// post wizard. Everyone who finished the walk is credited automatically —
    /// the point of a buddy recap is that you didn't do it alone, so making
    /// the poster re-pick their walking partners by hand would be busywork.
    /// `buddyCoauthorIds` is authoritative when non-empty; `coauthor` (the
    /// manual picker) is left alone so a normal post is unaffected.
    @Published var buddyCoauthorIds: [String] = []
    @Published var buddySessionId: String?
    /// Non-nil turns this composer into "add MY photo to the crew's post".
    ///
    /// The walk already has a card — a friend made it — and everything below
    /// (camera, canvas, sticker, the flatten) is identical; only the terminal
    /// call differs. That's the whole point: the alternative, and what shipped,
    /// was that the second person on a walk opened a SECOND post for the same
    /// walk, because "add my picture to that one" had nowhere to go.
    ///
    /// While set there is no destination to choose — a slide on someone else's
    /// feed card is not a story and not a post of your own — so `publish()`
    /// treats it as feed-bound and the share step hides the picker.
    @Published var crewPhotoPostId: String?
    /// Not an error: this walk is already on the feed and this photo is
    /// joining that card. It has its own slot because red error text beside
    /// "tap Share again" reads as a warning about the very thing we are
    /// asking for — and the user did nothing wrong. The one report this
    /// exists for was a second walker being told to "delete it first",
    /// about a post that was never hers.
    @Published var crewHandoffNotice: String?
    /// Display names for `buddyCoauthorIds`, same order — set once by the
    /// wizard so the share step can SHOW the crew it's crediting instead of
    /// offering the manual co-poster picker beside an invisible roster.
    var buddyCrewNames: [String] = []
    /// Publish was rejected server-side for unaccepted guidelines — the view
    /// re-presents the gate when this flips true.
    @Published var needsTermsGate = false
    /// Display-only composite for the share step's thumbnail. Rendered from the
    /// SAME `flatten()` the upload uses, so the thumbnail is literally the image
    /// that ships — sticker baked in, cropped 4:5 exactly as the feed shows it.
    /// Never read by `publish()`: that re-flattens, so the upload path stays
    /// byte-for-byte what it has always been.
    @Published var previewComposite: UIImage?
    /// FRONT & BACK's other arrangement, rendered the same way, for the share
    /// step's side-by-side "what friends see". nil on a single photo.
    @Published var previewCompositeSwapped: UIImage?

    /// Published: the competition sticker text is re-resolved after a fresh
    /// competitions fetch (see `refreshCompetitionSticker`), and the tray
    /// has to re-read what's available when it lands.
    @Published var stats: RunStatsInput
    /// Captured on-screen canvas size (points), reused to render the composite.
    var canvasSize: CGSize = .zero

    /// The competition sticker's standing is a snapshot of whatever the
    /// Compete tab last loaded — "2nd of 6" from Tuesday on a Friday post,
    /// or nothing at all on a day the tab was never opened. Fetch fresh on
    /// open and re-resolve; a failed fetch leaves the snapshot alone.
    @MainActor
    func refreshCompetitionSticker() async {
        let service = CompetitionService()
        guard (try? await service.loadCompetitions()) != nil else { return }
        liveCompetitions = RunPostService.competitionStickers()
        await warmCompetitionFaces(liveCompetitions)
        let fresh = liveCompetitions.first { $0.competitionId == stats.competition?.competitionId }
            ?? liveCompetitions.first
        guard fresh != stats.competition else { return }
        stats.competition = fresh
        if fresh == nil {
            config.enabled.removeAll { $0 == .competition }
        }
    }

    /// Pull every face the competition sticker might draw into `FeedImageCache`
    /// before it is baked.
    ///
    /// The sticker is rendered into the photo by `ImageRenderer`, which drives
    /// no view lifecycle and cannot wait on a download, so it reads the cache
    /// SYNCHRONOUSLY and falls back to initials on a miss. Without this warm-up
    /// the first post of a session would bake initials for everyone even though
    /// the pictures exist — the miss has to be the exception, not the norm.
    @MainActor
    private func warmCompetitionFaces(_ competitions: [CompetitionStickerData]) async {
        let urls = Set(competitions.flatMap { competition in
            competition.rows.flatMap { row in
                [row.avatarURL] + row.members.map(\.avatarURL)
            }
        }.compactMap { $0 }.filter { !$0.isEmpty })
        guard !urls.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask { _ = await RouteAvatarImageLoader.loadImage(for: url) }
            }
        }
    }

    /// Every competition the poster could put on this photo, soonest-ending
    /// first. More than one and the tray offers a choice — otherwise the
    /// sticker would silently pick for them, and the one it picks is rarely
    /// the one the walk was for.
    @Published var liveCompetitions: [CompetitionStickerData] = []

    /// The competition this post will CARRY, as opposed to the ones the author
    /// happens to be in. Nil unless the overlay is on, the competition block is
    /// one of the enabled stats, and one is actually selected — all three, or a
    /// chip would appear on a card that never showed the competition.
    var stickeredCompetitionId: String? {
        guard renderedStickers.contains(where: { $0.kind == .stats }),
              config.isOn(.competition) else { return nil }
        return stats.competition?.competitionId
    }

    /// Switch the sticker to a different competition (tray tap). Turns the
    /// sticker on, since choosing one is asking for it.
    @MainActor
    func selectCompetition(_ competition: CompetitionStickerData) {
        stats.competition = competition
        if !config.isOn(.competition) { config.enabled.append(.competition) }
    }

    init(
        stats: RunStatsInput,
        initialImage: UIImage? = nil,
        initialSecondary: UIImage? = nil,
        initialPrimaryWasFront: Bool = false
    ) {
        self.stats = stats
        var cfg = StickerConfig.load()
        // Drop any remembered stats that aren't available today, and make sure
        // at least one available stat is shown.
        let available = Set(stats.availableStats())
        cfg.enabled = cfg.enabled.filter { available.contains($0) }
        if cfg.enabled.isEmpty { cfg.enabled = Array(available.prefix(1)) }
        self.config = cfg
        // A new photo starts clean: only the stats sticker — THIS walk's
        // numbers, on unless it was turned off last time — back at its size
        // and spot (StickerConfig sanitizes on decode; ranges live there
        // too). The last post's other stickers are NOT put back on: a Flamey,
        // a badge or a number left over from yesterday's photo reads as a
        // mistake on today's. The memory only decides where a kind lands
        // when the poster adds it again (`addSticker`).
        let memory = StickerMemory.load()
        self.memory = memory
        var seeded: [PlacedSticker] = []
        if memory?.statsOn ?? true {
            seeded.append(PlacedSticker(kind: .stats,
                                        pos: CGPoint(x: cfg.posX, y: cfg.posY),
                                        scale: cfg.scale,
                                        rotation: Angle(degrees: cfg.rotation)))
        }
        self.stickers = seeded
        // Seed a pre-chosen photo (mid-run snap) AFTER all stored properties
        // are initialized — the @Published setter touches self.
        self.pickedImage = initialImage
        // A mid-walk FRONT & BACK press arrives as a PAIR and has to be
        // restored as one, or the walk's best shot publishes as whichever
        // frame happened to be large and quietly drops the other half.
        if initialImage != nil, let initialSecondary {
            self.dualSecondary = initialSecondary
            self.dualPrimaryWasFront = initialPrimaryWasFront
        }
        // A mid-run snap was shot DURING the walk and is already in the camera
        // roll, so it's the library tier, not a live capture. Labelling it
        // `.camera` would let the ten-minute countdown reject a photo whose
        // whole claim to the walk is the timestamp it already carries.
        if initialImage != nil { self.photoSource = .library }
    }

    /// Adding a slide to the crew's post — no destination to pick, so nothing
    /// to wait for beyond the photo itself.
    var isCrewPhoto: Bool { crewPhotoPostId != nil }

    var canPublish: Bool {
        pickedImage != nil && (isCrewPhoto || destination != nil) && !isPublishing && !savedAsDraft
    }

    /// A photo on the canvas IS the draft — the caption and sticker ride with it.
    /// Gates the discard confirmation.
    var hasDraft: Bool { pickedImage != nil }

    // MARK: Stickers

    /// The layer the editor shows and the tray edits: the view whose camera
    /// is LARGE right now. Only a pair with separate stickers has two.
    var editsFrontStickers: Bool {
        separateViewStickers && isDualPhoto && dualPrimaryWasFront
    }

    var activeStickers: [PlacedSticker] {
        get { editsFrontStickers ? frontStickers : stickers }
        set {
            if editsFrontStickers { frontStickers = newValue } else { stickers = newValue }
        }
    }

    /// The stickers drawn on the view with the front (`true`) or back camera
    /// large. A single photo, or a pair sharing one set, always reads
    /// `stickers`.
    func layer(frontView: Bool) -> [PlacedSticker] {
        separateViewStickers && isDualPhoto && frontView ? frontStickers : stickers
    }

    /// Every sticker that will be baked into some uploaded picture.
    var renderedStickers: [PlacedSticker] {
        separateViewStickers && isDualPhoto ? stickers + frontStickers : stickers
    }

    var stickerContext: StickerRenderContext {
        StickerRenderContext(input: stats, config: config, route: routeSticker)
    }

    func sticker(in slot: PostStickerKind.Slot) -> PlacedSticker? {
        activeStickers.first { $0.kind.slot == slot }
    }

    /// A picker tap, Instagram-style: the sticker lands on the photo,
    /// focused, ready to move. One-per-photo kinds (the stats card, the
    /// route, each number) restyle the one already there and bring it to the
    /// front instead of stacking a duplicate.
    func addSticker(_ kind: PostStickerKind) {
        var layer = activeStickers
        if kind.isSingleton, let i = layer.firstIndex(where: { $0.kind.slot == kind.slot }) {
            var existing = layer.remove(at: i)
            if kind != .stats { existing.kind = kind }
            layer.append(existing)
            selectedStickerId = existing.id
        } else {
            // A kind the poster has placed before goes back to THEIR spot
            // (unless one is already sitting there); anything new finds the
            // emptiest part of the photo.
            var placed: PlacedSticker
            if let remembered = memory?.remembered(kind),
               !layer.contains(where: { $0.kind == kind }) {
                placed = remembered
            } else {
                placed = PlacedSticker(kind: kind, pos: freshPosition(for: kind, in: layer))
            }
            placed.text = capturedText(for: kind)
            layer.append(placed)
            selectedStickerId = placed.id
        }
        activeStickers = layer
    }

    /// The poster's own words, typed in the text editor, landing focused in
    /// the middle the way Instagram's do.
    func addText(_ text: String, style: TextStickerStyle, accent: StickerAccent?, width: CGFloat? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var placed = PlacedSticker(kind: .text(style), pos: CGPoint(x: 0.5, y: 0.45))
        placed.text = String(trimmed.prefix(Self.maxStickerText))
        placed.accent = accent
        placed.textWidth = width
        var layer = activeStickers
        layer.append(placed)
        activeStickers = layer
        selectedStickerId = placed.id
    }

    /// Re-typed text on an existing text sticker; emptied, it goes.
    func updateText(id: UUID, text: String, style: TextStickerStyle, accent: StickerAccent?,
                    width: CGFloat? = nil) {
        var layer = activeStickers
        guard let i = layer.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            layer.remove(at: i)
            if selectedStickerId == id { selectedStickerId = nil }
        } else {
            layer[i].text = String(trimmed.prefix(Self.maxStickerText))
            layer[i].kind = .text(style)
            layer[i].accent = accent
            layer[i].textWidth = width
        }
        activeStickers = layer
    }

    /// The focused bar's line-width slider, live.
    func setTextWidth(id: UUID, width: CGFloat) {
        var layer = activeStickers
        guard let i = layer.firstIndex(where: { $0.id == id }) else { return }
        layer[i].textWidth = width.clamped(to: TextPostSticker.widthRange)
        activeStickers = layer
    }

    /// Long enough for a caption-ish line, short enough to stay a sticker.
    static let maxStickerText = 80

    /// Words a badge freezes the moment it's added, so the bake can't
    /// disagree with what was on screen.
    func capturedText(for kind: PostStickerKind) -> String? {
        guard case .badge(let badge) = kind else { return nil }
        switch badge {
        case .dayCount:
            guard let streak = stats.streak, streak > 0 else { return nil }
            return "DAY \(streak)"
        case .clock:
            let now = Date()
            let hour = Calendar.current.component(.hour, from: now)
            let part: String
            switch hour {
            case 4..<12: part = "MORNING MILE"
            case 12..<17: part = "AFTERNOON MILE"
            case 17..<21: part = "EVENING MILE"
            default: part = "NIGHT MILE"
            }
            let time = now.formatted(date: .omitted, time: .shortened).uppercased()
            return "\(time) · \(part)"
        case .buddies:
            // First names: it's a sticker, not a byline.
            let names = (buddyCrewNames.isEmpty ? coauthors.map(\.displayName) : buddyCrewNames)
                .map { name in name.split(separator: " ").first.map { String($0) } ?? name }
            guard !names.isEmpty else { return nil }
            let list = names.count <= 2
                ? names.joined(separator: " & ")
                : "\(names[0]), \(names[1]) & \(names.count - 2) MORE"
            return "WITH \(list)".uppercased()
        default:
            return nil
        }
    }

    /// Badges worth offering for THIS walk: no crew badge on a solo walk, no
    /// day count without a streak.
    var offeredBadges: [FunBadge] {
        FunBadge.allCases.filter { badge in
            switch badge {
            case .buddies: return !(buddyCrewNames.isEmpty && coauthors.isEmpty)
            case .dayCount: return (stats.streak ?? 0) > 0
            default: return true
            }
        }
    }

    /// A gesture landed: the sticker takes the transform it was let go at,
    /// and goes on top.
    func commitTransform(id: UUID, pos: CGPoint, scale: CGFloat, rotation: Angle) {
        var layer = activeStickers
        guard let i = layer.firstIndex(where: { $0.id == id }) else { return }
        var sticker = layer.remove(at: i)
        sticker.pos = pos
        sticker.scale = scale
        sticker.rotation = rotation
        layer.append(sticker)
        activeStickers = layer
    }

    /// VoiceOver's move and resize actions.
    func nudgeSticker(id: UUID, dx: CGFloat, dy: CGFloat) {
        var layer = activeStickers
        guard let i = layer.firstIndex(where: { $0.id == id }) else { return }
        layer[i].pos = CGPoint(x: (layer[i].pos.x + dx).clamped(to: StickerConfig.posXRange),
                               y: (layer[i].pos.y + dy).clamped(to: StickerConfig.posYRange))
        activeStickers = layer
    }

    func resizeSticker(id: UUID, by factor: CGFloat) {
        var layer = activeStickers
        guard let i = layer.firstIndex(where: { $0.id == id }) else { return }
        layer[i].scale = (layer[i].scale * factor).clamped(to: StickerConfig.scaleRange)
        activeStickers = layer
    }

    /// The focused sticker's own colour.
    func setAccent(_ accent: StickerAccent, for id: UUID) {
        var layer = activeStickers
        guard let i = layer.firstIndex(where: { $0.id == id }) else { return }
        // The stats card's colour is its config's, which is what the next
        // post remembers.
        if layer[i].kind == .stats {
            config.accent = accent
            layer[i].accent = nil
        } else {
            layer[i].accent = accent
        }
        activeStickers = layer
    }

    func accent(of sticker: PlacedSticker) -> StickerAccent { sticker.accent ?? config.accent }

    func removeSticker(in slot: PostStickerKind.Slot) {
        activeStickers.removeAll { $0.kind.slot == slot }
    }

    func removeSticker(id: UUID) {
        activeStickers.removeAll { $0.id == id }
    }

    /// The sticker just handled goes on top, so the one you last touched is
    /// never stuck under another.
    func bringStickerToFront(id: UUID) {
        var layer = activeStickers
        guard let i = layer.firstIndex(where: { $0.id == id }), i != layer.count - 1 else { return }
        layer.append(layer.remove(at: i))
        activeStickers = layer
    }

    /// The emptiest good spot on the photo being edited — off its subject
    /// (Vision saliency), the other stickers, the inset and the top pills.
    private func freshPosition(for kind: PostStickerKind, in layer: [PlacedSticker]) -> CGPoint {
        StickerPlacement.bestSpot(for: kind, analysis: analysis(for: pickedImage),
                                  existing: layer, inset: normalizedInsetRect)
    }

    /// The FRONT & BACK inset as a canvas fraction, nil on a single photo.
    var normalizedInsetRect: CGRect? {
        guard isDualPhoto else { return nil }
        let ref = canvasSize.width > 0 ? canvasSize : CGSize(width: 100, height: 125)
        let r = DualPhotoLayout.insetRect(in: ref, corner: dualInsetCorner)
        return CGRect(x: r.minX / ref.width, y: r.minY / ref.height,
                      width: r.width / ref.width, height: r.height / ref.height)
    }

    // MARK: Photo analysis

    func analysis(for image: UIImage?) -> PhotoAnalysis? {
        image.flatMap { photoAnalyses[ObjectIdentifier($0)] }
    }

    /// Analyse whichever frames are on the canvas and not yet analysed; drop
    /// entries for frames that are gone.
    func analyzePhotos() async {
        let current = [pickedImage, dualSecondary].compactMap { $0 }
        let ids = Set(current.map { ObjectIdentifier($0) })
        photoAnalyses = photoAnalyses.filter { ids.contains($0.key) }
        for image in current where photoAnalyses[ObjectIdentifier(image)] == nil {
            let result = await PhotoAnalysis.analyze(image)
            // Still on the canvas after the await?
            guard pickedImage === image || dualSecondary === image else { continue }
            photoAnalyses[ObjectIdentifier(image)] = result
        }
    }

    /// Whether `sticker` sits on a bright part of `image` — the photo LARGE
    /// in the arrangement it's drawn on.
    func isOnBright(_ sticker: PlacedSticker, image: UIImage?) -> Bool {
        guard let analysis = analysis(for: image) else { return false }
        switch sticker.kind {
        case .number, .route: break
        // The stats card, the badges and Flamey's tag carry their own
        // backdrops.
        case .stats, .flamey, .basicFlamey, .badge, .text, .emoji, .pack: return false
        }
        let box = StickerPlacement.box(of: sticker.kind, at: sticker.pos, scale: sticker.scale)
        return analysis.brightness(in: box) > StickerPlacement.brightThreshold
    }

    // MARK: Tap, cycle, undo

    /// The selected sticker, if it is still on the view being edited — a
    /// swap to the other view's set, or a removal, leaves none.
    var selectedSticker: PlacedSticker? {
        guard let id = selectedStickerId else { return nil }
        return activeStickers.first { $0.id == id }
    }

    /// First tap focuses (its colours and options appear under the photo);
    /// a tap on the focused one cycles its style, Instagram-style.
    func tapSticker(id: UUID) {
        guard activeStickers.contains(where: { $0.id == id }) else { return }
        if selectedStickerId == id {
            cycleStyle(of: id)
        } else {
            selectedStickerId = id
        }
    }

    func cycleStyle(of id: UUID) {
        var layer = activeStickers
        guard let i = layer.firstIndex(where: { $0.id == id }) else { return }
        switch layer[i].kind {
        case .stats:
            config.style = config.style.cycled
            return
        case .flamey(let f):
            layer[i].kind = .flamey(f.cycled)
        case .basicFlamey(let f):
            layer[i].kind = .basicFlamey(f.cycled)
        case .badge:
            layer[i].variant += 1
        case .text(let style):
            layer[i].kind = .text(style.cycled)
        case .emoji:
            return
        case .pack(let p):
            layer[i].kind = .pack(p.cycled)
        case .route(let s):
            layer[i].kind = .route(s.cycled)
        case .number(let k):
            // The next number this walk HAS that isn't already on the photo.
            let options = NumberPostSticker.available(for: stats)
            let taken = Set(layer.compactMap { s -> RunStatKind? in
                if case .number(let n) = s.kind { return n } else { return nil }
            })
            guard let start = options.firstIndex(of: k) else { return }
            let candidate = (1..<options.count).lazy
                .map { options[(start + $0) % options.count] }
                .first { !taken.contains($0) }
            guard let candidate else { return }
            layer[i].kind = .number(candidate)
        }
        activeStickers = layer
    }

    /// The bin's removal, undoable for a few seconds.
    func removeStickerWithUndo(id: UUID) {
        let layer = activeStickers
        guard let index = layer.firstIndex(where: { $0.id == id }) else { return }
        let removed = RemovedSticker(sticker: layer[index], index: index, frontLayer: editsFrontStickers)
        removeSticker(id: id)
        if selectedStickerId == id { selectedStickerId = nil }
        removedSticker = removed
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, self.removedSticker?.token == removed.token else { return }
            withAnimation(.easeOut(duration: 0.2)) { self.removedSticker = nil }
        }
    }

    func undoRemove() {
        guard let removed = removedSticker else { return }
        removedSticker = nil
        // Back into the layer it came out of, even if the big photo was
        // swapped since — and never as a second sticker in a taken slot.
        let front = removed.frontLayer && separateViewStickers && isDualPhoto
        var layer = front ? frontStickers : stickers
        if removed.sticker.kind.isSingleton,
           layer.contains(where: { $0.kind.slot == removed.sticker.kind.slot }) { return }
        layer.insert(removed.sticker, at: min(removed.index, layer.count))
        if front { frontStickers = layer } else { stickers = layer }
    }

    /// FRONT & BACK: give each view its own stickers, or one set for both.
    /// Splitting copies what's on now onto the other view, so nothing
    /// vanishes the moment you flip it; joining keeps the set you're looking
    /// at for both.
    func setSeparateViewStickers(_ separate: Bool) {
        guard separate != separateViewStickers else { return }
        if separate {
            frontStickers = stickers.map { $0.duplicated() }
            separateViewStickers = true
        } else {
            let keep = activeStickers
            separateViewStickers = false
            frontStickers = []
            stickers = keep
        }
    }

    /// The stats sticker has been moved/resized/tilted off its default
    /// placement. Epsilon-compared because pinch and twist land on
    /// irrational values.
    var isStatsStickerTransformed: Bool {
        guard let s = sticker(in: .stats) else { return false }
        let home = PostStickerKind.stats.defaultPosition
        return abs(s.pos.x - home.x) > 0.001
            || abs(s.pos.y - home.y) > 0.001
            || abs(s.scale - 1) > 0.001
            || abs(s.rotation.degrees) > 0.001
    }

    func resetStatsStickerPlacement() {
        var layer = activeStickers
        guard let i = layer.firstIndex(where: { $0.kind == .stats }) else { return }
        layer[i].pos = PostStickerKind.stats.defaultPosition
        layer[i].scale = 1
        layer[i].rotation = .zero
        activeStickers = layer
    }

    /// Check whether the linked workout has GPS route data, enabling the
    /// "Include route map" toggle. No route (indoor/manual) → toggle hidden.
    /// Cheap existence probe — never enumerates the route's locations.
    func checkRouteAvailability() async {
        guard !routeStickerAvailable, let workoutId = stats.workoutId else { return }
        let workout = HealthKitManager.shared.todaysWorkouts
            .first { $0.uuid.uuidString == workoutId }
        guard let workout else { return }
        // Stealth Mode: the trace stays on the phone — no toggle, no preview,
        // no route slide, no route sticker.
        guard !StealthModeStore.shared.isStealth(workout) else { return }
        routeWorkoutType = Self.workoutTypeString(workout.workoutActivityType)
        let has = await HealthKitManager.shared.hasRouteData(for: workout)
        routeStickerAvailable = has
        // Master "Share route maps" setting off → never offer the per-post
        // map toggle (the server wouldn't ship the route to friends anyway).
        hasRoute = has && NotificationPreferences.load().shareRouteMaps
    }

    /// Load the route's coordinates for the share step's preview.
    ///
    /// Deliberately NOT part of `checkRouteAvailability` — that one is a
    /// limit-1 existence probe that runs while the user is still picking a
    /// photo, and this enumerates every GPS sample of the run. It's cheap
    /// enough once, on the screen that actually draws the map, and never
    /// twice: an empty result parks `hasLoadedRoutePreview` so a route-less
    /// workout doesn't re-query on every re-render.
    func loadRoutePreview() async {
        guard routeStickerAvailable, !hasLoadedRoutePreview, !isLoadingRoutePreview,
              let workoutId = stats.workoutId else { return }
        let workout = HealthKitManager.shared.todaysWorkouts
            .first { $0.uuid.uuidString == workoutId }
        guard let workout else { return }
        isLoadingRoutePreview = true
        let locations = await HealthKitManager.shared.fetchAllRouteLocations(for: workout)
        // A single point can't draw a path — treat it as no preview rather
        // than rendering a lone dot the post won't have.
        routePreview = locations.count >= 2 ? locations.map(\.coordinate) : nil
        if let coordinates = routePreview {
            // The WHOLE line, start to finish, the way Strava draws it: the
            // sticker is the walk's shape with no map under it, so there's
            // nothing to trim. (Map slides keep the server's trim.)
            routeSticker = RouteStickerTrace.make(full: coordinates, kept: 0...(coordinates.count - 1),
                                                  key: workoutId)
        }
        hasLoadedRoutePreview = true
        isLoadingRoutePreview = false
    }

    private static func workoutTypeString(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "running"
        case .walking: return "walking"
        case .cycling: return "cycling"
        case .hiking: return "hiking"
        default: return "other"
        }
    }

    var isDualPhoto: Bool { dualSecondary != nil }

    /// The line under the editor canvas. Names the SMALL frame, because that
    /// is the one you tap and the one about to become large.
    ///
    /// It also carries more weight than it used to: the published card no
    /// longer draws a ⇄ disc on the inset, so this sentence — on your own
    /// photo, before you post — is where the tap is learned.
    var dualHint: String {
        // Per-view stickers: the corner tap is ALSO how you reach the other
        // view's stickers, so the line says which set is on screen.
        if separateViewStickers {
            // The FRONT/BACK VIEW chip beside it names the set.
            return "Tap the corner to edit the other view"
        }
        let who = dualPrimaryWasFront ? "The view's" : "You're"
        return "\(who) in the corner · tap to swap, drag to move"
    }

    /// Which camera the BIG frame came from, as a plain statement for the
    /// picker under the canvas.
    var dualLeadIsFront: Bool { dualPrimaryWasFront }

    /// Put a specific camera in the big frame. Idempotent on purpose: the
    /// picker's chips are a STATE, so tapping the one already chosen has to
    /// do nothing rather than toggle it away.
    func setDualLead(front: Bool) {
        guard isDualPhoto, front != dualPrimaryWasFront else { return }
        swapDualFrames()
    }

    /// Swap which frame is large. Called from the editor's inset tap, and it
    /// is the SAME gesture the published card offers — learn it once, in the
    /// place where the consequence is still editable.
    func swapDualFrames() {
        guard let secondary = dualSecondary, let primary = pickedImage else { return }
        pickedImage = secondary
        dualSecondary = primary
        dualPrimaryWasFront.toggle()
    }

    /// Drop the second frame. Any path that replaces the photo has to call
    /// this, or a fresh single shot inherits the previous capture's other
    /// half and publishes a flip to a photo of somewhere else.
    func clearDual() {
        // Per-view stickers go with the pair: one picture is one view, and
        // the set the poster was looking at is the one that stays. Read
        // BEFORE the frame is dropped — after it, the front layer is
        // unreachable.
        setSeparateViewStickers(false)
        dualSecondary = nil
        dualPrimaryWasFront = false
        // The corner belongs to the pair, not to the canvas: a fresh single
        // that later becomes a pair starts where every other post's does.
        dualInsetCorner = .topTrailing
    }

    /// Render the on-screen canvas (photo + sticker) to a flat JPEG-ready image
    /// at ~1080px wide, baking the overlay in. Returns nil if no photo.
    ///
    /// `swapped` renders the FRONT & BACK arrangement the other way round —
    /// the identical canvas, identical sticker, with the two frames exchanged.
    /// That second render is what gets uploaded as `dual_media_url`, and the
    /// reason both are FINISHED pictures rather than raw frames: the primary
    /// alone already has the inset baked into it, so every surface that only
    /// knows about `media_url` — the profile grid, a share card, the website's
    /// link preview, every shipped app build — shows a complete front-and-back
    /// photo with no changes at all.
    func flatten(swapped: Bool = false) -> UIImage? {
        guard let image = pickedImage, canvasSize.width > 0 else { return nil }
        if swapped && dualSecondary == nil { return nil }
        let big = swapped ? (dualSecondary ?? image) : image
        let small = swapped ? image : dualSecondary
        // Each arrangement wears the stickers of the camera that's LARGE in
        // it — with per-view stickers off, that's the same set either way.
        let bigIsFront = swapped ? !dualPrimaryWasFront : dualPrimaryWasFront
        let baked = layer(frontView: bigIsFront)
        let canvas = PostCanvas(
            image: big,
            secondary: small,
            dualCorner: dualInsetCorner,
            stickers: baked,
            context: stickerContext,
            // Judged against the photo that's LARGE in this arrangement —
            // the same call the editor makes for what's on screen.
            brightStickerIds: Set(baked.filter { isOnBright($0, image: big) }.map(\.id))
        )
        .frame(width: canvasSize.width, height: canvasSize.height)

        let renderer = ImageRenderer(content: canvas)
        renderer.scale = max(1, 1080 / canvasSize.width)
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// Who this post credits: the buddy walk's crew if it came from a recap,
    /// otherwise whoever was picked by hand. Nil rather than an empty array so
    /// an ordinary solo post sends no collab field at all.
    private var resolvedCoauthorIds: [String]? {
        let ids = buddyCoauthorIds.isEmpty
            ? coauthors.map(\.user_id)
            : buddyCoauthorIds
        return ids.isEmpty ? nil : ids
    }

    /// FRONT & BACK's swapped frame, with up to three attempts (0.5s, then
    /// 1.5s apart). nil after the last one fails — the caller then keeps the
    /// whole post as a draft rather than publishing half of the pair.
    private static func uploadDualFrame(_ image: UIImage) async -> String? {
        let backoff: [UInt64] = [500_000_000, 1_500_000_000]
        for attempt in 0...backoff.count {
            do {
                return try await PostService.uploadMedia(image)
            } catch {
                print("[PostComposer] dual frame upload attempt \(attempt + 1) failed: \(error)")
                guard attempt < backoff.count else { break }
                try? await Task.sleep(nanoseconds: backoff[attempt])
            }
        }
        return nil
    }

    func publish() async -> Bool {
        guard !isPublishing, !savedAsDraft else { return false }
        guard let flat = flatten() else {
            errorMessage = "Add a photo first."
            return false
        }
        // A crew photo has nowhere else to go — it's a slide on a card that
        // already exists — so it skips the destination gate entirely.
        let resolvedDestination: PostDestination? =
            destination ?? (isCrewPhoto ? PostDestination.feed : nil)
        guard let destination = resolvedDestination else {
            errorMessage = "Choose where to share — story, feed, or both."
            return false
        }
        isPublishing = true
        errorMessage = nil
        defer { isPublishing = false }

        // A buddy post made from the recap can open before HealthKit has
        // published the walk, so `stats.workoutId` is nil at init — and an
        // unlinked post is the one that used to slip past the server's
        // one-post-per-walk guard and land as a red, routeless second card.
        // Resolve it again at the moment of posting: by now the walk has
        // usually landed. (The server also guards on the declared session and
        // hands the post its workout once the walk links, so this is the
        // fast path, not the only one.)
        if stats.workoutId == nil, let sessionId = buddySessionId {
            let buddy = BuddySessionService.shared
            if let session = [buddy.session, buddy.lastFinishedSession]
                .compactMap({ $0 })
                .first(where: { $0.id == sessionId }),
               let resolved = RunPostService.buddyWorkoutId(
                    reconciled: session.me(buddy.currentUserId)?.workoutId,
                    startedAt: session.startedAtDate,
                    endedAt: session.endedAtDate
               )
            {
                stats.workoutId = resolved
            }
        }

        do {
            let mediaUrl = try await PostService.uploadMedia(flat)
            // The swapped arrangement, uploaded second and only for a FRONT &
            // BACK. Retried a few times, and if it STILL fails the post is
            // not published at all — it becomes a draft (the catch below)
            // and goes out whole once the signal is back. Publishing without
            // it is what put a baked inset on the feed that could never be
            // tapped: the primary made it up on a fading signal, this one
            // didn't, and nothing anywhere said so.
            var dualMediaUrl: String?
            if isDualPhoto, let swapped = flatten(swapped: true) {
                dualMediaUrl = await Self.uploadDualFrame(swapped)
                if dualMediaUrl == nil { throw DualFrameUploadError() }
            }
            if let crewPhotoPostId {
                // Everything above this line is the ordinary composer — same
                // camera, same canvas, same flatten. Only the terminal call
                // differs, which is exactly why this is a branch here and not
                // a second composer: the walk's post already exists, and this
                // photo joins it rather than opening a rival to it.
                try await PostService.addCrewPhoto(
                    postId: crewPhotoPostId,
                    mediaUrl: mediaUrl,
                    caption: caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? nil : caption,
                    photoSource: photoSource,
                    dualMediaUrl: dualMediaUrl,
                    // Only when there IS a pair: the corner describes an
                    // inset, and a single photo has none.
                    dualInsetCorner: dualMediaUrl == nil ? nil : dualInsetCorner.rawValue
                )
                // The run's photo moment is spent either way — the picture is
                // on the feed. Retire the prompt so it can't surface later
                // asking for a photo of the walk it's already on, which is the
                // exact complaint the buddy path produced before.
                if let workoutId = stats.workoutId, !workoutId.isEmpty {
                    PostedWorkoutRegistry.markPosted(workoutId)
                    CelebrationManager.shared.resolvePhotoPrompt(forWorkout: workoutId)
                }
                return true
            }
            _ = try await PostService.createPost(
                mediaUrl: mediaUrl,
                dualMediaUrl: dualMediaUrl,
                dualInsetCorner: dualMediaUrl == nil ? nil : dualInsetCorner.rawValue,
                caption: caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : caption,
                workoutId: stats.workoutId,
                shareToFeed: destination.toFeed,
                shareToStory: destination.toStory,
                stats: stats.snapshot,
                isAuto: false,
                includeRoute: includeRoute,
                // Feed posts only — the server ignores it otherwise anyway.
                //
                // Everyone goes through `coauthorUserIds`, including a single
                // manual pick: the server mirrors the FIRST of them into the
                // legacy scalar column itself, so sending both would just be
                // two ways of saying the same thing that can disagree. A buddy
                // recap's crew stays authoritative when it's set — the wizard
                // already settled who was on that walk.
                coauthorUserId: nil,
                coauthorUserIds: destination.toFeed ? resolvedCoauthorIds : nil,
                buddySessionId: destination.toFeed ? buddySessionId : nil,
                photoSource: photoSource,
                // Only when the competition is actually ON the card. A
                // competition reaches a post because the poster put it there —
                // recording one they turned off would hand the card a chip
                // for a group they chose not to mention, which is the row this
                // sticker replaced.
                competitionId: stickeredCompetitionId
            )
            // The run now has the user's one deliberate post — the server will
            // 409 `workout_already_posted` on a second, for a story-only share
            // as much as a feed one, so this is recorded regardless of
            // destination. Everything that would otherwise go on to offer this
            // run again reads it: the post-run photo prompt (which is why a
            // buddy walk posted through the recap wizard then got asked for a
            // photo it already had), the recap's own CTA, and autoPostMile.
            //
            // ONE place, on purpose: every composer entry point in the app —
            // the buddy wizard, the photo prompt, the feed FAB, a promoted
            // story — publishes through this method, so putting it at any of
            // the call sites would be the same bug waiting on the next door.
            if let workoutId = stats.workoutId, !workoutId.isEmpty {
                PostedWorkoutRegistry.markPosted(workoutId)
                CelebrationManager.shared.resolvePhotoPrompt(forWorkout: workoutId)
            }
            rememberStickerChoices()
            return true
        } catch let APIError.buddyWalkAlreadyPosted(postId, mine) {
            // This walk is already on the feed. Whose card it is decides
            // what can be offered: somebody ELSE's and this photo still has a
            // home on it, so the composer BECOMES the add-your-photo composer
            // rather than a dead end — same picture, same canvas, one more tap
            // on the same button, and `publish()` takes the crew branch above.
            //
            // Two things were wrong with what this did before. It caught
            // `.apiError`, but a 409 throws `.conflict`, so the branch was
            // unreachable and every conflict fell through to "You've already
            // shared a post for this workout. Delete it first" — advice to
            // delete a post the user does not own. And it gated on the
            // client's own `buddySessionId`, which is nil for anyone whose
            // composer opened after the walk closed (`lastFinishedSession` is
            // cleared by the recap's Done button); the SERVER resolves the
            // walk from the workout, so its answer is the one to trust.
            if mine {
                // Their OWN card, from another leg of the same walk. There is
                // no coauthor row for an author, so a handoff would 400 —
                // and there is nothing to add anyway: the walk is on the feed
                // with their name on it.
                crewPhotoPostId = nil
                crewHandoffNotice = nil
                errorMessage =
                    "You've already shared this walk — one post per walk, and "
                    + "every leg of it is on that one. Delete it if you want to "
                    + "swap the photo."
            } else if let postId, !postId.isEmpty {
                // The composer BECOMES the add-your-photo composer: the share
                // step re-renders into its crew shape (no caption, no
                // destination, no route toggle — the card owns all three) and
                // the button renames itself "Add photo". Nothing here is
                // phrased as a failure, because nothing failed.
                crewPhotoPostId = postId
                errorMessage = nil
                crewHandoffNotice =
                    "This walk is already on the feed — one post, everyone on it. "
                    + "Your photo joins it as your own slide. Tap Add photo."
            } else {
                // No post id (an older server): there is nothing to hand off
                // to, so this one IS a dead end and says where to go instead.
                errorMessage =
                    "Someone already shared this walk. Open it from your buddy "
                    + "walk recap and add your photo to it — one post, everyone on it."
            }
            return false
        } catch let APIError.apiError(message) where message == "mile_not_completed" {
            // The server recomputes this gate from ITS workouts table, so this
            // 403 while local HealthKit already shows the mile done means the
            // workout just hasn't reached the backend (sync failed or hasn't
            // fired) — tell the user that instead of "finish your mile", and
            // kick a sync so an immediate retry can succeed.
            let localDone = ProgressCalculator.isGoalCompleted(
                current: HealthKitManager.shared.todaysDistance,
                goal: UserManager.shared.currentUser.goalMiles
            )
            if localDone {
                errorMessage = "Your mile is still syncing — give it a few seconds and try again."
                Task { try? await WorkoutSyncService.shared.syncNewWorkouts() }
            } else {
                errorMessage = "Finish today's mile before you post."
            }
            return false
        } catch let APIError.apiError(message) where message == "post_window_closed" {
            // Only a LIVE capture can hit this now: the camera's ten minutes
            // lapsed while this composer sat open (a long edit, or the photo
            // was shot with seconds to spare). There's nothing to retry with
            // this shot, but the camera roll is still open all day — and the
            // photo is already in it, because the camera saves every capture.
            // So point at the door that's still open instead of a dead end.
            errorMessage = photoSource == .camera
                ? "The camera closes 10 minutes after a walk or run, and that just passed. Your shot is saved in Photos — tap Change and pick it from this walk to share it."
                : "Finish a walk or run today to share a photo from it."
            return false
        } catch let APIError.apiError(message) where message == "terms_not_accepted" {
            // Stale local acceptance — clear the memo and re-gate.
            PostService.cacheTermsAccepted(false)
            needsTermsGate = true
            errorMessage = "Please accept the community guidelines to post."
            return false
        } catch APIError.badRequest("invalid_coauthor") {
            errorMessage = "You can only co-post with an accepted friend."
            return false
        } catch APIError.conflict {
            // One deliberate post per workout — a reward, not a redo.
            errorMessage = "You've already shared a post for this workout. Delete it first if you want to post a new one."
            return false
        } catch let error where PostDraftStore.isTransient(error) {
            // No signal, or the upload died part way. The post is finished —
            // the poster arranged it and tapped Share — so it is kept whole
            // and sent when the connection is back, instead of asking them to
            // stand in a field re-tapping a button that cannot work.
            guard saveAsDraft(flat: flat, destination: destination) else {
                errorMessage = "No connection — couldn't share your post. Try again."
                return false
            }
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't share your post. Try again."
            return false
        }
    }

    /// Hand the finished post to `PostDraftStore`. Everything `publish()`
    /// would have sent goes with it, the pictures already baked.
    private func saveAsDraft(flat: UIImage, destination: PostDestination) -> Bool {
        let swapped = isDualPhoto ? flatten(swapped: true) : nil
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = PostDraft(
            id: UUID(),
            createdAt: Date(),
            localDay: DayKeyFormatter.string(from: Date()),
            caption: trimmed.isEmpty ? nil : caption,
            workoutId: stats.workoutId,
            shareToFeed: destination.toFeed,
            shareToStory: destination.toStory,
            stats: stats.snapshot,
            includeRoute: includeRoute,
            coauthorUserIds: resolvedCoauthorIds,
            buddySessionId: buddySessionId,
            crewPhotoPostId: crewPhotoPostId,
            competitionId: stickeredCompetitionId,
            photoSource: photoSource.rawValue,
            // Only with the second frame actually in hand — the corner
            // describes an inset the swapped picture has to exist for.
            dualInsetCorner: swapped == nil ? nil : dualInsetCorner.rawValue
        )
        guard PostDraftStore.shared.save(draft, primary: flat, swapped: swapped) else { return false }
        // The photo moment is answered: the post exists, it just hasn't
        // left the phone. NOT `markPosted` — if the draft is deleted the
        // walk must still be postable; the store marks it once it lands.
        if let workoutId = stats.workoutId, !workoutId.isEmpty {
            CelebrationManager.shared.resolvePhotoPrompt(forWorkout: workoutId)
        }
        rememberStickerChoices()
        savedAsDraft = true
        errorMessage = nil
        // Said in the composer, before it closes: the poster is looking
        // here, and wherever they land next may not show the draft.
        crewHandoffNotice = "No signal — your post is saved as a draft and will "
            + "post on its own when you're back online. It's at the top of your Feed."
        return true
    }

    /// Remember the user's sticker choices once a post is made (or kept as a
    /// draft), so the next one starts from them.
    private func rememberStickerChoices() {
        if let statsSticker = renderedStickers.first(where: { $0.kind == .stats }) {
            // Remember the user's overlay style — but merge back any stats
            // that were remembered and merely had no data TODAY (init
            // filters those out of the session config); otherwise one
            // treadmill day permanently erases a saved choice like pace.
            var toSave = config
            let available = Set(stats.availableStats())
            let rememberedUnavailable = StickerConfig.load().enabled
                .filter { !available.contains($0) }
            toSave.enabled = config.enabled + rememberedUnavailable
            // Remember the transform too, so the next post's sticker shows
            // up at this exact size and position.
            toSave.scale = statsSticker.scale
            toSave.posX = statsSticker.pos.x
            toSave.posY = statsSticker.pos.y
            toSave.rotation = statsSticker.rotation.degrees
            toSave.save()
        }
        // And where the rest went, so a kind added again lands in the
        // poster's spot. The main set only: per-view extras are a one-off
        // arrangement.
        StickerMemory(stickers: stickers).save()
    }
}

/// An informational line in the composer — the walk is already posted and this
/// photo is joining it. Deliberately NOT `MADTheme.Colors.error`: the error
/// slot means "you have to fix something", and this is the app explaining
/// where the picture is going.
struct ComposerNoticeBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(MADTheme.Colors.walkBlue)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(MADTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                .fill(MADTheme.Colors.walkBlue.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                        .strokeBorder(MADTheme.Colors.walkBlue.opacity(0.35), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
    }
}

/// The photo + sticker canvas (4:5). Shared by the live editor preview and the
/// ImageRenderer flatten so what you see is exactly what's uploaded.
struct PostCanvas: View {
    let image: UIImage
    /// FRONT & BACK's other frame, drawn as the corner inset. nil = an
    /// ordinary single photo, and this view is then byte-identical to what it
    /// always rendered.
    var secondary: UIImage? = nil
    /// Which corner the inset sits in — baked, so it has to match what the
    /// post will carry.
    var dualCorner: DualInsetCorner = .topTrailing
    /// Live drag only, never set by `flatten`.
    var dualDragOffset: CGSize = .zero
    /// Baked stickers, bottom to top. The live editor passes none and draws
    /// its own manipulable layers over the photo instead.
    var stickers: [PlacedSticker] = []
    var context: StickerRenderContext? = nil
    /// Stickers sitting on a bright part of the photo (`isOnBright`).
    var brightStickerIds: Set<UUID> = []

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let secondary {
                    // The inset sits UNDER the sticker: the stats overlay is
                    // the thing the poster placed, so it keeps the top of the
                    // stack. Note what is NOT here — the ⇄ glyph. That is an
                    // affordance drawn live by whoever offers the tap, and
                    // baking it into somebody's photograph forever would be a
                    // watermark nobody asked for.
                    DualPhotoView(
                        big: image,
                        small: secondary,
                        corner: dualCorner,
                        offset: dualDragOffset
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }

                if let context {
                    ForEach(stickers) { sticker in
                        PostStickerView(sticker, context: context,
                                        onBright: brightStickerIds.contains(sticker.id))
                            .scaleEffect(sticker.scale)
                            .rotationEffect(sticker.rotation)
                            .position(x: sticker.pos.x * geo.size.width,
                                      y: sticker.pos.y * geo.size.height)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
}

/// One sticker on the photo being edited — DISPLAY only. Every touch goes
/// to the single `StickerGestureSurface` above the stack (see
/// StickerGestureSurface.swift for why); this layer just draws the sticker at
/// its committed transform, or at the live one while it's under the fingers.
///
/// The sticker is wrapped in `.equatable()` (outside the transforms) so its
/// own body — drop shadow, number formatting — renders once and only its
/// transform changes per frame.
private struct StickerDisplayLayer: View {
    let sticker: PlacedSticker
    let context: StickerRenderContext
    /// Canvas size in points — the SAME value `flatten()` renders at, so the
    /// live sticker and the baked image land pixel-identically.
    let canvas: CGSize
    let edit: StickerLiveEdit
    /// Focused on the photo: a resting ring says "tap again to restyle".
    var isFocused: Bool = false
    /// The photo under it is bright — drawn the way the bake will draw it.
    var onBright: Bool = false
    /// VoiceOver's move, resize, restyle and remove.
    let onNudge: (CGFloat, CGFloat) -> Void
    let onResize: (CGFloat) -> Void
    let onCycle: () -> Void
    let onRemove: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The springy pop when the sticker first lands on the photo.
    @State private var appeared = false

    private var live: StickerLiveEdit.Live? {
        guard let live = edit.live, live.id == sticker.id else { return nil }
        return live
    }

    var body: some View {
        let moving = live
        let center = moving?.center ?? sticker.pos
        let scale = moving?.scale ?? sticker.scale
        let rotation = moving?.rotation ?? sticker.rotation
        let overBin = moving != nil && edit.overBin
        PostStickerView(sticker, context: context, onBright: onBright)
            .equatable()                       // MUST stay OUTSIDE the transforms
            // Probe OUTSIDE .equatable() but UNDER the transforms, so it
            // reports the NATURAL size (for hit-testing and the size limits)
            // and settles instead of firing per frame.
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: StickerNaturalSizeKey.self, value: geo.size)
                }
            )
            .onPreferenceChange(StickerNaturalSizeKey.self) { edit.naturalSizes[sticker.id] = $0 }
            .overlay { ring(scale: scale, moving: moving != nil) }
            .scaleEffect(scale)
            .rotationEffect(rotation)
            // Over the bin it shrinks and fades, so "let go to remove" reads
            // before anyone lets go; on arrival it pops in. Their own scale,
            // so neither ever reaches a commit.
            .scaleEffect((overBin ? 0.45 : 1) * (appeared ? 1 : 0.35))
            .opacity(overBin ? 0.6 : (appeared ? 1 : 0))
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: overBin)
            .position(x: center.x * canvas.width, y: center.y * canvas.height)
            .frame(width: canvas.width, height: canvas.height)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(sticker.kind.accessibilityName)
            .accessibilityHint("Actions move, resize, restyle or remove it.")
            .accessibilityAction(named: "Move up") { onNudge(0, -0.06) }
            .accessibilityAction(named: "Move down") { onNudge(0, 0.06) }
            .accessibilityAction(named: "Move left") { onNudge(-0.06, 0) }
            .accessibilityAction(named: "Move right") { onNudge(0.06, 0) }
            .accessibilityAction(named: "Bigger") { onResize(1.15) }
            .accessibilityAction(named: "Smaller") { onResize(1 / 1.15) }
            .accessibilityAction(named: "Change style") { onCycle() }
            .accessibilityAction(named: "Remove sticker") { onRemove() }
            .onAppear {
                guard !appeared else { return }
                if reduceMotion {
                    appeared = true
                } else {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.55)) { appeared = true }
                }
            }
    }

    /// Dashed outline while it's focused or moving. Inside the transforms
    /// (so it tracks scale and rotation) with its stroke divided by the
    /// scale, which keeps it visually constant at any size.
    @ViewBuilder
    private func ring(scale: CGFloat, moving: Bool) -> some View {
        if isFocused || moving {
            let s = max(scale, 0.01)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(moving ? 0.85 : 0.7),
                    style: StrokeStyle(lineWidth: (moving ? 1.5 : 2) / s, dash: [5 / s, 4 / s])
                )
                .padding(-5 / s)
        }
    }
}

struct PostComposerView: View {
    /// Community-guidelines acceptance, resolved before sharing is allowed
    /// (App Review 1.2 — and the server rejects un-accepted posts anyway, so
    /// gating up front beats a dead-end publish error). The CAMERA is never
    /// blocked on this: capturing preserves the moment (and lands in the
    /// user's camera roll) — only composing/sharing waits for acceptance.
    private enum TermsState { case unknown, accepted, needsAcceptance }

    /// The composer's second screen. Edit is the stack ROOT, so this enum only
    /// needs the one case: `path` is `[]` on edit and `[.share]` on share.
    private enum ComposerStep: Hashable { case share }

    @StateObject private var vm: PostComposerViewModel
    @StateObject private var friendService = FriendService()
    /// Drives the camera half of the screen. Taking a photo is bounded to the
    /// ten minutes after the walk; picking one out of the camera roll isn't, so
    /// this retires the capture affordances rather than locking the composer.
    @ObservedObject private var freshWindow = FreshPostWindowManager.shared
    @State private var showCamera = false
    // Library import of a photo captured DURING this walk/run (window-filtered
    // for authenticity, same as the post-run prompt). Its cover rides the
    // `canvasSection` node — a third cover on the ZStack or the background Color
    // (which already own the camera + terms covers) would silently drop one.
    @State private var showLibraryImport = false
    /// The walk's own snaps, offered right here. See `snapsFromThisWalkButton`.
    @State private var showSnapGallery = false
    /// Live translation while the inset is being dragged. Lives on the VIEW,
    /// not the model: it is a gesture in progress, and nothing that renders
    /// for upload may ever see it.
    @State private var dualDrag: CGSize = .zero
    /// The sticker under the fingers, mid-gesture (StickerGestureSurface).
    @State private var liveEdit = StickerLiveEdit()
    /// Whether the stash HAS anything, cached. `hasEntriesToday()` enumerates
    /// the sandbox directory, which is not something to do from a `body` —
    /// the dashboard's photo-waiting banner caches it for the same reason.
    @State private var hasWalkSnaps = false
    /// Seeded from the local cache so a returning poster never waits on (or
    /// races) the network check in `resolveTermsIfNeeded`.
    @State private var termsState: TermsState =
        PostService.termsAcceptedCached ? .accepted : .unknown
    @State private var showTermsGate = false
    /// Gate outcome relayed by PostTermsGateView.onAccepted, read in the
    /// cover's onDismiss — deliberately not inferred from the cache so gate
    /// internals can change without silently breaking this flow.
    @State private var gateAccepted = false
    /// The auto camera open must fire exactly once: .onAppear re-fires every
    /// time a fullScreenCover dismisses, and re-opening on each pass would
    /// trap the user in the camera with no way back.
    @State private var didAutoOpenCamera = false
    /// A buddy walk this user closed without posting, minutes ago
    /// (`BuddyPostOffer`). Asked about once, on open: post this WITH the
    /// crew, or just me. nil when the caller already settled the crew, or
    /// there's nothing to ask.
    @State private var crewOffer: BuddyPostOffer?
    @State private var askingCrewOffer = false
    /// "Saved to Photos" confirmation for the canvas Save button.
    @State private var showSavedToPhotos = false
    /// Guards against silently destroying a composed draft on Cancel.
    @State private var showDiscardConfirm = false
    /// Empty on the edit step, `[.share]` on the share step.
    @State private var path: [ComposerStep] = []
    /// Launch straight into the camera on first appear (post-run prompt flow) —
    /// the user already tapped "Take a photo" once to get here.
    let autoOpenCamera: Bool
    /// Post-run prompt flow: leaving returns to the snap picker with nothing
    /// lost, so the exit reads "‹ Back" instead of "Cancel" (which made
    /// people fear their photos would be discarded).
    let backNavigation: Bool
    let onFinished: (PostComposeOutcome) -> Void
    @Environment(\.dismiss) private var dismiss

    init(
        stats: RunStatsInput,
        autoOpenCamera: Bool = false,
        initialImage: UIImage? = nil,
        /// The other lens of a FRONT & BACK snap chosen before the composer
        /// opened (the post-run prompt's cards and its gallery).
        initialSecondary: UIImage? = nil,
        initialPrimaryWasFront: Bool = false,
        backNavigation: Bool = false,
        // Buddy Walk recap: credit everyone who finished the session.
        buddyCoauthorIds: [String] = [],
        buddySessionId: String? = nil,
        buddyCrewNames: [String] = [],
        // Set instead of the three above when the walk is ALREADY posted and
        // this composer is adding your photo to it.
        crewPhotoPostId: String? = nil,
        onFinished: @escaping (PostComposeOutcome) -> Void
    ) {
        let model = PostComposerViewModel(
            stats: stats,
            initialImage: initialImage,
            initialSecondary: initialSecondary,
            initialPrimaryWasFront: initialPrimaryWasFront
        )
        model.buddyCoauthorIds = buddyCoauthorIds
        model.buddySessionId = buddySessionId
        model.buddyCrewNames = buddyCrewNames
        model.crewPhotoPostId = crewPhotoPostId
        // EVERY door, not just the wizard. The buddy context used to be
        // supplied only by `BuddyPostWizardView`, so the same photo of the
        // same walk became a crew post from the recap and a solo post from the
        // post-run prompt, the feed FAB or the snap gallery — unlinked from
        // the session (invisible to everyone else's recap, which is what let a
        // second card be made) and crediting nobody (one route on the map
        // where the other card drew two). Resolving it here means the door
        // stops mattering.
        //
        // Never overrides what a caller passed, and never applies to the
        // crew-photo composer: that one is already adding to the walk's post.
        if crewPhotoPostId == nil, buddySessionId == nil,
           let workoutId = stats.workoutId,
           let session = RunPostService.buddySessionForWorkout(workoutId) {
            let crew = session.activeParticipants
                .filter { $0.userId != BuddySessionService.shared.currentUserId }
                .sorted { $0.bestDistance > $1.bestDistance }
            model.buddySessionId = session.id
            model.buddyCoauthorIds = crew.map(\.userId)
            model.buddyCrewNames = crew.map(\.displayName)
        }
        _vm = StateObject(wrappedValue: model)
        // Backed out of a buddy walk's post a few minutes ago? Then this post
        // is probably that walk, and the poster gets to say so rather than
        // have it go out solo (or, via the resolution above, silently with
        // a crew they didn't pick). Never when the caller already settled it
        // (the walk's own post step, a crew photo), for a different walk, or
        // once the walk is posted.
        var offer: BuddyPostOffer?
        if crewPhotoPostId == nil, buddySessionId == nil,
           let live = BuddyPostOffer.current(for: BuddySessionService.shared.currentUserId),
           live.applies(toWorkout: stats.workoutId),
           !(live.workoutId.map(PostedWorkoutRegistry.hasPost(for:)) ?? false),
           model.buddySessionId == nil || model.buddySessionId == live.sessionId {
            offer = live
        }
        _crewOffer = State(initialValue: offer)
        self.autoOpenCamera = autoOpenCamera
        self.backNavigation = backNavigation
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.black.ignoresSafeArea()
                    // Its own node: the GeometryReader, ZStack and stack all
                    // present something else already.
                    .alert(
                        crewOffer.map { "Post this with \($0.crewText)?" } ?? "",
                        isPresented: $askingCrewOffer,
                        presenting: crewOffer
                    ) { offer in
                        Button("Post with the crew") { answerCrewOffer(offer, withCrew: true) }
                        Button("Just me", role: .cancel) { answerCrewOffer(offer, withCrew: false) }
                    } message: { _ in
                        Text("You just walked together. Put it on the buddy walk's post — "
                             + "everyone's routes on one card, everyone credited.")
                    }

                GeometryReader { outer in
                    editContent(container: outer.size)
                        .frame(maxWidth: .infinity)
                        // Its own node, distinct from the NavigationStack (terms
                        // gate), the ZStack (camera) and the GeometryReader
                        // (discard dialog) — two presentations on one node
                        // silently drop one. On the VStack, not the canvas, so the
                        // node survives the empty → pinned switch a pick causes.
                        .fullScreenCover(isPresented: $showLibraryImport) {
                            WorkoutPhotoImportPicker(windows: importWindows) { result in
                                showLibraryImport = false
                                switch result {
                                case .accepted(let image):
                                    vm.pickedImage = image
                                    // A library pick is one picture, so
                                    // any FRONT & BACK frame still held
                                    // from a previous capture goes with
                                    // the photo it belonged to.
                                    vm.clearDual()
                                    // Declares the day tier to the server —
                                    // this photo is bounded by when it was
                                    // SHOT, not by when it's posted.
                                    vm.photoSource = .library
                                    vm.errorMessage = nil
                                case .acceptedPair(let primary, let secondary, let primaryWasFront):
                                    // A FRONT & BACK from the library —
                                    // restored as the pair it was taken
                                    // as, so it posts swappable.
                                    vm.clearDual()
                                    vm.pickedImage = primary
                                    vm.dualSecondary = secondary
                                    vm.dualPrimaryWasFront = primaryWasFront
                                    vm.photoSource = .library
                                    vm.errorMessage = nil
                                case .failed:
                                    vm.errorMessage = "Couldn't load that photo. Try another one."
                                case .cancelled:
                                    break
                                }
                            }
                        }
                }
                .confirmationDialog("Discard this post?", isPresented: $showDiscardConfirm,
                                    titleVisibility: .visible) {
                    Button("Discard", role: .destructive) { onFinished(.cancelled); dismiss() }
                    Button("Keep editing", role: .cancel) { }
                } message: {
                    Text("Your photo and caption won't be saved.")
                }
            }
            // The buddy flow is a numbered wizard whose first screen lives in
            // another view, so this screen has to say where it is in it. It
            // used to say "New Post" — which, arriving from a screen headed
            // "STEP 1 OF 3", read as having left the wizard rather than
            // advanced through it.
            .navigationTitle(vm.isCrewPhoto ? "Your photo" : editStepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ComposerStep.self) { _ in
                PostShareStepView(
                    vm: vm,
                    friendService: friendService,
                    shareEnabled: vm.canPublish && termsState == .accepted,
                    stepTitle: shareStepTitle,
                    onShare: share,
                    onEditMedia: { if !path.isEmpty { path.removeLast() } }
                )
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Disabled while publishing: publish() has no cancellation
                    // hook, so a Cancel racing an in-flight upload would fire
                    // onFinished twice with contradictory outcomes (the
                    // post-run prompt would auto-post the route card AND the
                    // photo post would land server-side).
                    Button(action: cancelTapped) {
                        if backNavigation {
                            HStack(spacing: 3) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Back")
                            }
                        } else {
                            Text("Cancel")
                        }
                    }
                    .foregroundColor(.white.opacity(vm.isPublishing ? 0.4 : 1))
                    .disabled(vm.isPublishing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next", action: goToShareStep)
                        .fontWeight(.semibold)
                        .foregroundColor(vm.pickedImage != nil
                            ? MADTheme.Colors.madRed : .white.opacity(0.3))
                        .disabled(vm.pickedImage == nil)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .fullScreenCover(isPresented: $showCamera) {
                // Stamp the source on the SET, not on opening the camera: a
                // cancelled camera must not relabel a library photo already on
                // the canvas as a live capture and re-charge it the countdown.
                MADCameraView(
                    image: Binding(
                        get: { vm.pickedImage },
                        set: { image in
                            vm.pickedImage = image
                            if image != nil {
                                // A fresh single REPLACES whatever was on the
                                // canvas, so the previous capture's other half
                                // must go with it — otherwise the post ships a
                                // flip to a photo of somewhere else entirely.
                                vm.clearDual()
                                vm.photoSource = .camera
                                vm.errorMessage = nil
                            }
                        }
                    ),
                    allowsDual: true,
                    onDualCapture: { capture in
                        vm.pickedImage = capture.primary
                        vm.dualSecondary = capture.secondary
                        vm.dualPrimaryWasFront = capture.primaryWasFront
                        vm.photoSource = .camera
                        vm.errorMessage = nil
                    }
                )
            }
            // A stale composite must never survive a trip back to the editor.
            .onChange(of: path) { _, newPath in
                if newPath.isEmpty {
                    vm.previewComposite = nil
                    vm.previewCompositeSwapped = nil
                }
            }
            .onAppear {
                if crewOffer != nil {
                    // The question first; the camera (if this door opens
                    // one) once it's answered.
                    askingCrewOffer = true
                } else {
                    autoOpenCameraIfNeeded()
                }
                // Resolved HERE, not in the button's own lifecycle: the button
                // renders nothing when the answer is false, and a view whose
                // body is empty never gets `.onAppear` to flip it true.
                hasWalkSnaps = MidRunPhotoStash.hasEntriesToday()
            }
            .task { await resolveTermsIfNeeded() }
            .task { await vm.refreshCompetitionSticker() }
            .task { await vm.checkRouteAvailability() }
            // The Route sticker needs the trace itself, not just the probe —
            // loaded once, as soon as there is a route to load.
            .task(id: vm.routeStickerAvailable) { await vm.loadRoutePreview() }
            .task { try? await friendService.loadFriends() }
            // Re-probe once a photo lands — todaysWorkouts may not have been
            // loaded yet when the composer first appeared.
            .onChange(of: vm.pickedImage) { _, newImage in
                guard newImage != nil else { return }
                Task { await vm.checkRouteAvailability() }
            }
            // A gate held back while the camera cover was up presents as soon
            // as the camera closes.
            .onChange(of: showCamera) { _, isUp in
                guard !isUp else { return }
                presentGateIfNeeded()
            }
            // The server rejected a publish for unaccepted terms (stale local
            // state) — re-gate instead of dead-ending on the error label.
            .onChange(of: vm.needsTermsGate) { _, needs in
                guard needs else { return }
                vm.needsTermsGate = false
                termsState = .needsAcceptance
                presentGateIfNeeded()
            }
        }
        // The guidelines gate hangs off the NavigationStack ITSELF, not the root
        // content. Share can trigger it from the pushed share step, and a cover
        // presented from a view that's been navigated away from is unreliable —
        // the stack is the one node that's current on both steps. It's also a
        // node of its own, which matters: the ZStack owns the camera cover, the
        // ScrollView owns the discard dialog, and the canvas owns the library
        // import. Two presentations on one node silently drop one.
        .fullScreenCover(isPresented: $showTermsGate, onDismiss: {
            if gateAccepted {
                gateAccepted = false
                termsState = .accepted
                vm.errorMessage = nil
            } else if vm.pickedImage == nil {
                // Declined with nothing composed — nothing to lose;
                // back out so the post-run prompt / feed takes over.
                onFinished(.cancelled)
                dismiss()
            } else {
                // Declined with a draft on screen: NEVER destroy it.
                // Share stays locked (tapping it re-opens the gate);
                // Cancel remains the deliberate way out.
                vm.errorMessage = "Accept the community guidelines to share your post."
            }
        }) {
            PostTermsGateView { gateAccepted = true }
        }
    }

    // MARK: - Edit layout

    /// Pinned: with a photo on the canvas, the photo stays put
    /// and only the controls under it scroll, so a sticker
    /// tapped in the tray lands where you can see it. On a
    /// short screen the canvas is SCALED down (never laid out
    /// narrower — a narrower canvas would bake every sticker
    /// relatively bigger), and its own controls are counter-
    /// scaled back to full size (`canvasSection(displayScale:)`).
    @ViewBuilder
    private func editContent(container: CGSize) -> some View {
        let logicalWidth = max(container.width - MADTheme.Spacing.md * 2, 1)
        let logicalHeight = logicalWidth * 5 / 4
        let roomForCanvas = container.height - MADTheme.Spacing.md
            - MADTheme.Spacing.sm - Self.pinnedTrayMinimum
        let displayScale = min(1, max(Self.minimumCanvasScale, roomForCanvas / logicalHeight))
        VStack(spacing: 0) {
            if vm.pickedImage != nil {
                canvasSection(displayScale: displayScale)
                    .frame(width: logicalWidth)
                    .scaleEffect(displayScale, anchor: .top)
                    .frame(width: logicalWidth, height: logicalHeight * displayScale, alignment: .top)
                    .padding(.top, MADTheme.Spacing.md)
                    .padding(.bottom, MADTheme.Spacing.sm)
                ScrollView {
                    VStack(spacing: MADTheme.Spacing.lg) {
                        // Directly under the photo it decides the shape of.
                        dualLeadPicker
                        StickerActionBar(vm: vm)
                        composerMessages
                    }
                    .padding(.horizontal, MADTheme.Spacing.md)
                    .padding(.top, MADTheme.Spacing.sm)
                    .padding(.bottom, MADTheme.Spacing.md)
                }
                // A hairline where the tray slides under the photo.
                .overlay(alignment: .top) {
                    LinearGradient(colors: [.black, .black.opacity(0)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 10)
                        .allowsHitTesting(false)
                }
            } else {
                ScrollView {
                    VStack(spacing: MADTheme.Spacing.lg) {
                        canvasSection()
                        // A photo snapped DURING this walk/run is a valid post,
                        // not just a fresh camera shot — mirrors the post-run
                        // prompt's "Choose from this walk". Only offered when the
                        // post is tied to a workout (empty state only).
                        if vm.stats.workoutId != nil {
                            snapsFromThisWalkButton
                            chooseFromLibraryButton
                        }
                        composerMessages
                    }
                    .padding(MADTheme.Spacing.md)
                }
            }
        }
    }

    // MARK: - Step titles

    /// A buddy walk's post is a THREE-step wizard that starts in
    /// `BuddyPostWizardView` ("STEP 1 OF 3 · THE CREW") and finishes in this
    /// composer, so these two screens are steps 2 and 3 of it and have to say
    /// so. Every other entry point (the feed FAB, the post-run prompt, a
    /// promoted story) is a plain one-off post and keeps the old titles —
    /// numbering a flow that has no other steps would be worse than not
    /// numbering it.
    /// Keyed on the SESSION, not on the crew list: a walk whose buddies all
    /// dropped out still came through the wizard's step 1, so it is still a
    /// three-step flow and must still be numbered like one.
    private var isBuddyWizard: Bool { vm.buddySessionId != nil }

    private var editStepTitle: String { isBuddyWizard ? "Step 2 of 3 · Photo" : "New Post" }

    /// What the pinned canvas always leaves below it: the sticker action bar
    /// (the picker itself is a sheet), so the photo gets the most room.
    private static let pinnedTrayMinimum: CGFloat = 170
    /// Below this the photo is too small to place anything on; the tray
    /// scrolls instead.
    private static let minimumCanvasScale: CGFloat = 0.55

    /// The notice and error lines, under the tray (or the empty canvas).
    @ViewBuilder
    private var composerMessages: some View {
        if let notice = vm.crewHandoffNotice {
            ComposerNoticeBanner(text: notice)
        }
        if let error = vm.errorMessage {
            Text(error)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(MADTheme.Colors.error)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var shareStepTitle: String { isBuddyWizard ? "Step 3 of 3 · Share" : "Share" }

    // MARK: - Step actions

    /// Advance to the share step, baking the thumbnail from the CURRENT canvas.
    /// Guarded on `canvasSize` so a composite is never rendered before the canvas
    /// has been laid out (which would produce a differently-scaled sticker than
    /// the one that ultimately uploads).
    private func goToShareStep() {
        guard vm.pickedImage != nil, vm.canvasSize.width > 0 else { return }
        MADHaptics.tap()
        vm.previewComposite = vm.flatten()
        vm.previewCompositeSwapped = vm.isDualPhoto ? vm.flatten(swapped: true) : nil
        path.append(.share)
    }

    /// The one terminal action. Lives HERE, never in `PostShareStepView`: inside a
    /// `navigationDestination`, `dismiss()` pops the push instead of dismissing the
    /// composer, so publishing from there would leave the user on the edit step with
    /// a post already live.
    private func share() {
        switch termsState {
        case .accepted:
            Task {
                let ok = await vm.publish()
                guard ok else { return }
                // A crew photo has no destination to read — it goes on the
                // walk's existing feed card, which is a feed outcome. Without
                // this the `let dest` below failed silently and the composer
                // simply sat there with the photo already published.
                let resolved: PostDestination? =
                    vm.destination ?? (vm.isCrewPhoto ? PostDestination.feed : nil)
                guard let dest = resolved else { return }
                if vm.savedAsDraft {
                    // Long enough to read the notice `publish()` just put up.
                    MADHaptics.tap()
                    try? await Task.sleep(nanoseconds: 2_200_000_000)
                    onFinished(.savedDraft(toFeed: dest.toFeed, toStory: dest.toStory))
                    dismiss()
                    return
                }
                // The day's post is made; nothing left to offer the crew for.
                BuddyPostOffer.clear()
                onFinished(.published(toFeed: dest.toFeed, toStory: dest.toStory))
                dismiss()
            }
        case .needsAcceptance:
            // Not allowed to post yet — the button routes to the guidelines
            // instead of a dead upload.
            presentGateIfNeeded()
        case .unknown:
            // Still resolving; the gate auto-presents if the answer comes back
            // unaccepted.
            break
        }
    }

    /// Cancel with a draft asks first. `backNavigation` deliberately skips the
    /// dialog: that button reads "‹ Back", a navigational affordance, and it returns
    /// to the post-run prompt which still holds the mid-run snaps and re-offers them
    /// — nothing is actually lost. "Cancel" was renamed to "Back" on that path
    /// precisely because people feared losing photos; a destructive dialog there
    /// would undo that fix.
    private func cancelTapped() {
        if backNavigation || !vm.hasDraft {
            onFinished(.cancelled)
            dismiss()
        } else {
            showDiscardConfirm = true
        }
    }

    // MARK: - Crew offer

    /// The auto camera fires exactly once (see `didAutoOpenCamera`).
    private func autoOpenCameraIfNeeded() {
        guard autoOpenCamera, !didAutoOpenCamera, vm.pickedImage == nil else { return }
        didAutoOpenCamera = true
        requestCamera()
    }

    /// "Post with the crew" makes this post exactly what the walk's own post
    /// step would have: the session and the crew it credits. "Just me" drops
    /// any crew the composer resolved by itself. Either way the question is
    /// spent.
    private func answerCrewOffer(_ offer: BuddyPostOffer, withCrew: Bool) {
        BuddyPostOffer.clear()
        crewOffer = nil
        if withCrew {
            vm.buddySessionId = offer.sessionId
            vm.buddyCoauthorIds = offer.crewIds
            vm.buddyCrewNames = offer.crewNames
        } else {
            vm.buddySessionId = nil
            vm.buddyCoauthorIds = []
            vm.buddyCrewNames = []
        }
        // After the alert is down: the camera (if this door opens one), and
        // a guidelines gate that waited for the question.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            autoOpenCameraIfNeeded()
            presentGateIfNeeded()
        }
    }

    // MARK: - Guidelines gate

    /// Opening the camera never waits on the guidelines — see TermsState. It
    /// does wait on the ten-minute window: a capture past it can't be posted,
    /// so offering the shutter would spend the user's moment on a publish the
    /// server refuses.
    private func requestCamera() {
        guard MADCameraView.isAvailable, cameraAllowed else { return }
        showCamera = true
    }

    /// May a fresh capture still be taken? A composer with no linked workout
    /// has no camera roll to fall back on (the importer needs a workout to
    /// bound capture time), so it keeps the camera — the server's mile gate is
    /// what stops it, exactly as before the split.
    private var cameraAllowed: Bool {
        vm.stats.workoutId == nil || freshWindow.isCameraOpen
    }

    private func resolveTermsIfNeeded() async {
        guard termsState == .unknown else { return }
        if PostService.termsAcceptedCached {
            termsState = .accepted
            return
        }
        // Failed check (offline) ⇒ treat as not accepted: the gate explains
        // the block and Share stays locked, while the camera keeps working so
        // the moment itself is never lost.
        let accepted = (try? await PostService.termsStatus())?.accepted ?? false
        termsState = accepted ? .accepted : .needsAcceptance
        presentGateIfNeeded()
    }

    /// Present the gate once no other cover is up — presenting while the
    /// camera cover (or the crew question) is up would drop the presentation
    /// entirely; both re-try this once they're down.
    private func presentGateIfNeeded() {
        guard termsState == .needsAcceptance, !showCamera, !showTermsGate,
              !askingCrewOffer else { return }
        showTermsGate = true
    }

    // MARK: - FRONT & BACK

    /// Which camera leads, as the choice it actually is.
    ///
    /// Tapping the inset already swaps, and the hint line says so — but that
    /// is a GESTURE, and the arrangement is a DECISION the poster is making
    /// about their own photo. A decision deserves a control that states the
    /// current answer without being operated: this row says which camera is
    /// big right now and puts the other one a single tap away, which is also
    /// the only form in which "I want the selfie to be the big one" is
    /// answerable by someone who never discovers the tap.
    ///
    /// Below the canvas rather than on it. The bottom of the photo already
    /// holds the hint, the sticker is draggable anywhere, and a control that
    /// changes what gets published should not be competing with either.
    @ViewBuilder
    private var dualLeadPicker: some View {
        if vm.isDualPhoto {
            HStack(spacing: 10) {
                Text("BIG PHOTO")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                HStack(spacing: 4) {
                    dualLeadChip(
                        title: "Back", icon: "camera.fill", front: false)
                    dualLeadChip(
                        title: "Front", icon: "person.fill", front: true)
                }
                .padding(4)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 2)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: vm.dualLeadIsFront)
        }
    }

    private func dualLeadChip(title: String, icon: String, front: Bool) -> some View {
        let selected = vm.dualLeadIsFront == front
        return Button {
            guard !selected else { return }
            MADHaptics.tap()
            withAnimation(.easeInOut(duration: 0.22)) { vm.setDualLead(front: front) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .black))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundColor(selected ? .black : .white.opacity(0.7))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(selected ? Color.white : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) camera as the big photo")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - Canvas

    /// - Parameter displayScale: how far the pinned canvas is scaled down to
    ///   fit a short screen. The controls drawn ON it (Save, Change, the hint
    ///   and the undo toast) are scaled back up by its inverse, so they stay
    ///   full size and full-size tappable however small the photo is drawn.
    private func canvasSection(displayScale: CGFloat = 1) -> some View {
        let counter = 1 / max(displayScale, 0.01)
        return GeometryReader { geo in
            let width = geo.size.width
            let height = width * 5 / 4
            Group {
                if let image = vm.pickedImage {
                    ZStack {
                        // Photo only. Stickers are SEPARATE display layers
                        // over it, and every touch on them goes to ONE gesture
                        // surface, so moving a sticker never re-renders this
                        // canvas or the rest of the composer.
                        PostCanvas(
                            image: image,
                            secondary: vm.dualSecondary,
                            dualCorner: vm.dualInsetCorner,
                            dualDragOffset: dualDrag
                        )
                        // Pass geo.size — the exact value flatten() renders
                        // at (via vm.canvasSize) — for pixel-perfect parity.
                        let context = vm.stickerContext
                        let layer = vm.activeStickers
                        ForEach(layer) { placed in
                            StickerDisplayLayer(
                                sticker: placed,
                                context: context,
                                canvas: geo.size,
                                edit: liveEdit,
                                isFocused: vm.selectedStickerId == placed.id,
                                onBright: vm.isOnBright(placed, image: image),
                                onNudge: { dx, dy in vm.nudgeSticker(id: placed.id, dx: dx, dy: dy) },
                                onResize: { vm.resizeSticker(id: placed.id, by: $0) },
                                onCycle: { vm.cycleStyle(of: placed.id) },
                                onRemove: {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        vm.removeStickerWithUndo(id: placed.id)
                                    }
                                }
                            )
                            .transition(.opacity)
                        }
                        StickerEditingOverlay(edit: liveEdit, canvas: geo.size)
                        StickerGestureSurface(
                            stickers: layer,
                            canvas: geo.size,
                            edit: liveEdit,
                            focusedId: vm.selectedStickerId,
                            onBegin: { id in
                                // Instagram focuses whatever you grab.
                                if vm.selectedStickerId != id { vm.selectedStickerId = id }
                            },
                            onCommit: { id, pos, scale, rotation in
                                vm.commitTransform(id: id, pos: pos, scale: scale, rotation: rotation)
                            },
                            onRemove: { id in
                                withAnimation(.easeOut(duration: 0.15)) {
                                    vm.removeStickerWithUndo(id: id)
                                }
                            },
                            onTap: { id in
                                MADHaptics.tap()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    vm.tapSticker(id: id)
                                }
                            },
                            onTapEmpty: {
                                guard vm.selectedStickerId != nil else { return }
                                withAnimation(.easeOut(duration: 0.15)) { vm.selectedStickerId = nil }
                            }
                        )
                        // VoiceOver reaches the stickers themselves.
                        .accessibilityHidden(true)
                        // The swap, learned HERE where it is still editable:
                        // the exact gesture the published card will offer, on
                        // the exact rectangle, so by the time anyone meets it
                        // on somebody else's photo they have already done it.
                        //
                        // ABOVE the gesture surface, which spans the whole
                        // canvas: a sticker parked over the inset must not
                        // swallow the one tap that corner is for, and the
                        // sticker stays draggable everywhere else.
                        if vm.isDualPhoto {
                            DualInsetMover(
                                canvas: CGSize(width: width, height: height),
                                corner: vm.dualInsetCorner,
                                onSwap: {
                                    MADHaptics.tap()
                                    withAnimation(.easeInOut(duration: 0.22)) {
                                        vm.swapDualFrames()
                                    }
                                },
                                // Live, unanimated: the inset has to sit
                                // under the finger, and a spring on every
                                // drag frame lags behind it.
                                onDragChanged: { dualDrag = $0 },
                                onDrop: { landed in
                                    guard landed != vm.dualInsetCorner else { return }
                                    MADHaptics.tap()
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                        vm.dualInsetCorner = landed
                                    }
                                }
                            )
                        }
                    }
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous))
                    // Track the LIVE geometry (initial + every later pass) —
                    // a size captured once on appear can go stale (e.g. first
                    // layout while the camera cover is up) and flatten() would
                    // render the sticker at a different relative size than the
                    // preview. geo.size is already 4:5 via the aspectRatio.
                    .onChange(of: geo.size, initial: true) { _, size in
                        guard size.width > 0 else { return }
                        vm.canvasSize = size
                    }
                    .overlay(alignment: .topTrailing) {
                        changePhotoControl.padding(10)
                            .scaleEffect(counter, anchor: .topTrailing)
                            .modifier(HiddenWhileEditing(edit: liveEdit))
                    }
                    // Keep a copy exactly as composed — stats sticker baked
                    // in (the camera already saved the RAW shot at capture).
                    .overlay(alignment: .topLeading) {
                        Button {
                            guard let flat = vm.flatten() else { return }
                            PhotoRollSaver.save(flat)
                            MADHaptics.success()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                showSavedToPhotos = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                withAnimation(.easeOut(duration: 0.25)) { showSavedToPhotos = false }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: showSavedToPhotos
                                    ? "checkmark.circle.fill" : "square.and.arrow.down")
                                    .font(.system(size: 12, weight: .bold))
                                Text(showSavedToPhotos ? "Saved" : "Save")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(showSavedToPhotos ? .green : .white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(.black.opacity(0.5)))
                        }
                        .padding(10)
                        .disabled(showSavedToPhotos)
                        .scaleEffect(counter, anchor: .topLeading)
                        .modifier(HiddenWhileEditing(edit: liveEdit))
                    }
                    .overlay(alignment: .bottom) {
                        canvasFooter
                            .padding(.horizontal, 10)
                            .padding(.bottom, 8)
                            .frame(width: geo.size.width * displayScale)
                            .scaleEffect(counter, anchor: .bottom)
                            .modifier(HiddenWhileEditing(edit: liveEdit))
                    }
                    // Subject + brightness for placing and drawing stickers,
                    // whenever a frame changes.
                    .task(id: ObjectIdentifier(image)) { await vm.analyzePhotos() }
                    .task(id: vm.dualSecondary.map { ObjectIdentifier($0) }) { await vm.analyzePhotos() }
                } else {
                    photoPlaceholder.frame(width: width, height: height)
                }
            }
        }
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
    }

    /// The one line along the photo's bottom edge, most urgent first: the
    /// undo for a sticker just binned, what a second tap on the selected
    /// sticker does, which view's stickers are on screen, then the gesture
    /// hint. One slot, so they never stack into a pile of pills.
    @ViewBuilder
    private var canvasFooter: some View {
        if let removed = vm.removedSticker {
            HStack(spacing: 10) {
                Text("Sticker removed")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                Button {
                    MADHaptics.tap()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { vm.undoRemove() }
                } label: {
                    Text("Undo")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(MADTheme.Colors.madRed)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Undo removing \(removed.sticker.kind.accessibilityName)")
            }
            .lineLimit(1)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(.black.opacity(0.7)))
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(removed.token)
        } else {
            HStack(spacing: 6) {
                if vm.separateViewStickers, vm.isDualPhoto {
                    // Which set you're editing, named on the photo itself.
                    Text(vm.dualLeadIsFront ? "FRONT VIEW" : "BACK VIEW")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(0.8)
                        .foregroundColor(.black)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color.white))
                }
                if let hint = canvasHint {
                    hint
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(.black.opacity(0.45)))
                }
            }
            .transition(.opacity)
        }
    }

    private var canvasHint: Text? {
        if vm.selectedSticker != nil {
            return Text("Tap again to change style")
        }
        if vm.isDualPhoto {
            // Outranks the sticker hint while it is showing: dragging a
            // sticker is a thing people already expect from a photo editor,
            // and the swap is not.
            return Text(vm.dualHint)
        }
        if !vm.activeStickers.isEmpty {
            return Text("Drag · pinch to resize · twist · drop on ")
                + Text(Image(systemName: "trash.fill"))
                + Text(" to remove")
        }
        return nil
    }

    /// Swapping the photo used to mean "Retake" and nothing else — the library
    /// option vanished the moment a photo existed, so a user who'd picked the wrong
    /// mid-run snap had to go through the camera to get back. A `Menu` offers both.
    ///
    /// Once the camera window closes the retake item drops out and the menu
    /// collapses to a plain library button: swapping the photo is still
    /// available all day, just not by shooting a new one.
    ///
    /// `Menu` rides UIKit's context-menu machinery rather than the sheet/cover
    /// presentation slot, so it costs no cover node (see the cover comments above).
    @ViewBuilder
    private var changePhotoControl: some View {
        if vm.stats.workoutId != nil {
            if cameraAllowed {
                Menu {
                    Button { requestCamera() } label: {
                        Label("Take a new photo", systemImage: "camera.fill")
                    }
                    Button { showLibraryImport = true } label: {
                        Label("Choose from this walk or run", systemImage: "photo.on.rectangle")
                    }
                } label: {
                    changePhotoPill(icon: "camera.fill")
                }
            } else {
                Button { showLibraryImport = true } label: {
                    changePhotoPill(icon: "photo.on.rectangle")
                }
            }
        } else {
            Button { requestCamera() } label: { changePhotoPill(icon: "camera.fill") }
        }
    }

    private func changePhotoPill(icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
            Text("Change")
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Capsule().fill(.black.opacity(0.5)))
    }

    /// The empty canvas. While the camera window runs it leads with the
    /// shutter and shows how long is left; once that lapses the SAME slot leads
    /// with the camera roll instead of going grey, because a photo from the
    /// walk is still perfectly postable — only capturing a new one isn't.
    @ViewBuilder
    private var photoPlaceholder: some View {
        if cameraAllowed {
            cameraPlaceholder
        } else {
            libraryPlaceholder
        }
    }

    private var cameraPlaceholder: some View {
        Button { requestCamera() } label: {
            VStack(spacing: MADTheme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(MADTheme.Colors.redGradient)
                        .frame(width: 84, height: 84)
                        .shadow(color: MADTheme.Colors.madRed.opacity(0.4), radius: 16, y: 6)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(spacing: 4) {
                    Text(MADCameraView.isAvailable ? "Take a photo" : "Camera unavailable")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text(MADCameraView.isAvailable
                        ? "Snap today's walk or run — camera keeps it real."
                        : "A camera is required to share a post.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, MADTheme.Spacing.lg)
                }

                if MADCameraView.isAvailable {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill").font(.system(size: 13, weight: .bold))
                        Text("Open camera").font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Capsule().fill(MADTheme.Colors.redGradient))
                    .padding(.top, 2)
                }

                // Say what the clock is for, right where the shutter is. It's
                // a deadline on the CAMERA only — never on the post — so the
                // line has to name what happens next, or a countdown reads as
                // "post now or lose it".
                if MADCameraView.isAvailable, vm.stats.workoutId != nil,
                   freshWindow.isCameraOpen {
                    cameraCountdownChip
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(placeholderBackground)
        }
        .buttonStyle(.plain)
        .disabled(!MADCameraView.isAvailable)
    }

    /// Countdown on the camera, with the reassurance attached. Uses the native
    /// `Text(timerInterval:)` so it ticks without a timer of ours.
    private var cameraCountdownChip: some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                // `timer` is SF Symbols 1 — deployment target is iOS 17, where
                // a symbol added after SF Symbols 5 renders as a blank box.
                Image(systemName: "timer")
                    .font(.system(size: 11, weight: .bold))
                Text("Camera closes in")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text(
                    timerInterval: (freshWindow.windowOpenedAt ?? Date())...freshWindow.windowEndDate,
                    countsDown: true
                )
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
            }
            .foregroundColor(.white.opacity(0.85))

            Text("Photos from this \(activityNoun) stay postable all day.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.top, 2)
    }

    /// The camera window has closed, so the camera roll leads. Deliberately not
    /// a locked-out state: nothing has been lost, the entry point just moved.
    private var libraryPlaceholder: some View {
        Button { showLibraryImport = true } label: {
            VStack(spacing: MADTheme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(MADTheme.Colors.redGradient)
                        .frame(width: 84, height: 84)
                        .shadow(color: MADTheme.Colors.madRed.opacity(0.4), radius: 16, y: 6)
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(spacing: 4) {
                    Text("Add a photo from your \(activityNoun)")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Text("The camera closes 10 minutes after you finish — but any photo you took out there is still good to post today.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, MADTheme.Spacing.lg)
                }

                HStack(spacing: 6) {
                    Image(systemName: "photo.badge.plus").font(.system(size: 13, weight: .bold))
                    Text("Choose a photo").font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Capsule().fill(MADTheme.Colors.redGradient))
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(placeholderBackground)
        }
        .buttonStyle(.plain)
    }

    private var placeholderBackground: some View {
        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
            .fill(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7]))
                    .foregroundColor(.white.opacity(0.2))
            )
    }

    /// "walk" / "run" for copy, from the workout this post is attached to.
    private var activityNoun: String {
        guard let wid = vm.stats.workoutId,
              let workout = HealthKitManager.shared.todaysWorkouts
                .first(where: { $0.uuid.uuidString == wid }) else { return "walk or run" }
        return workout.workoutActivityType == .walking ? "walk" : "run"
    }

    /// The photos taken DURING this walk, offered where the post is made.
    ///
    /// `MidRunPhotoStash` was read by exactly one screen — the post-run photo
    /// prompt — so the moment you arrived at the composer any other way, the
    /// shots you took out there were unreachable and the only offer was the
    /// camera roll. On a buddy walk that is the ordinary path (the recap and
    /// its post wizard are what open after the walk, and neither knew the
    /// stash existed), which is why "it didn't prompt me like a normal walk
    /// does — I had to go and find the photos myself".
    ///
    /// A stashed snap is `.library`, never `.camera`: its claim to the walk is
    /// the timestamp it was taken at, and the server's camera-window tier
    /// would refuse a `.camera` declaration made after the ten minutes.
    @ViewBuilder
    private var snapsFromThisWalkButton: some View {
        if hasWalkSnaps {
            Button { showSnapGallery = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "camera.on.rectangle")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Photos from this \(activityNoun)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(MADTheme.Colors.redGradient))
            }
            .buttonStyle(.plain)
            // Its OWN node: this file already hangs a fullScreenCover for the
            // library importer off `canvasSection`, and two on one node means
            // SwiftUI silently drops one.
            .fullScreenCover(isPresented: $showSnapGallery) {
                SnapGalleryView(
                    title: "Your snaps",
                    onUse: { entry in
                        // The ORIGINAL off disk — `entries()` decodes at a
                        // thumbnail size so an uncapped walk can be listed,
                        // and a post must not inherit that resolution.
                        let full = MidRunPhotoStash.fullImage(for: entry)
                        vm.pickedImage = full?.primary ?? entry.image
                        // Restore the pair, or drop whatever was on the canvas
                        // before — never inherit the previous shot's other
                        // half, which would publish a flip to somewhere else.
                        vm.clearDual()
                        if let second = full?.secondary ?? entry.secondary {
                            vm.dualSecondary = second
                            vm.dualPrimaryWasFront = entry.primaryWasFront
                        }
                        vm.photoSource = .library
                        vm.errorMessage = nil
                        showSnapGallery = false
                    },
                    onStashChanged: { hasWalkSnaps = MidRunPhotoStash.hasEntriesToday() }
                )
            }
        }
    }

    /// Secondary CTA under the camera placeholder: pick a photo the user
    /// already took on this walk/run (the capture-time-filtered importer).
    /// Only shown while the camera still leads — once it closes, the library
    /// IS the placeholder and a second button would just repeat it.
    @ViewBuilder
    private var chooseFromLibraryButton: some View {
        if cameraAllowed {
            Button { showLibraryImport = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Choose a photo from this walk or run")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    Capsule().fill(Color.white.opacity(0.1))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
        }
    }

    /// Accepted capture-time window for the library importer, from the linked
    /// workout's own start/end (HealthKit) with grace on both ends. Mirrors the
    /// post-run prompt: when the workout hasn't synced into `todaysWorkouts` yet
    /// we bound to a generous recent window rather than the whole day, so an
    /// unrelated earlier photo still can't slip in.
    ///
    /// A mile walked in several goes accepts a photo from ANY of its legs
    /// (`RunPostService.photoWindows`) — the post is all of them.
    private var importWindows: [ClosedRange<Date>] {
        let now = Date()
        guard let wid = vm.stats.workoutId,
              let windows = RunPostService.photoWindows(forWorkoutId: wid) else {
            return [now.addingTimeInterval(-3 * 60 * 60)...now.addingTimeInterval(2 * 60)]
        }
        return windows
    }

}

/// Pick the friends who were on this walk (Instagram collab style, plural).
///
/// Multi-select with a Done button rather than pick-one-and-dismiss: a walk
/// with three people on it is the ordinary case, and the single-slot picker
/// meant the other two either went uncredited or opened their own posts for
/// the same walk. Selection order is kept — the server mirrors the FIRST pick
/// into the legacy scalar coauthor column, which is the name a shipped client
/// that knows nothing about multi-person collabs will show.
struct CoauthorPickerSheet: View {
    let friends: [BackendUser]
    /// Already-picked, so re-opening the sheet shows the current crew rather
    /// than starting from nothing.
    let initialSelection: [BackendUser]
    let maxSelection: Int
    let onDone: ([BackendUser]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var picked: [BackendUser] = []
    @State private var seeded = false

    private var filtered: [BackendUser] {
        guard !search.isEmpty else { return friends }
        let q = search.lowercased()
        return friends.filter {
            ($0.username?.lowercased().contains(q) ?? false)
                || ($0.first_name?.lowercased().contains(q) ?? false)
        }
    }

    private var isFull: Bool { picked.count >= maxSelection }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()
                if friends.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.2")
                            .font(.system(size: 34))
                            .foregroundColor(.white.opacity(0.3))
                        Text("Add friends to co-post")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filtered, id: \.user_id) { friend in
                                friendRow(friend)
                            }
                        }
                        .padding(.vertical, MADTheme.Spacing.sm)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle(picked.isEmpty ? "Co-post with" : "Co-posting with \(picked.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .searchable(text: $search, prompt: "Search friends")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(picked)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .foregroundColor(MADTheme.Colors.madRed)
                }
            }
        }
        .presentationDetents([.medium, .large])
        // Seeded once, in onAppear rather than init: a `@State` initial value
        // is captured the first time the view is built and would go stale if
        // the sheet is re-presented after the crew changed.
        .onAppear {
            guard !seeded else { return }
            picked = initialSelection
            seeded = true
        }
    }

    private func friendRow(_ friend: BackendUser) -> some View {
        let position = picked.firstIndex { $0.user_id == friend.user_id }
        // A full crew greys out the people who aren't in it rather than
        // dropping them from the list — vanishing rows read as a broken search.
        let disabled = position == nil && isFull
        return Button {
            MADHaptics.tap()
            toggle(friend)
        } label: {
            HStack(spacing: 12) {
                AvatarView(name: friend.username ?? "?",
                           imageURL: friend.profile_image_url, size: 42)
                VStack(alignment: .leading, spacing: 1) {
                    Text(friend.username ?? friend.first_name ?? "Friend")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    if let first = friend.first_name, !first.isEmpty {
                        Text(first)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                Spacer()
                ZStack {
                    Circle()
                        .strokeBorder(
                            position != nil ? Color.clear : Color.white.opacity(0.25),
                            lineWidth: 1.5
                        )
                        .background(
                            Circle().fill(position != nil
                                          ? MADTheme.Colors.madRed : Color.clear)
                        )
                        .frame(width: 24, height: 24)
                    if let position {
                        Text("\(position + 1)")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .opacity(disabled ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func toggle(_ friend: BackendUser) {
        if let index = picked.firstIndex(where: { $0.user_id == friend.user_id }) {
            picked.remove(at: index)
        } else if picked.count < maxSelection {
            picked.append(friend)
        }
    }
}
