import SwiftUI
import Photos
import UIKit

/// Outcome of importing a library photo into a walk/run.
enum WorkoutPhotoImportResult {
    case accepted(UIImage)
    /// A FRONT & BACK pair: either one of our own saved pairs restored from
    /// `DualPairStore`, or two photos taken seconds apart that the user chose
    /// to post together. `primary` is the one shown large.
    case acceptedPair(primary: UIImage, secondary: UIImage, primaryWasFront: Bool)
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
    /// Library photos we know are FRONT & BACK pairs (`DualPairStore`), so
    /// the grid can say so before anyone taps.
    @State private var pairIds: Set<String> = []
    /// "Taken together?" — a picked photo with another shot seconds beside
    /// it, offered as one front-and-back post.
    @State private var pairOffer: PairOffer?

    /// Where the last pick landed. The picker is a fresh view every time it
    /// is presented — the composer's "Change", the prompt's second look —
    /// and a fresh grid opens at the top of the window, so choosing the wrong
    /// photo meant scrolling all the way back down to try the next one.
    /// Process-lifetime is the right scope: the window is the same walk, and
    /// the position only matters between two opens minutes apart.
    private static var lastPickedIdentifier: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Divider().overlay(Color.white.opacity(0.12))
                content
            }
            if let offer = pairOffer, !isFetchingFull {
                PairOfferOverlay(
                    offer: offer,
                    onSwap: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            pairOffer = offer.swapped
                        }
                    },
                    onPair: { acceptPair(offer) },
                    onSingle: {
                        pairOffer = nil
                        loadSingle(offer.picked)
                    },
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.2)) { pairOffer = nil }
                    }
                )
                .transition(.opacity)
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
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.fixed(side), spacing: spacing),
                            count: columnCount
                        ),
                        spacing: spacing
                    ) {
                        ForEach(assets, id: \.localIdentifier) { asset in
                            AssetThumbnailView(
                                asset: asset, side: side,
                                isPair: pairIds.contains(asset.localIdentifier)
                            )
                            .onTapGesture { select(asset) }
                        }
                    }
                }
                // Both hooks, because which one sees the loaded grid depends
                // on whether the grid is in the hierarchy while the fetch
                // runs: appear covers a grid mounted after the load, the
                // change covers one mounted before it.
                .onAppear { returnToLastPick(proxy) }
                .onChange(of: isLoading) { _, _ in returnToLastPick(proxy) }
            }
        }
    }

    /// Scroll back to the photo picked last time, centred, once the grid has
    /// it. A photo that has since left the window (or the library) is simply
    /// not found, and the grid stays at the top as before.
    private func returnToLastPick(_ proxy: ScrollViewProxy) {
        guard !isLoading,
              let id = Self.lastPickedIdentifier,
              assets.contains(where: { $0.localIdentifier == id })
        else { return }
        // Next turn: the lazy grid needs a layout pass before it can scroll
        // to an item it has not drawn yet.
        DispatchQueue.main.async {
            proxy.scrollTo(id, anchor: .center)
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

        let pairs = Set(list.map(\.localIdentifier).filter { DualPairStore.isPair(assetId: $0) })

        await MainActor.run {
            assets = list
            pairIds = pairs
            isLoading = false
        }
    }

    // MARK: - Selection

    private func select(_ asset: PHAsset) {
        guard !isFetchingFull, !didFinish else { return }
        Self.lastPickedIdentifier = asset.localIdentifier

        // One of our own FRONT & BACK saves: hand back both frames, so it
        // posts as the swappable pair it was taken as, not a flat picture.
        if pairIds.contains(asset.localIdentifier) {
            isFetchingFull = true
            let id = asset.localIdentifier
            Task {
                // Disk read off the main thread.
                let pair = await Task.detached(priority: .userInitiated) {
                    DualPairStore.pair(forAssetId: id)
                }.value
                isFetchingFull = false
                if let pair {
                    finish(.acceptedPair(
                        primary: pair.primary, secondary: pair.secondary,
                        primaryWasFront: pair.primaryWasFront))
                } else {
                    // Frames pruned since the grid loaded — the photo itself
                    // still has both frames flattened into it.
                    loadSingle(asset)
                }
            }
            return
        }

        // Two loose photos taken seconds apart — a front-and-back from
        // before pairs were remembered, or the camera app's own — are
        // OFFERED as one post. Never paired silently: seconds apart is a
        // strong hint, not proof, and the user can see which it was.
        if let partner = companion(of: asset) {
            MADHaptics.tap()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                pairOffer = PairOffer(picked: asset, partner: partner)
            }
            return
        }

        loadSingle(asset)
    }

    /// The closest other photo in the window taken within
    /// `companionGap` of this one, that isn't itself a remembered pair.
    /// A front-and-back's second frame lands ~2s after the first.
    private func companion(of asset: PHAsset) -> PHAsset? {
        guard let date = asset.creationDate else { return nil }
        return assets
            .filter { other in
                other.localIdentifier != asset.localIdentifier
                    && !pairIds.contains(other.localIdentifier)
                    && other.creationDate.map { abs($0.timeIntervalSince(date)) <= Self.companionGap } == true
            }
            .min { lhs, rhs in
                abs(lhs.creationDate!.timeIntervalSince(date)) < abs(rhs.creationDate!.timeIntervalSince(date))
            }
    }

    private static let companionGap: TimeInterval = 6

    private func loadSingle(_ asset: PHAsset) {
        guard !isFetchingFull, !didFinish else { return }
        isFetchingFull = true
        Self.requestFullImage(asset) { image in
            isFetchingFull = false
            if let image {
                finish(.accepted(image))
            } else {
                finish(.failed)
            }
        }
    }

    private func acceptPair(_ offer: PairOffer) {
        guard !isFetchingFull, !didFinish else { return }
        isFetchingFull = true
        let group = DispatchGroup()
        var big: UIImage?
        var small: UIImage?
        group.enter()
        Self.requestFullImage(offer.picked) { big = $0; group.leave() }
        group.enter()
        Self.requestFullImage(offer.partner) { small = $0; group.leave() }
        group.notify(queue: .main) {
            isFetchingFull = false
            guard let big else {
                finish(.failed)
                return
            }
            guard let small else {
                // The partner wouldn't load — still post what they tapped.
                finish(.accepted(big))
                return
            }
            finish(.acceptedPair(primary: big, secondary: small,
                                 primaryWasFront: offer.pickedLooksFront))
        }
    }

    /// Full-size image for a library photo, delivered on the main queue.
    private static func requestFullImage(_ asset: PHAsset, completion: @escaping (UIImage?) -> Void) {
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
            DispatchQueue.main.async { completion(image) }
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
    var isPair: Bool = false

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
        .overlay(alignment: .bottomLeading) {
            if isPair { FrontBackBadge().padding(5) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isPair ? "Front and back photo" : "Photo")
        .accessibilityAddTraits(.isButton)
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

/// "⧉ FRONT & BACK" — on a photo that will post as a pair.
private struct FrontBackBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "rectangle.inset.topright.filled")
                .font(.system(size: 9, weight: .bold))
            Text("FRONT & BACK")
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .tracking(0.4)
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.black.opacity(0.6)))
        .accessibilityHidden(true)
    }
}

/// A picked photo and the one taken seconds beside it.
private struct PairOffer {
    /// Shown LARGE.
    let picked: PHAsset
    /// The inset.
    let partner: PHAsset

    var swapped: PairOffer { PairOffer(picked: partner, partner: picked) }

    /// Which lens took the large one isn't recorded on these photos, so it's
    /// inferred from the order: a front-and-back shoots the camera you
    /// framed (the back, by default) and then flips — so the LATER of the
    /// two is the selfie. It only labels the composer's "Big photo · Back |
    /// Front" chips, which the poster can change.
    var pickedLooksFront: Bool {
        guard let a = picked.creationDate, let b = partner.creationDate else { return false }
        return a > b
    }
}

/// "Taken together?" — the two photos side by side, the large one first,
/// with a swap and the two answers. Drawn inside the picker (not a sheet):
/// the picker is itself a cover, and this is one more question in it.
private struct PairOfferOverlay: View {
    let offer: PairOffer
    let onSwap: () -> Void
    let onPair: () -> Void
    let onSingle: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text("Taken together?")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text("These two were taken seconds apart. Post them as one front & back photo?")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                preview

                Button(action: onPair) {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.inset.topright.filled")
                        Text("Post as Front & Back")
                    }
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Capsule().fill(MADTheme.Colors.redGradient))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onSingle) {
                    Text("Just this photo")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .padding(.bottom, 8)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(white: 0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .ignoresSafeArea(edges: .bottom)
            )
            .transition(.move(edge: .bottom))
        }
    }

    /// The post as it'll look: the large photo with the other inset in its
    /// top-right corner, and a swap button to choose which is which.
    private var preview: some View {
        let width: CGFloat = 180
        return ZStack(alignment: .topTrailing) {
            LibraryAssetImage(asset: offer.picked, side: width * 1.25)
                .frame(width: width, height: width * 1.25)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            LibraryAssetImage(asset: offer.partner, side: width * 0.42)
                .frame(width: width * 0.34, height: width * 0.34 * 1.25)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white, lineWidth: 2)
                )
                .padding(10)
        }
        .overlay(alignment: .bottom) {
            Button(action: onSwap) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .bold))
                    Text("Swap")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.black.opacity(0.65)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(10)
            .accessibilityLabel("Swap which photo is large")
        }
        .accessibilityElement(children: .contain)
    }
}

/// A library photo drawn aspect-fill at roughly `side` points.
private struct LibraryAssetImage: View {
    let asset: PHAsset
    let side: CGFloat

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.white.opacity(0.06))
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .clipped()
        // Keyed to the asset: a swap hands this view the other photo.
        .task(id: asset.localIdentifier) { load() }
        .accessibilityHidden(true)
    }

    private func load() {
        let scale = UIScreen.main.scale
        let target = CGSize(width: side * scale, height: side * scale)
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        PHImageManager.default().requestImage(
            for: asset, targetSize: target, contentMode: .aspectFill, options: options
        ) { img, _ in
            guard let img else { return }
            DispatchQueue.main.async { self.image = img }
        }
    }
}
