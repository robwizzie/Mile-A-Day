import SwiftUI
import UIKit

/// Web links to individual posts.
///
/// The link is a WEB url, not the `mileaday://` scheme, so it survives being
/// pasted anywhere — iMessage, a group chat, a browser. mileaday.run/p/<id>
/// renders a signpost page (author name + "Open in Mile A Day") and hands off
/// to the app; the post's photo and caption never appear there, because a
/// share link travels further than the friends-only audience the post was
/// written for.
enum PostShareLink {
    static let host = "mileaday.run"

    static func url(for postId: String) -> URL {
        URL(string: "https://\(host)/p/\(postId)")!
    }

    /// The post id in either link form, or nil when the URL isn't a post link:
    /// - `mileaday://p/<postId>` (what the app itself emits)
    /// - `https://mileaday.run/p/<postId>` (what gets shared and pasted)
    static func postId(from url: URL) -> String? {
        let raw: String?
        if url.scheme == "mileaday", url.host == "p" {
            let candidate = url.lastPathComponent
            raw = candidate.isEmpty || candidate == "/" ? nil : candidate
        } else if url.scheme == "https",
                  let host = url.host?.lowercased(),
                  host == Self.host || host == "www.\(Self.host)" {
            let parts = url.path.split(separator: "/").map(String.init)
            raw = (parts.count == 2 && parts[0] == "p") ? parts[1] : nil
        } else {
            raw = nil
        }
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }
}

/// Identifiable wrapper so a URL can drive `.sheet(item:)` — a plain `URL?`
/// binding races to nil the same way an `isPresented` pair does.
struct ShareURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// The system share sheet. UIKit because SwiftUI's `ShareLink` is iOS 16+ but
/// gives no control over the presenting controller, which matters here: this
/// is presented from inside another sheet.
struct ShareLinkSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Deep-link entry point: fetches one post by id, then renders it through the
/// same `PostDetailView` the profile grid uses.
///
/// The fetch is what makes a link or a notification actually work — the post
/// may be weeks old, far past whatever page the feed has loaded, and hunting
/// for it in a paginated feed can't find it at all. The server re-authorizes
/// the viewer, so a link forwarded to someone outside the author's circle gets
/// the not-available state rather than the post.
struct PostDetailLoaderView: View {
    let postId: String
    @Environment(\.dismiss) private var dismiss

    @State private var posts: [PostItem] = []
    @State private var isLoading = true
    @State private var failed = false

    var body: some View {
        Group {
            if !posts.isEmpty {
                PostDetailView(
                    title: "Post",
                    posts: $posts,
                    initialPostId: postId,
                    onNeedMore: {},
                    // Always someone else's post as far as this entry point is
                    // concerned — names and @mentions should open profiles.
                    showsAuthorProfiles: true
                )
            } else {
                NavigationStack {
                    ZStack {
                        MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()
                        if isLoading {
                            ProgressView().tint(MADTheme.Colors.madRed)
                        } else if failed {
                            unavailable
                        }
                    }
                    .navigationTitle("Post")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    }
                    .toolbarBackground(.black, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbarColorScheme(.dark, for: .navigationBar)
                }
            }
        }
        .task(id: postId) { await load() }
    }

    private var unavailable: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: "eye.slash")
                .font(.system(size: 30))
                .foregroundColor(.white.opacity(0.25))
            Text("This post isn't available")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
            // Deleted and not-visible are deliberately one message — the server
            // 404s both so post existence can't be probed with a link.
            Text("It may have been deleted, or it's only shared with the poster's friends.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, MADTheme.Spacing.xl)
        }
    }

    private func load() async {
        guard posts.isEmpty else { return }
        isLoading = true
        failed = false
        do {
            let entry = try await PostService.fetchPost(postId: postId)
            guard let item = entry.asPostItem() else {
                isLoading = false
                failed = true
                return
            }
            posts = [item]
            isLoading = false
        } catch {
            print("[PostDetail] load failed: \(error.localizedDescription)")
            isLoading = false
            failed = true
        }
    }
}

/// Where the app parks "open this post" until something can present it.
///
/// Same reason `DeepLinkRouter` exists: a universal link or a notification tap
/// can land during a cold launch, long before any view that could show a post
/// is mounted. `MainTabView` observes this and presents the loader.
@MainActor
final class PostDeepLink: ObservableObject {
    static let shared = PostDeepLink()
    private init() {}

    /// Post to present. Cleared by the presenter on dismiss.
    @Published var pendingPostId: String?

    func open(_ postId: String) {
        pendingPostId = postId
    }

    /// For callers that are dismissing their OWN sheet first (the notification
    /// inbox). Two presentations in one transaction race and SwiftUI silently
    /// drops one, so let the first dismissal finish before asking for the post.
    func openAfterDismiss(_ postId: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.pendingPostId = postId
        }
    }

    /// Handles `mileaday://p/<id>` and `https://mileaday.run/p/<id>`.
    /// Returns true when the URL was a post link.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let postId = PostShareLink.postId(from: url) else { return false }
        open(postId)
        return true
    }
}
