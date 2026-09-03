//
//  SyncProgressView.swift
//  Mile A Day
//
//  The modal shown when a catch-up sync is big enough to be worth waiting on
//  (AppLaunchSyncHandler's `silentSyncThreshold`).
//
//  It is presented with `interactiveDismissDisabled`, which made it a trap: if
//  the sync errored, nothing here reported it and nothing here dismissed, so
//  the only escape was force-quitting the app. It now always offers a way out
//  — the sync keeps running in the background either way, surfaced by
//  SyncStatusBanner — and it says how many workouts there are and roughly how
//  long they'll take, rather than "this may take a few moments".
//

import SwiftUI
// Timer.publish(...).autoconnect() properties are Combine types; SwiftUI's
// re-export covers use sites but not stored-property type declarations.
import Combine

struct SyncProgressView: View {
    @ObservedObject var syncService = WorkoutSyncService.shared
    @State private var animateRunner = false
    @State private var progressStream: AsyncStream<SyncProgress>?
    /// Ticks the estimate; also gates the escape hatch appearing.
    @State private var tick = Date()
    @State private var shownSince = Date()

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    let onComplete: () -> Void

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

            VStack(spacing: MADTheme.Spacing.lg) {
                Spacer()

                Text("Syncing your workouts")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                if let progress = syncService.currentProgress {
                    Text(phaseDescription(progress))
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, MADTheme.Spacing.lg)

                    runningTrackView(progress: progress)
                        .padding(.horizontal, MADTheme.Spacing.xl)

                    progressDetailsView(progress: progress)
                        .padding(.horizontal, MADTheme.Spacing.xl)

                    if progress.isFailed {
                        failureBlock(progress)
                            .padding(.horizontal, MADTheme.Spacing.xl)
                    }
                } else {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                        .padding()
                }

                Spacer()

                // Never a dead end. The work continues in the background and
                // the banner keeps reporting it, so there is no reason to hold
                // anyone here — and every reason not to, since the one thing
                // that made this modal appear is having a lot to sync.
                if canDismiss {
                    Button {
                        MADHaptics.tap()
                        onComplete()
                    } label: {
                        Text("Continue in the background")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.horizontal, 26)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }

                Text("Keep Mile A Day open while this runs — it pauses in the background and picks up where it left off.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, MADTheme.Spacing.xl)
                    .padding(.bottom, MADTheme.Spacing.lg)
            }
            .padding()
        }
        .animation(.easeInOut(duration: 0.25), value: canDismiss)
        .onAppear {
            shownSince = Date()
            startSync()
        }
        .onReceive(clock) { tick = $0 }
        .onChange(of: syncService.currentProgress) { _, newProgress in
            if let progress = newProgress, progress.isComplete {
                // Delay completion to show 100% state
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    onComplete()
                }
            }
        }
    }

    /// Offered as soon as there's anything to escape from — immediately on a
    /// failure, and after a few seconds otherwise so it doesn't flash past on
    /// a sync that finishes instantly.
    private var canDismiss: Bool {
        if syncService.currentProgress?.isFailed == true { return true }
        return tick.timeIntervalSince(shownSince) > 4
    }

    // MARK: - Subviews

    private func runningTrackView(progress: SyncProgress) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 54)

                RoundedRectangle(cornerRadius: 10)
                    .fill(MADTheme.Colors.redGradient)
                    .frame(
                        width: max(0, geometry.size.width * progress.displayProgress),
                        height: 54
                    )
                    .animation(.easeInOut(duration: 0.3), value: progress.displayProgress)

                Image(systemName: animateRunner ? "figure.run" : "figure.walk")
                    .font(.system(size: 26))
                    .foregroundColor(.white)
                    .offset(x: max(10, geometry.size.width * progress.displayProgress - 36))
                    .animation(.easeInOut(duration: 0.3), value: progress.displayProgress)
            }
        }
        .frame(height: 54)
        .onAppear {
            withAnimation(.linear(duration: 0.5).repeatForever(autoreverses: true)) {
                animateRunner.toggle()
            }
        }
    }

    private func progressDetailsView(progress: SyncProgress) -> some View {
        _ = tick
        return HStack {
            Text("\(SyncCopy.count(progress.preparedCount)) of \(SyncCopy.count(progress.totalToUpload))")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white.opacity(0.8))
            Spacer()
            if let eta = progress.estimatedSecondsRemaining, !progress.isComplete {
                Text("about \(SyncCopy.duration(eta)) left")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            } else {
                Text("\(Int((progress.displayProgress * 100).rounded()))%")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.55))
            }
        }
    }

    private func failureBlock(_ progress: SyncProgress) -> some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            Text(progress.failure?.recovery ?? "Tap retry.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if progress.failure?.isRetryable != false {
                Button {
                    MADHaptics.tap()
                    syncService.retryFailedSync()
                } label: {
                    Text("Try again")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(MADTheme.Colors.redGradient))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helper Methods

    private func phaseDescription(_ progress: SyncProgress) -> String {
        switch progress.phase {
        case .idle:
            return "Getting ready…"
        case .fetchingFromHealthKit:
            return "Reading your workouts from Apple Health"
        case .uploadingToBackend:
            return "Saving each workout's distance, pace and splits to your account"
        case .complete:
            return "All caught up"
        case .error:
            return progress.failure?.message ?? "Sync paused"
        }
    }

    private func startSync() {
        Task {
            let stream = syncService.performInitialSync()
            self.progressStream = stream

            for await progress in stream {
                await MainActor.run {
                    syncService.currentProgress = progress
                }
            }
        }
    }
}

// MARK: - Preview

struct SyncProgressView_Previews: PreviewProvider {
    static var previews: some View {
        SyncProgressView(onComplete: {})
    }
}
