import SwiftUI

/// Run stats handed to the composer to seed the overlay sticker. Carries every
/// stat we can show; `datum(for:)` formats one and returns nil when there's no
/// data, so unavailable stats simply don't appear (and aren't offered as toggles).
struct RunStatsInput {
    var distance: Double
    var paceSecondsPerMile: Double?
    var durationSeconds: Double?
    var streak: Int?
    var calories: Double?
    var steps: Int?
    var workoutId: String?
    var dateText: String?

    var snapshot: PostStats {
        PostStats(
            distance: distance,
            pace: paceSecondsPerMile,
            duration: durationSeconds,
            streak: streak,
            date: dateText,
            calories: calories,
            steps: steps
        )
    }

    /// Stats that actually have data, in a stable display order.
    func availableStats() -> [RunStatKind] {
        RunStatKind.allCases.filter { datum(for: $0) != nil }
    }

    func datum(for kind: RunStatKind) -> RunStatDatum? {
        switch kind {
        case .distance:
            return RunStatDatum(kind: .distance, value: "\(String(format: "%.2f", distance)) mi")
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
        }
    }

    private static func grouped(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
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
        case .story: return "Disappears in 24 hours — friends who've done their mile can watch."
        case .feed: return "Stays on your profile and in friends' feeds."
        case .both: return "Posts to your story and your permanent feed."
        }
    }

    var toStory: Bool { self != .feed }
    var toFeed: Bool { self != .story }
}

/// What the composer did, reported back to the presenter.
enum PostComposeOutcome {
    case cancelled
    case published(toFeed: Bool, toStory: Bool)
}

@MainActor
final class PostComposerViewModel: ObservableObject {
    @Published var pickedImage: UIImage?
    @Published var caption: String = ""
    @Published var destination: PostDestination
    @Published var stickerEnabled: Bool = true
    /// Sticker center in normalized canvas coordinates (0…1).
    @Published var stickerPos: CGPoint = CGPoint(x: 0.5, y: 0.82)
    @Published var stickerScale: CGFloat = 1.0
    @Published var config: StickerConfig
    @Published var isPublishing = false
    @Published var errorMessage: String?

    let stats: RunStatsInput
    /// Captured on-screen canvas size (points), reused to render the composite.
    var canvasSize: CGSize = .zero

    init(stats: RunStatsInput, destination: PostDestination) {
        self.stats = stats
        self.destination = destination
        var cfg = StickerConfig.load()
        // Drop any remembered stats that aren't available today, and make sure
        // at least one available stat is shown.
        let available = Set(stats.availableStats())
        cfg.enabled = cfg.enabled.filter { available.contains($0) }
        if cfg.enabled.isEmpty { cfg.enabled = Array(available.prefix(1)) }
        self.config = cfg
    }

    var canPublish: Bool {
        pickedImage != nil && !isPublishing
    }

    /// Render the on-screen canvas (photo + sticker) to a flat JPEG-ready image
    /// at ~1080px wide, baking the overlay in. Returns nil if no photo.
    func flatten() -> UIImage? {
        guard let image = pickedImage, canvasSize.width > 0 else { return nil }
        let canvas = PostCanvas(
            image: image,
            showSticker: stickerEnabled,
            stickerPos: stickerPos,
            stickerScale: stickerScale,
            input: stats,
            config: config
        )
        .frame(width: canvasSize.width, height: canvasSize.height)

        let renderer = ImageRenderer(content: canvas)
        renderer.scale = max(1, 1080 / canvasSize.width)
        renderer.isOpaque = true
        return renderer.uiImage
    }

    func publish() async -> Bool {
        guard !isPublishing else { return false }
        guard let flat = flatten() else {
            errorMessage = "Add a photo first."
            return false
        }
        isPublishing = true
        errorMessage = nil
        defer { isPublishing = false }

        do {
            let mediaUrl = try await PostService.uploadMedia(flat)
            _ = try await PostService.createPost(
                mediaUrl: mediaUrl,
                caption: caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : caption,
                workoutId: stats.workoutId,
                shareToFeed: destination.toFeed,
                shareToStory: destination.toStory,
                stats: stats.snapshot
            )
            if stickerEnabled { config.save() } // remember the user's overlay style
            return true
        } catch let APIError.apiError(message) where message == "mile_not_completed" {
            errorMessage = "Finish today's mile before you post."
            return false
        } catch let APIError.apiError(message) where message == "terms_not_accepted" {
            errorMessage = "Please accept the community terms to post."
            return false
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't share your post. Try again."
            return false
        }
    }
}

/// The photo + sticker canvas (4:5). Shared by the live editor preview and the
/// ImageRenderer flatten so what you see is exactly what's uploaded.
struct PostCanvas: View {
    let image: UIImage
    let showSticker: Bool
    let stickerPos: CGPoint
    let stickerScale: CGFloat
    let input: RunStatsInput
    let config: StickerConfig

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                if showSticker {
                    RunStatsStickerView(input: input, config: config)
                        .scaleEffect(stickerScale)
                        .position(x: stickerPos.x * geo.size.width, y: stickerPos.y * geo.size.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
}

struct PostComposerView: View {
    @StateObject private var vm: PostComposerViewModel
    @State private var showCamera = false
    @State private var gestureBaseScale: CGFloat = 1.0
    /// Launch straight into the camera on first appear (post-run prompt flow) —
    /// the user already tapped "Take a photo" once to get here.
    let autoOpenCamera: Bool
    let onFinished: (PostComposeOutcome) -> Void
    @Environment(\.dismiss) private var dismiss

    init(
        stats: RunStatsInput,
        destination: PostDestination = .feed,
        autoOpenCamera: Bool = false,
        onFinished: @escaping (PostComposeOutcome) -> Void
    ) {
        _vm = StateObject(wrappedValue: PostComposerViewModel(stats: stats, destination: destination))
        self.autoOpenCamera = autoOpenCamera
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: MADTheme.Spacing.lg) {
                        canvasSection
                        if vm.pickedImage != nil {
                            overlayEditor
                            captionField
                            destinationToggles
                        }
                        if let error = vm.errorMessage {
                            Text(error)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(MADTheme.Colors.error)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(MADTheme.Spacing.md)
                }
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onFinished(.cancelled); dismiss() }
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isPublishing {
                        ProgressView().tint(.white)
                    } else {
                        Button("Share") {
                            Task {
                                let ok = await vm.publish()
                                if ok {
                                    onFinished(.published(
                                        toFeed: vm.destination.toFeed,
                                        toStory: vm.destination.toStory
                                    ))
                                    dismiss()
                                }
                            }
                        }
                        .fontWeight(.bold)
                        .foregroundColor(vm.canPublish ? MADTheme.Colors.madRed : .white.opacity(0.3))
                        .disabled(!vm.canPublish)
                    }
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker(image: $vm.pickedImage)
                    .ignoresSafeArea()
            }
            .onAppear {
                if autoOpenCamera, vm.pickedImage == nil, CameraPicker.isAvailable {
                    showCamera = true
                }
            }
        }
    }

    // MARK: - Canvas

    private var canvasSection: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = width * 5 / 4
            Group {
                if let image = vm.pickedImage {
                    ZStack {
                        PostCanvas(
                            image: image,
                            showSticker: vm.stickerEnabled,
                            stickerPos: vm.stickerPos,
                            stickerScale: vm.stickerScale,
                            input: vm.stats,
                            config: vm.config
                        )
                        if vm.stickerEnabled {
                            stickerGestureLayer(canvas: CGSize(width: width, height: height))
                        }
                    }
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous))
                    .onAppear { vm.canvasSize = CGSize(width: width, height: height) }
                    .overlay(alignment: .topTrailing) {
                        Button { showCamera = true } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Retake")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(.black.opacity(0.5)))
                        }
                        .padding(10)
                    }
                    .overlay(alignment: .bottom) {
                        if vm.stickerEnabled {
                            Text("Drag to move · pinch to resize")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.65))
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Capsule().fill(.black.opacity(0.4)))
                                .padding(.bottom, 8)
                        }
                    }
                } else {
                    photoPlaceholder.frame(width: width, height: height)
                }
            }
        }
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
    }

    private var photoPlaceholder: some View {
        Button { if CameraPicker.isAvailable { showCamera = true } } label: {
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
                    Text(CameraPicker.isAvailable ? "Take a photo" : "Camera unavailable")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text(CameraPicker.isAvailable
                        ? "Snap today's walk or run — camera keeps it real."
                        : "A camera is required to share a post.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, MADTheme.Spacing.lg)
                }

                if CameraPicker.isAvailable {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill").font(.system(size: 13, weight: .bold))
                        Text("Open camera").font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Capsule().fill(MADTheme.Colors.redGradient))
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7]))
                            .foregroundColor(.white.opacity(0.2))
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!CameraPicker.isAvailable)
    }

    private func stickerGestureLayer(canvas: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                SimultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            let x = min(max(value.location.x / canvas.width, 0.12), 0.88)
                            let y = min(max(value.location.y / canvas.height, 0.1), 0.9)
                            vm.stickerPos = CGPoint(x: x, y: y)
                        },
                    MagnificationGesture()
                        .onChanged { value in
                            vm.stickerScale = min(max(gestureBaseScale * value, 0.6), 1.9)
                        }
                        .onEnded { _ in gestureBaseScale = vm.stickerScale }
                )
            )
    }

    // MARK: - Overlay editor

    private var overlayEditor: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Toggle(isOn: $vm.stickerEnabled.animation(.easeInOut)) {
                Label("Show run stats", systemImage: "chart.bar.doc.horizontal")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            .tint(MADTheme.Colors.madRed)

            if vm.stickerEnabled {
                editorLabel("STYLE")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: MADTheme.Spacing.sm) {
                        ForEach(StickerStyle.allCases) { style in
                            chip(
                                title: style.title, icon: style.icon,
                                selected: vm.config.style == style
                            ) { vm.config.style = style }
                        }
                    }
                }

                editorLabel("SHOW")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: MADTheme.Spacing.sm) {
                        ForEach(vm.stats.availableStats()) { kind in
                            chip(
                                title: kind.label, icon: kind.icon,
                                selected: vm.config.isOn(kind)
                            ) { vm.config.toggle(kind) }
                        }
                    }
                }

                editorLabel("COLOR")
                HStack(spacing: MADTheme.Spacing.md) {
                    ForEach(StickerAccent.allCases) { accent in
                        Button { vm.config.accent = accent } label: {
                            Circle()
                                .fill(accent.color)
                                .frame(width: 26, height: 26)
                                .overlay(
                                    Circle().strokeBorder(
                                        Color.white,
                                        lineWidth: vm.config.accent == accent ? 2.5 : 0
                                    )
                                )
                                .overlay(
                                    Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func editorLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .tracking(1.2)
            .foregroundColor(.white.opacity(0.4))
    }

    private func chip(title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold))
                Text(title).font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundColor(selected ? .white : .white.opacity(0.6))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(
                Capsule().fill(selected ? AnyShapeStyle(MADTheme.Colors.redGradient) : AnyShapeStyle(Color.white.opacity(0.07)))
            )
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(selected ? 0 : 0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var captionField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("", text: $vm.caption, prompt: Text("Add a caption…").foregroundColor(.white.opacity(0.4)), axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .padding(MADTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .fill(Color.white.opacity(0.06))
                )
            Text("\(vm.caption.count)/280")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(vm.caption.count > 280 ? MADTheme.Colors.error : .white.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .onChange(of: vm.caption) { _, newValue in
            if newValue.count > 280 { vm.caption = String(newValue.prefix(280)) }
        }
    }

    /// Story / Feed / Both — a single deliberate destination choice, so the
    /// story stays the ephemeral moment and the feed stays the curated record.
    private var destinationToggles: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            editorLabel("SHARE TO")
            HStack(spacing: MADTheme.Spacing.sm) {
                ForEach(PostDestination.allCases) { dest in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { vm.destination = dest }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: dest.icon)
                                .font(.system(size: 16, weight: .bold))
                            Text(dest.title)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(vm.destination == dest ? .white : .white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                                .fill(vm.destination == dest
                                    ? AnyShapeStyle(MADTheme.Colors.redGradient)
                                    : AnyShapeStyle(Color.white.opacity(0.06)))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                                .strokeBorder(Color.white.opacity(vm.destination == dest ? 0 : 0.1), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(vm.destination.footnote)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(Color.white.opacity(0.04))
        )
    }
}
