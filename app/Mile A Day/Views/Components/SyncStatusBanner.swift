//
//  SyncStatusBanner.swift
//  Mile A Day
//
//  Non-blocking banner that surfaces background workout sync progress.
//  Shown when the initial sync (or any large background sync) is in flight.
//

import SwiftUI

struct SyncStatusBanner: View {
    @ObservedObject private var syncService = WorkoutSyncService.shared
    @State private var showCompletedFlash = false

    var body: some View {
        Group {
            if let progress = syncService.currentProgress, shouldShow(progress) {
                bannerContent(for: progress)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: syncService.currentProgress)
        .onChange(of: syncService.currentProgress) { _, newValue in
            guard let p = newValue, p.isComplete else { return }
            showCompletedFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                showCompletedFlash = false
                // Clear progress so the banner disappears.
                if syncService.currentProgress?.isComplete == true {
                    syncService.currentProgress = nil
                }
            }
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

    @ViewBuilder
    private func bannerContent(for progress: SyncProgress) -> some View {
        HStack(spacing: 12) {
            iconView(for: progress.phase)

            VStack(alignment: .leading, spacing: 4) {
                Text(title(for: progress))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                if case .error(let message) = progress.phase {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else if progress.totalToUpload > 0 {
                    ProgressView(value: progress.overallProgress)
                        .tint(MADTheme.Colors.madRed)
                        .frame(height: 4)
                }
            }

            Spacer(minLength: 8)

            if progress.totalToUpload > 0 && progress.phase != .complete {
                Text("\(progress.uploadedCount)/\(progress.totalToUpload)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            if case .error = progress.phase {
                Button {
                    WorkoutSyncService.shared.startInitialSyncIfNeeded()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline)
                        .foregroundColor(MADTheme.Colors.madRed)
                }
            }
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
    private func iconView(for phase: SyncPhase) -> some View {
        switch phase {
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundColor(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
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
            return "Reading workouts from Apple Health…"
        case .uploadingToBackend:
            return "Syncing workouts"
        case .complete:
            return progress.totalToUpload > 0
                ? "Synced \(progress.totalToUpload) workouts"
                : "Sync complete"
        case .error:
            return "Sync paused — tap to retry"
        }
    }
}

#Preview {
    SyncStatusBanner()
}
