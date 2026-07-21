import SwiftUI
import Photos
import UIKit

/// Outcome of importing a library photo into a walk/run.
enum WorkoutPhotoImportResult {
    case accepted(UIImage)
    case cancelled
    case failed
}

/// Library import that stays true to the app's "captured on this walk"
/// authenticity by only ever SHOWING photos whose library creation time falls
/// inside the workout window — the user can't pick something we'd reject, so
/// there's no "you tapped a photo we won't allow" dead-end.
///
/// This reads the photo library directly (PHAsset), which needs
/// `NSPhotoLibraryUsageDescription`, because Apple's out-of-process PHPicker
/// can't filter what it displays by capture time. `creationDate` is the
/// library's own trusted timestamp (the shutter moment for camera captures), so
/// no post-selection EXIF re-check is needed. Screenshots are excluded — they
/// have no real capture moment and the old EXIF path rejected them too.
struct WorkoutPhotoImportPicker: View {
    /// Accepted capture-time window (absolute time). Callers add grace.
    let window: ClosedRange<Date>
    /// "run" / "walk" for copy; defaults to a neutral noun.
    var activityNoun: String = "workout"
    let onResult: (WorkoutPhotoImportResult) -> Void

    @State private var status: PHAuthorizationStatus = .notDetermined
    @State private var assets: [PHAsset] = []
    @State private var isLoading = true
    @State private var isFetchingFull = false
    @State private var didFinish = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Divider().overlay(Color.white.opacity(0.12))
                content
            }
            if isFetchingFull {
                Color.black.opacity(0.45).ignoresSafeArea()
                ProgressView().tint(.white)
            }
        }
        .task { await start() }
    }

    // MARK: - Chrome

    private var header: some View {
        ZStack {
            Text("Photos from your \(activityNoun)")
                .font(.headline)
                .foregroundStyle(.white)
            HStack {
                Button("Cancel") { finish(.cancelled) }
                    .foregroundStyle(.white)
                Spacer()
                // Limited access → let the user add more of their photos so the
                // in-window ones they want aren't hidden by the allowed subset.
                if status == .limited {
                    Button("Add") { presentLimitedPicker() }
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var content: some View {
        switch status {
        case .denied, .restricted:
            infoState(
                title: "Photo access is off",
                message: "Turn on photo access in Settings to add a picture you took on your \(activityNoun).",
                actionTitle: "Open Settings",
                action: openSettings
            )
        case .notDetermined:
            loadingState
        default:
            if isLoading {
                loadingState
            } else if assets.isEmpty {
                infoState(
                    title: "No photos from this \(activityNoun)",
                    message: "We only show photos taken while you were moving. Snap one with the camera to add it.",
                    actionTitle: nil,
                    action: {}
                )
            } else {
                grid
            }
        }
    }

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView().tint(.white)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func infoState(
        title: String,
        message: String,
        actionTitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.white, in: Capsule())
                    .foregroundStyle(.black)
                    .padding(.top, 4)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var grid: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 2
            let columnCount = 3
            let side = (geo.size.width - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount)
            ScrollView {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.fixed(side), spacing: spacing),
                        count: columnCount
                    ),
                    spacing: spacing
                ) {
                    ForEach(assets, id: \.localIdentifier) { asset in
                        AssetThumbnailView(asset: asset, side: side)
                            .onTapGesture { select(asset) }
                    }
                }
            }
        }
    }

    // MARK: - Authorization + fetch

    private func start() async {
        var resolved = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if resolved == .notDetermined {
            resolved = await requestAuthorization()
        }
        await MainActor.run { status = resolved }
        if resolved == .authorized || resolved == .limited {
            await fetchAssets()
        } else {
            await MainActor.run { isLoading = false }
        }
    }

    private func requestAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                continuation.resume(returning: newStatus)
            }
        }
    }

    private func fetchAssets() async {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate <= %@",
            window.lowerBound as NSDate,
            window.upperBound as NSDate
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetched = PHAsset.fetchAssets(with: .image, options: options)

        var list: [PHAsset] = []
        fetched.enumerateObjects { asset, _, _ in
            // Screenshots have a creationDate but no real "taken on this walk"
            // moment — the old EXIF check rejected them, so keep them out.
            if !asset.mediaSubtypes.contains(.photoScreenshot) {
                list.append(asset)
            }
        }

        await MainActor.run {
            assets = list
            isLoading = false
        }
    }

    // MARK: - Selection

    private func select(_ asset: PHAsset) {
        guard !isFetchingFull, !didFinish else { return }
        isFetchingFull = true

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true // download from iCloud if needed
        options.resizeMode = .exact
        // Large enough for a full-bleed post; the composer/upload compress.
        let target = CGSize(width: 3024, height: 3024)

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: target,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            // highQualityFormat may still deliver a degraded placeholder first
            // while downloading; wait for the final, full-quality delivery.
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            if degraded { return }
            DispatchQueue.main.async {
                isFetchingFull = false
                if let image {
                    finish(.accepted(image))
                } else {
                    finish(.failed)
                }
            }
        }
    }

    private func finish(_ result: WorkoutPhotoImportResult) {
        guard !didFinish else { return }
        didFinish = true
        onResult(result)
    }

    // MARK: - System affordances

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func presentLimitedPicker() {
        guard let presenter = Self.topViewController() else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter) { _ in
            Task { await fetchAssets() }
        }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
            ?? scene?.windows.first?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// One square library thumbnail, loaded async from PhotoKit.
private struct AssetThumbnailView: View {
    let asset: PHAsset
    let side: CGFloat

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(Color.white.opacity(0.06))
            }
        }
        .frame(width: side, height: side)
        .clipped()
        .contentShape(Rectangle())
        .onAppear(perform: load)
    }

    private func load() {
        guard image == nil else { return }
        let scale = UIScreen.main.scale
        let target = CGSize(width: side * scale, height: side * scale)
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: target,
            contentMode: .aspectFill,
            options: options
        ) { img, _ in
            guard let img else { return }
            DispatchQueue.main.async { self.image = img }
        }
    }
}
