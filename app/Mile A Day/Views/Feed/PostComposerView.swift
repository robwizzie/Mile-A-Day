import SwiftUI

/// Run stats handed to the composer to seed the overlay sticker.
struct RunStatsInput {
    var distance: Double
    var paceSecondsPerMile: Double?
    var durationSeconds: Double?
    var streak: Int?
    var workoutId: String?
    var dateText: String?

    var snapshot: PostStats {
        PostStats(
            distance: distance,
            pace: paceSecondsPerMile,
            duration: durationSeconds,
            streak: streak,
            date: dateText
        )
    }
}

@MainActor
final class PostComposerViewModel: ObservableObject {
    @Published var pickedImage: UIImage?
    @Published var caption: String = ""
    @Published var shareToStory: Bool = true
    @Published var shareToFeed: Bool = true
    @Published var stickerEnabled: Bool = true
    /// Sticker center in normalized canvas coordinates (0…1).
    @Published var stickerPos: CGPoint = CGPoint(x: 0.5, y: 0.82)
    @Published var isPublishing = false
    @Published var errorMessage: String?

    let stats: RunStatsInput
    /// Captured on-screen canvas size (points), reused to render the composite.
    var canvasSize: CGSize = .zero

    init(stats: RunStatsInput) {
        self.stats = stats
    }

    var canPublish: Bool {
        pickedImage != nil && (shareToStory || shareToFeed) && !isPublishing
    }

    /// Render the on-screen canvas (photo + sticker) to a flat JPEG-ready image
    /// at ~1080px wide, baking the overlay in. Returns nil if no photo.
    func flatten() -> UIImage? {
        guard let image = pickedImage, canvasSize.width > 0 else { return nil }
        let canvas = PostCanvas(
            image: image,
            showSticker: stickerEnabled,
            stickerPos: stickerPos,
            stats: stats
        )
        .frame(width: canvasSize.width, height: canvasSize.height)

        let renderer = ImageRenderer(content: canvas)
        // Scale the point-sized canvas up to ~1080px wide for crisp output.
        renderer.scale = max(1, 1080 / canvasSize.width)
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// Flatten → upload → create. Returns true on success. Maps the server's
    /// gating errors to friendly messages.
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
                shareToFeed: shareToFeed,
                shareToStory: shareToStory,
                stats: stats.snapshot
            )
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
    let stats: RunStatsInput

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                if showSticker {
                    RunStatsStickerView(
                        distance: stats.distance,
                        paceSecondsPerMile: stats.paceSecondsPerMile,
                        durationSeconds: stats.durationSeconds,
                        streak: stats.streak,
                        dateText: stats.dateText
                    )
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
    @State private var showImagePicker = false
    /// Called with true once a post is published so the parent can refresh.
    let onFinished: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    init(stats: RunStatsInput, onFinished: @escaping (Bool) -> Void) {
        _vm = StateObject(wrappedValue: PostComposerViewModel(stats: stats))
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
                            stickerToggle
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
                    Button("Cancel") { onFinished(false); dismiss() }
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isPublishing {
                        ProgressView().tint(.white)
                    } else {
                        Button("Share") {
                            Task {
                                let ok = await vm.publish()
                                if ok { onFinished(true); dismiss() }
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
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(selectedImage: $vm.pickedImage)
            }
        }
    }

    // MARK: - Sections

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
                            stats: vm.stats
                        )
                        // Invisible drag layer to move the sticker.
                        if vm.stickerEnabled {
                            stickerDragLayer(canvas: CGSize(width: width, height: height))
                        }
                    }
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous))
                    .onAppear { vm.canvasSize = CGSize(width: width, height: height) }
                    .overlay(alignment: .topTrailing) {
                        Button { showImagePicker = true } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Circle().fill(.black.opacity(0.45)))
                        }
                        .padding(10)
                    }
                } else {
                    photoPlaceholder
                        .frame(width: width, height: height)
                }
            }
        }
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
    }

    private var photoPlaceholder: some View {
        Button { showImagePicker = true } label: {
            VStack(spacing: MADTheme.Spacing.md) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(MADTheme.Colors.redGradient)
                Text("Choose a photo")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Share today's walk or run")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
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
    }

    private func stickerDragLayer(canvas: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let x = min(max(value.location.x / canvas.width, 0.12), 0.88)
                        let y = min(max(value.location.y / canvas.height, 0.1), 0.9)
                        vm.stickerPos = CGPoint(x: x, y: y)
                    }
            )
            .allowsHitTesting(true)
    }

    private var stickerToggle: some View {
        Toggle(isOn: $vm.stickerEnabled) {
            Label("Show run stats", systemImage: "chart.bar.doc.horizontal")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
        .tint(MADTheme.Colors.madRed)
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

    private var destinationToggles: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            Toggle(isOn: $vm.shareToStory) {
                Label("Share to Story", systemImage: "circle.dashed")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            .tint(MADTheme.Colors.madRed)

            Toggle(isOn: $vm.shareToFeed) {
                Label("Share to Feed", systemImage: "square.stack")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            .tint(MADTheme.Colors.madRed)

            if !vm.shareToStory && !vm.shareToFeed {
                Text("Pick at least one place to share.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(MADTheme.Colors.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(Color.white.opacity(0.04))
        )
    }
}
