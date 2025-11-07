//
//  SyncProgressView.swift
//  Mile A Day
//
//  Shows animated progress for initial workout sync
//  with running figure and dual progress bars
//

import SwiftUI

struct SyncProgressView: View {
    @ObservedObject var syncService = WorkoutSyncService.shared
    @State private var runnerOffset: CGFloat = 0
    @State private var animateRunner = false
    @State private var progressStream: AsyncStream<SyncProgress>?

    let onComplete: () -> Void

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()

                // Title
                Text("Syncing Your Workouts")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)

                if let progress = syncService.currentProgress {
                    // Phase description
                    Text(phaseDescription(progress.phase))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 10)

                    // Running track with animated runner
                    runningTrackView(progress: progress)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 20)

                    // Progress details
                    progressDetailsView(progress: progress)
                        .padding(.horizontal, 40)

                    // Batch progress
                    if progress.totalBatches > 0 {
                        Text("Batch \(progress.currentBatch) of \(progress.totalBatches)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 5)
                    }
                } else {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()
                }

                Spacer()

                // Info text
                Text("This may take a few moments...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 40)
            }
            .padding()
        }
        .onAppear {
            startSync()
        }
        .onChange(of: syncService.currentProgress) { newProgress in
            if let progress = newProgress, progress.isComplete {
                // Delay completion to show 100% state
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    onComplete()
                }
            }
        }
    }

    // MARK: - Subviews

    private func runningTrackView(progress: SyncProgress) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track background
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 60)

                // Progress fill
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * progress.overallProgress, height: 60)
                    .animation(.easeInOut(duration: 0.3), value: progress.overallProgress)

                // Running figure
                Image(systemName: animateRunner ? "figure.run" : "figure.walk")
                    .font(.system(size: 30))
                    .foregroundColor(.white)
                    .offset(x: max(10, geometry.size.width * progress.overallProgress - 40))
                    .animation(.easeInOut(duration: 0.3), value: progress.overallProgress)

                // Mile markers (optional decorative elements)
                HStack(spacing: 0) {
                    ForEach(0..<5) { index in
                        VStack {
                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(width: 2, height: 20)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal)
            }
        }
        .frame(height: 60)
        .onAppear {
            withAnimation(.linear(duration: 0.5).repeatForever(autoreverses: true)) {
                animateRunner.toggle()
            }
        }
    }

    private func progressDetailsView(progress: SyncProgress) -> some View {
        VStack(spacing: 20) {
            // Fetching progress
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "iphone.and.arrow.forward")
                        .foregroundColor(.blue)
                    Text("Fetching from HealthKit")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(progress.fetchedCount)/\(progress.totalToFetch)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }

                ProgressView(value: Double(progress.fetchedCount), total: Double(max(1, progress.totalToFetch)))
                    .tint(.blue)
            }

            // Uploading progress
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "icloud.and.arrow.up")
                        .foregroundColor(.purple)
                    Text("Uploading to Cloud")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(progress.uploadedCount)/\(progress.totalToUpload)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.purple)
                }

                ProgressView(value: Double(progress.uploadedCount), total: Double(max(1, progress.totalToUpload)))
                    .tint(.purple)
            }
        }
    }

    // MARK: - Helper Methods

    private func phaseDescription(_ phase: SyncPhase) -> String {
        switch phase {
        case .idle:
            return "Preparing to sync..."
        case .fetchingFromHealthKit:
            return "Fetching workouts from HealthKit"
        case .uploadingToBackend:
            return "Uploading workouts to cloud"
        case .complete:
            return "Sync complete!"
        case .error(let error):
            return "Error: \(error.localizedDescription)"
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
