import SwiftUI

/// Finds the real account that referred someone. Free typing never becomes a
/// referral: only a person chosen from these results can be saved.
struct ReferrerPicker: View {
    @Binding var selection: BackendUser?

    @StateObject private var friendService = FriendService()
    @State private var query = ""
    @State private var results: [BackendUser] = []
    @State private var searched = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selection {
                selected(selection)
            } else {
                searchField
                ForEach(results.prefix(5)) { user in
                    Button {
                        MADHaptics.tap()
                        focused = false
                        self.selection = user
                    } label: {
                        row(user)
                    }
                    .buttonStyle(.plain)
                }
                if searched, results.isEmpty {
                    Text("No account with that name. Check the spelling with your friend.")
                        .madFont(size: 13, weight: .medium, design: .rounded, maxScale: 1.4)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            Text("They'll see your first name and how many days you've walked until this referral counts.")
                .madFont(size: 12, weight: .medium, design: .rounded, maxScale: 1.4)
                .foregroundColor(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: query) {
            let term = query.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
            guard term.count >= 2 else {
                results = []
                searched = false
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            results = (try? await friendService.searchUsers(byUsername: term)) ?? []
            searched = true
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.5))
                .accessibilityHidden(true)
            TextField("", text: $query, prompt: Text("Search your friend's name or username").foregroundColor(.white.opacity(0.4)))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .submitLabel(.search)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private func row(_ user: BackendUser) -> some View {
        HStack(spacing: 10) {
            AvatarWithRing(name: user.displayName, imageURL: user.profile_image_url, progress: 0, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(user.displayName)
                    .madFont(size: 15, weight: .bold, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let username = user.username {
                    Text("@\(username)")
                        .madFont(size: 13, weight: .medium, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
        .contentShape(Rectangle())
    }

    private func selected(_ user: BackendUser) -> some View {
        HStack(spacing: 8) {
            row(user)
            Button("Change") {
                selection = nil
                query = ""
                results = []
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundColor(MADTheme.Colors.madRed)
        }
    }
}
