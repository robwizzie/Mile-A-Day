import SwiftUI

/// Full-bleed review gallery for the run's snapped photos — used mid-run (as
/// a sheet over the tracking screen, which keeps tracking untouched) and from
/// the post-run prompt. Swipe between shots, save any to Photos, delete the
/// duds on the spot, and — from the post-run prompt — jump straight into
/// posting one.
struct SnapGalleryView: View {
    let title: String
    /// Page to start on (tapping a specific card opens THAT photo).
    var initialIndex: Int = 0
    /// Show the "Use this photo" action (post-run prompt only).
    var onUse: ((MidRunPhotoStash.Entry) -> Void)? = nil
    /// Fired after any deletion so the presenter can refresh counts/cards.
    var onStashChanged: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var savedLedger = SavedPhotoLibraryLedger.shared
    @State private var entries: [MidRunPhotoStash.Entry] = []
    @State private var selectedId: String?
    @State private var showSavedToast = false
    @State private var appeared = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.08, green: 0.06, blue: 0.10), .black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: MADTheme.Spacing.md) {
                header

                if entries.isEmpty {
                    Spacer()
                    Text("No snaps yet")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                } else {
                    TabView(selection: $selectedId) {
                        ForEach(entries) { entry in
                            Image(uiImage: entry.image)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .padding(.horizontal, MADTheme.Spacing.md)
                                .tag(Optional(entry.id))
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: entries.count > 1 ? .always : .never))
                    .indexViewStyle(.page(backgroundDisplayMode: .interactive))

                    actionBar
                        .padding(.bottom, MADTheme.Spacing.md)
                }
            }
            .opacity(appeared ? 1 : 0)
        }
        .overlay(alignment: .top) {
            if showSavedToast {
                savedToast
            }
        }
        .onAppear {
            entries = MidRunPhotoStash.entries()
            savedLedger.prune(keeping: entries.map(\.id))
            if entries.indices.contains(initialIndex) {
                selectedId = entries[initialIndex].id
            } else {
                selectedId = entries.first?.id
            }
            withAnimation(.easeOut(duration: 0.25)) { appeared = true }
        }
    }

    private var current: MidRunPhotoStash.Entry? {
        entries.first { $0.id == selectedId } ?? entries.first
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            Text(title)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundColor(.white)
            if !entries.isEmpty {
                Text("\(entries.count)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.top, MADTheme.Spacing.md)
    }

    /// Whether the photo on screen is already in the user's photo library —
    /// true for every capture (auto-saved at shutter time) and every library
    /// import, unless the capture's auto-save was blocked by a denied
    /// permission that has since been granted.
    private var isCurrentSaved: Bool {
        guard let current else { return false }
        return savedLedger.contains(current.id)
    }

    /// Save / Use / Delete for the photo on screen. Photos already in the
    /// library show a disabled "Saved" — Save only stays active to cover a
    /// capture whose auto-save was blocked by a denied-then-granted permission.
    private var actionBar: some View {
        let saved = isCurrentSaved
        return HStack(spacing: MADTheme.Spacing.sm) {
            galleryAction(
                icon: saved ? "checkmark.circle.fill" : "square.and.arrow.down",
                label: saved ? "Saved" : "Save",
                tint: saved ? .green : .white
            ) {
                guard let current, !saved else { return }
                PhotoRollSaver.save(current.image, ledgerKey: current.id) { ok in
                    guard ok else { return }
                    MADHaptics.success()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showSavedToast = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        withAnimation(.easeOut(duration: 0.25)) { showSavedToast = false }
                    }
                }
            }
            .disabled(saved)

            if let onUse {
                Button {
                    guard let current else { return }
                    MADHaptics.action()
                    dismiss()
                    onUse(current)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text("Use this photo")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(MADTheme.Colors.redGradient))
                }
                .buttonStyle(.plain)
            }

            galleryAction(icon: "trash", label: "Delete", tint: MADTheme.Colors.error) {
                deleteCurrent()
            }
        }
        .padding(.horizontal, MADTheme.Spacing.md)
    }

    private func galleryAction(
        icon: String, label: String, tint: Color = .white, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                Text(label)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundColor(tint)
            .frame(width: 82)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(Color.white.opacity(0.08))
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var savedToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.green)
            Text("Saved to Photos")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.75))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
        )
        .padding(.top, 64)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Actions

    private func deleteCurrent() {
        guard let current else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        // Land on a sensible neighbor before the deleted page vanishes.
        let removedIndex = entries.firstIndex(of: current) ?? 0
        MidRunPhotoStash.remove(current)
        withAnimation(.easeInOut(duration: 0.2)) {
            entries.removeAll { $0.id == current.id }
            if entries.isEmpty {
                selectedId = nil
            } else {
                let next = min(removedIndex, entries.count - 1)
                selectedId = entries[next].id
            }
        }
        onStashChanged()
        if entries.isEmpty {
            dismiss()
        }
    }
}
