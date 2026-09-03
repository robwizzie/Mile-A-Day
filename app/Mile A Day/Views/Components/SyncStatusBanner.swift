//
//  SyncStatusBanner.swift
//  Mile A Day
//
//  Non-blocking status for the workout sync, and the one surface that explains
//  the FIRST-RUN import of a user's whole Apple Health history.
//
//  That import is a genuinely long job — a runner with a decade of walks has
//  thousands of workouts, each needing its own HealthKit reads — and the old
//  banner said almost nothing about it: no total, no idea how long, no reason
//  to keep the app open, and a raw HealthKit error string ("Authorization not
//  determined") pinned on screen next to a dead retry button. So it read as
//  "broken and stuck" during the exact minutes it was working hardest.
//
//  What it says now: what we're doing, how much of it there is, roughly how
//  long it has left, and that leaving the app open is what keeps it moving.
//

import SwiftUI
// Timer.publish(...).autoconnect() properties are Combine types; SwiftUI's
// re-export covers use sites but not stored-property type declarations.
import Combine

struct SyncStatusBanner: View {
    @ObservedObject private var syncService = WorkoutSyncService.shared
    @State private var showCompletedFlash = false
    @State private var showDetail = false
    /// Re-renders the countdown ~once a second without touching the sync.
    @State private var tick = Date()

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let progress = syncService.currentProgress, shouldShow(progress) {
                bannerContent(for: progress)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: syncService.currentProgress)
        .onReceive(clock) { now in
            // Only while something is actually running — an idle banner must
            // not keep the run loop busy.
            if let p = syncService.currentProgress, !p.isComplete, !p.isFailed {
                tick = now
            }
        }
        .onChange(of: syncService.currentProgress) { _, newValue in
            guard let p = newValue, p.isComplete else { return }
            showCompletedFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                showCompletedFlash = false
                // Clear progress so the banner disappears.
                if syncService.currentProgress?.isComplete == true {
                    syncService.currentProgress = nil
                }
            }
        }
        .sheet(isPresented: $showDetail) {
            HistoryImportDetailView()
        }
    }

    private func shouldShow(_ progress: SyncProgress) -> Bool {
        switch progress.phase {
        case .idle:
            return false
        case .complete:
            return showCompletedFlash
        case .error:
            return true
        case .fetchingFromHealthKit, .uploadingToBackend:
            return true
        }
    }

    // MARK: - Banner

    @ViewBuilder
    private func bannerContent(for progress: SyncProgress) -> some View {
        // Two independent hit targets, never a button nested inside a button:
        // the body opens the explanation, the trailing glyph retries. Nesting
        // them is how the retry became a control that looked tappable and
        // wasn't.
        HStack(spacing: 12) {
            Button {
                guard progress.isInitialImport || progress.isFailed else { return }
                MADHaptics.tap()
                showDetail = true
            } label: {
                HStack(spacing: 12) {
                    iconView(for: progress)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(title(for: progress))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if progress.totalToUpload > 0, !progress.isComplete {
                            ProgressView(value: progress.displayProgress)
                                .tint(MADTheme.Colors.madRed)
                                .frame(height: 4)
                        }

                        if let subtitle = subtitle(for: progress) {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            trailingControl(for: progress)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func trailingControl(for progress: SyncProgress) -> some View {
        if progress.isFailed {
            if progress.failure?.isRetryable != false {
                Button {
                    MADHaptics.tap()
                    // `retryFailedSync` reports whether it could start. The old
                    // retry called `startInitialSyncIfNeeded`, which silently
                    // no-ops both while a sync is running and once a watermark
                    // exists — i.e. in exactly the two states someone taps it.
                    if !syncService.retryFailedSync() { showDetail = true }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(MADTheme.Colors.madRed)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } else if progress.totalToUpload > 0 && !progress.isComplete {
            // A percentage, not "412/1284" jammed against a bar that already
            // shows the same thing — the exact counts live one tap away.
            Text("\(Int((progress.displayProgress * 100).rounded()))%")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func iconView(for progress: SyncProgress) -> some View {
        switch progress.phase {
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundColor(.green)
        case .error:
            Image(systemName: progress.failure == .healthNotAsked
                  ? "heart.text.square.fill"
                  : "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundColor(.orange)
        default:
            ProgressView()
                .controlSize(.small)
        }
    }

    private func title(for progress: SyncProgress) -> String {
        switch progress.phase {
        case .idle:
            return "Preparing sync…"
        case .fetchingFromHealthKit:
            return progress.isInitialImport
                ? "Reading your Apple Health history…"
                : "Reading workouts from Apple Health…"
        case .uploadingToBackend:
            guard progress.isInitialImport else { return "Syncing workouts" }
            return "Importing \(SyncCopy.count(progress.totalToUpload)) workouts"
        case .complete:
            if progress.isInitialImport && progress.totalToUpload > 0 {
                return "History imported — \(SyncCopy.count(progress.totalToUpload)) workouts"
            }
            return progress.totalToUpload > 0
                ? "Synced \(SyncCopy.count(progress.totalToUpload)) workouts"
                : "Sync complete"
        case .error:
            return progress.failure?.message ?? "Sync paused"
        }
    }

    private func subtitle(for progress: SyncProgress) -> String? {
        if progress.isFailed {
            // Lead with what already landed. A failure at workout 900 of 1200
            // is not a failed import, and saying so is the difference between
            // "it's broken" and "it needs a tap".
            if progress.isInitialImport, progress.uploadedCount > 0 {
                return "\(SyncCopy.count(progress.uploadedCount)) already imported · tap for details"
            }
            return "Tap for details"
        }
        guard progress.isInitialImport, !progress.isComplete else { return nil }
        _ = tick  // re-evaluate the estimate each second
        var parts: [String] = []
        if progress.totalToUpload > 0 {
            parts.append("\(SyncCopy.count(progress.preparedCount)) of \(SyncCopy.count(progress.totalToUpload))")
        }
        if let eta = progress.estimatedSecondsRemaining {
            parts.append("about \(SyncCopy.duration(eta)) left")
        }
        parts.append("keep the app open")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Shared copy helpers

/// Formatting shared by the banner and the detail sheet, so the two can never
/// describe the same import differently.
enum SyncCopy {
    static func count(_ value: Int) -> String {
        Self.number.string(from: NSNumber(value: max(0, value))) ?? "\(max(0, value))"
    }

    /// Deliberately coarse. A per-second countdown on a job this long invites
    /// the user to watch it, and it would be wrong anyway — the rate changes
    /// with how much detail each workout carries.
    static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        if s < 45 { return "a few seconds" }
        if s < 90 { return "a minute" }
        if s < 3600 {
            let minutes = Int((s / 60).rounded())
            return "\(minutes) min"
        }
        let hours = s / 3600
        return hours < 1.5 ? "an hour" : "\(Int(hours.rounded())) hours"
    }

    private static let number: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()
}

// MARK: - Detail sheet

/// The "what is happening and is it stuck" screen.
///
/// Everything here answers a question the user actually asked support: how
/// many workouts is it doing, how long will it take, do I have to sit here,
/// and what is that warning. A progress bar alone answered none of them.
struct HistoryImportDetailView: View {
    @ObservedObject private var syncService = WorkoutSyncService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var tick = Date()
    @State private var retryMessage: String?

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: MADTheme.Spacing.lg) {
                        headline
                        if let progress = syncService.currentProgress {
                            if progress.isFailed {
                                failureCard(progress)
                            } else {
                                progressCard(progress)
                            }
                            countsCard(progress)
                        }
                        explainer
                    }
                    .padding(MADTheme.Spacing.md)
                }
            }
            .navigationTitle("Importing history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(MADTheme.Colors.madRed)
                }
            }
        }
        .onReceive(clock) { tick = $0 }
    }

    // MARK: Pieces

    private var headline: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(MADTheme.Colors.redGradient)
            Text("We're reading every walk and run in Apple Health")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
            Text("Your streak, records and badges are all built from this, so we bring across your whole history — not just today.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, MADTheme.Spacing.sm)
    }

    private func progressCard(_ progress: SyncProgress) -> some View {
        _ = tick
        return VStack(spacing: MADTheme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int((progress.displayProgress * 100).rounded()))%")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                Spacer()
                if let eta = progress.estimatedSecondsRemaining {
                    Text("about \(SyncCopy.duration(eta)) left")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            ProgressView(value: progress.displayProgress)
                .tint(MADTheme.Colors.madRed)

            Text(phaseLine(progress))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    private func phaseLine(_ progress: SyncProgress) -> String {
        switch progress.phase {
        case .fetchingFromHealthKit:
            return "Asking Apple Health for your workouts. This part is quick."
        case .uploadingToBackend:
            return "Reading each workout's distance, pace and splits, then saving it to your account."
        case .complete:
            return "All done — your streak and records are up to date."
        default:
            return "Working…"
        }
    }

    private func countsCard(_ progress: SyncProgress) -> some View {
        VStack(spacing: 0) {
            row("Workouts to import", SyncCopy.count(progress.totalToUpload))
            divider
            row("Read from Health", SyncCopy.count(progress.preparedCount))
            divider
            row("Saved to your account", SyncCopy.count(progress.uploadedCount))
        }
        .padding(.vertical, 4)
        .madLiquidGlass()
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
            .padding(.horizontal, MADTheme.Spacing.md)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.vertical, 11)
    }

    private func failureCard(_ progress: SyncProgress) -> some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(progress.failure?.message ?? "Import paused")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            Text(progress.failure?.recovery ?? "Tap retry.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            if progress.failure?.isRetryable != false {
                Button {
                    MADHaptics.tap()
                    if syncService.retryFailedSync() {
                        retryMessage = nil
                    } else {
                        retryMessage = "Already running — this can take a few minutes."
                    }
                } label: {
                    Text("Try again")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(MADTheme.Colors.redGradient))
                }
                .buttonStyle(.plain)
            }

            if let retryMessage {
                Text(retryMessage)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            point(
                icon: "iphone",
                title: "Keep Mile A Day open",
                body: "iOS pauses the import when the app goes to the background. It picks up exactly where it left off next time you open it — nothing already imported is redone."
            )
            point(
                icon: "clock",
                title: "Years of history take minutes",
                body: "Every workout carries its own distance, pace and mile splits, and each one is read from Apple Health individually. Thousands of workouts is thousands of reads."
            )
            point(
                icon: "flame.fill",
                title: "Your streak grows as it goes",
                body: "The number you see climbing is real — it's your streak being rebuilt day by day. It settles on the final figure when the import finishes."
            )
            point(
                icon: "hand.raised.fill",
                title: "About Health permissions",
                body: "Apple never tells an app whether READ access was granted — a denied read and a day with no walks look identical to us. So we can't warn you accurately, and we won't pretend otherwise. If your numbers are moving, your permissions are fine."
            )
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    private func point(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: MADTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(MADTheme.Colors.madRed)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(body)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    SyncStatusBanner()
}
