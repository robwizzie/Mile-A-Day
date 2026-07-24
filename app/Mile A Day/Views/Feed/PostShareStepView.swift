import SwiftUI

/// Step 2 of the composer — Instagram's share screen.
///
/// The whole reason this screen exists: the caption used to be the fifth section of
/// one long scroll, below the entire sticker editor, so on a phone it sat under the
/// fold and people genuinely could not find it. Here it is the first thing on
/// screen, sitting beside a thumbnail of what they just composed, with the
/// destination picker — the control that actually gates Share — immediately below
/// it rather than several scrolls down.
struct PostShareStepView: View {
    @ObservedObject var vm: PostComposerViewModel
    @ObservedObject var friendService: FriendService
    /// Terms accepted AND `vm.canPublish`. Resolved by the composer, which owns the
    /// terms state machine.
    let shareEnabled: Bool
    /// Owned by `PostComposerView` — it holds the terms switch, `publish()`,
    /// `onFinished` and `dismiss()`.
    ///
    /// NEVER call `dismiss()` from this view. Inside a `navigationDestination`,
    /// `@Environment(\.dismiss)` POPS the push instead of dismissing the composer,
    /// so a publish that dismissed from here would drop the user back on the edit
    /// step with a post already live. Everything terminal stays in the parent.
    let onShare: () -> Void
    /// Pops back to the edit step (also wired to the thumbnail).
    let onEditMedia: () -> Void

    @FocusState private var captionFocused: Bool
    @State private var showCoauthorPicker = false

    /// Instagram auto-focuses its caption field. We deliberately don't: `destination`
    /// starts nil on purpose and gates Share, so raising the keyboard on entry would
    /// hide the destination picker — recreating, one screen down, the exact
    /// below-the-fold problem this redesign fixes. The field is already first on
    /// screen, which is the discoverability fix that actually mattered. Flip this
    /// only if the destination ever gains a sensible default.
    private let autoFocusCaption = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
                    captionRow
                    if !captionMentionCandidates.isEmpty { mentionRail }

                    Divider().overlay(Color.white.opacity(0.08))

                    destinationSection
                    // Collabs are a feed concept — only offered once the chosen
                    // destination actually includes the feed.
                    if vm.destination?.toFeed == true { coauthorRow }
                    if vm.hasRoute { routeToggle }

                    if let error = vm.errorMessage {
                        Text(error)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(MADTheme.Colors.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(MADTheme.Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Share")
        .navigationBarTitleDisplayMode(.inline)
        // Toolbar background does not reliably inherit across a push — re-declare it
        // or this screen gets a translucent bar while the edit step has a solid one.
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if vm.isPublishing {
                    ProgressView().tint(.white)
                } else {
                    Button("Share", action: onShare)
                        .fontWeight(.bold)
                        .foregroundColor(shareEnabled
                            ? MADTheme.Colors.madRed : .white.opacity(0.3))
                        .disabled(!vm.canPublish)
                }
            }
        }
        .onAppear {
            if autoFocusCaption { captionFocused = true }
        }
    }

    // MARK: - Caption (the fix)

    private var captionRow: some View {
        HStack(alignment: .top, spacing: MADTheme.Spacing.md) {
            thumbnail
            VStack(alignment: .leading, spacing: 6) {
                TextField(
                    "",
                    text: $vm.caption,
                    prompt: Text("Write a caption… (@ to tag a friend)")
                        .foregroundColor(.white.opacity(0.4)),
                    axis: .vertical
                )
                .lineLimit(3...7)
                .focused($captionFocused)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                // No filled box: flat beside the thumbnail, the way Instagram's
                // share screen reads.
                .textInputAutocapitalization(.sentences)

                HStack {
                    // Anchored to the field it dismisses (a keyboard-toolbar Done
                    // floated as a detached pill over the counter on iOS 26) —
                    // Return adds newlines in this multi-line field, so this is
                    // THE way to put the keyboard away.
                    if captionFocused {
                        Button {
                            captionFocused = false
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "keyboard.chevron.compact.down")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Done")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(MADTheme.Colors.redGradient))
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                    Spacer()
                    Text("\(vm.caption.count)/280")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(vm.caption.count > 280
                            ? MADTheme.Colors.error : .white.opacity(0.4))
                }
                .animation(.easeInOut(duration: 0.15), value: captionFocused)
            }
        }
        .onChange(of: vm.caption) { _, newValue in
            if newValue.count > 280 { vm.caption = String(newValue.prefix(280)) }
        }
    }

    /// Shows the FLATTENED composite, so the thumbnail is literally what gets
    /// uploaded — sticker baked in, cropped to 4:5 exactly as the feed will show it.
    private var thumbnail: some View {
        Button {
            MADHaptics.tap()
            onEditMedia()
        } label: {
            Group {
                if let image = vm.previewComposite ?? vm.pickedImage {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color.white.opacity(0.06)
                }
            }
            .frame(width: 68, height: 85)          // 4:5, matching the canvas
            .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small,
                                        style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small,
                                 style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "pencil")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Circle().fill(.black.opacity(0.65)))
                    .padding(3)
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel("Edit photo")
    }

    // MARK: - @mentions

    /// Friends matching an @token being typed at the end of the caption.
    /// Explicit types — inference across filter/prefix chains slows the
    /// type checker to a crawl.
    private var captionMentionCandidates: [BackendUser] {
        guard let token = vm.caption.split(separator: " ").last,
              token.hasPrefix("@") else { return [] }
        let query: String = String(token.dropFirst()).lowercased()
        let matches: [BackendUser] = friendService.friends.filter { friend in
            guard let name = friend.username?.lowercased() else { return false }
            return query.isEmpty || name.hasPrefix(query)
        }
        return Array(matches.prefix(8))
    }

    private func completeCaptionMention(_ friend: BackendUser) {
        var parts = vm.caption.split(separator: " ", omittingEmptySubsequences: false)
        if let last = parts.last, last.hasPrefix("@") { parts.removeLast() }
        vm.caption = (parts + ["@\(friend.username ?? "") "]).joined(separator: " ")
    }

    private var mentionRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(captionMentionCandidates, id: \.user_id) { friend in
                    Button {
                        completeCaptionMention(friend)
                    } label: {
                        HStack(spacing: 6) {
                            AvatarView(name: friend.username ?? "?",
                                       imageURL: friend.profile_image_url, size: 22)
                            Text("@\(friend.username ?? "")")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Destination

    /// Story / Feed / Both — a single deliberate destination choice, so the
    /// story stays the ephemeral moment and the feed stays the curated record.
    /// Nothing is preselected: Share stays disabled until the user picks. That was
    /// always the intent; the problem was that this section used to sit below the
    /// fold, so the reason Share was greyed out was invisible. Here it's the second
    /// thing on the screen.
    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            sectionLabel("SHARE TO")
            HStack(spacing: MADTheme.Spacing.sm) {
                ForEach(PostDestination.allCases) { dest in
                    destinationCard(dest, selected: vm.destination == dest)
                }
            }
            if let dest = vm.destination {
                Text(dest.footnote)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("Pick where this goes — Share unlocks once you choose.",
                      systemImage: "hand.tap.fill")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(MADTheme.Colors.madRed.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(Color.white.opacity(0.04))
        )
        // Until a destination is chosen this section is the one thing left to
        // do — a soft accent border pulls the eye to it.
        .overlay(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .strokeBorder(
                    MADTheme.Colors.madRed.opacity(vm.destination == nil ? 0.45 : 0),
                    lineWidth: 1.5
                )
        )
        .animation(.easeInOut(duration: 0.2), value: vm.destination)
    }

    private func destinationCard(_ dest: PostDestination, selected: Bool) -> some View {
        Button {
            MADHaptics.tap()
            withAnimation(.easeInOut(duration: 0.15)) { vm.destination = dest }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: dest.icon)
                    .font(.system(size: 16, weight: .bold))
                Text(dest.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundColor(selected ? .white : .white.opacity(0.55))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                    .fill(selected
                        ? AnyShapeStyle(MADTheme.Colors.redGradient)
                        : AnyShapeStyle(Color.white.opacity(0.06)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                    .strokeBorder(Color.white.opacity(selected ? 0 : 0.1), lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white, .black.opacity(0.35))
                        .padding(5)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Co-poster

    /// "Ran it together?" — pick ONE friend to co-post with. They're invited
    /// on share and the post goes dual-author once they accept.
    private var coauthorRow: some View {
        Button { showCoauthorPicker = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(MADTheme.Colors.madRed)
                if let coauthor = vm.coauthor {
                    AvatarView(name: coauthor.username ?? "?",
                               imageURL: coauthor.profile_image_url, size: 26)
                    Text("Co-posting with @\(coauthor.username ?? "")")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Button {
                        vm.coauthor = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.4))
                    }
                } else {
                    Text("Ran it together? Add a co-poster")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(Color.white.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showCoauthorPicker) {
            CoauthorPickerSheet(friends: friendService.friends) { picked in
                vm.coauthor = picked
            }
        }
    }

    // MARK: - Route

    /// Offer to ride the run's GPS route along with the photo (shown as a
    /// second, swipeable slide on the feed card). Only offered when the linked
    /// workout actually has route data.
    private var routeToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $vm.includeRoute.animation(.easeInOut)) {
                Label("Include route map", systemImage: "map.fill")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            .tint(MADTheme.Colors.madRed)
            Text("Friends can swipe to see your mile's path next to the photo.")
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

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .tracking(1.2)
            .foregroundColor(.white.opacity(0.4))
    }
}
