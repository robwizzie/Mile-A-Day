import SwiftUI

/// Race PRs for the Stats tab: only the distances that HAVE a record, plus
/// "See all distances" for the full catalog (empty distances included). Tap a
/// record to open its history. Self-contained — owns its own fetch + state,
/// so the parent just drops it in with a user id.
struct RacePRsSection: View {
    let userId: String?

    @State private var records: [String: RaceRecord] = [:]  // keyed by distanceKey
    @State private var isLoading = true
    @State private var selected: RaceDistance?
    @State private var showingAllDistances = false

    private var recordedDistances: [RaceDistance] {
        RaceCatalog.distances.filter { records[$0.key] != nil }
    }

    var body: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "stopwatch.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MADTheme.Colors.redGradient)
                Text("Race PRs")
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(.primary)
                Spacer()
            }

            if isLoading && records.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MADTheme.Spacing.md)
            } else if recordedDistances.isEmpty {
                Text("No race PRs yet. Finish a mile, 5K or longer in one go to set your first.")
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                RacePRGrid(distances: recordedDistances, records: records) { selected = $0 }
            }

            Button {
                MADHaptics.tap()
                showingAllDistances = true
            } label: {
                HStack(spacing: 4) {
                    Text("See all distances")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .accessibilityHidden(true)
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(MADTheme.Colors.madRed)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
        .task(id: userId) { await load() }
        .sheet(item: $selected) { dist in
            RaceHistoryView(userId: userId ?? "", distance: dist)
        }
        .sheet(isPresented: $showingAllDistances) {
            RaceAllDistancesView(userId: userId, records: records)
        }
    }

    private func load() async {
        defer { isLoading = false }
        guard let userId else { return }
        do {
            let recs = try await RaceRecordsService.fetchRecords(userId: userId)
            records = Dictionary(recs.map { ($0.distanceKey, $0) }, uniquingKeysWith: { a, _ in a })
        } catch {
            print("[RacePRs] load failed: \(error)")
        }
    }
}

/// Two-column PR cards. Distances without a record draw dimmed and inert.
private struct RacePRGrid: View {
    let distances: [RaceDistance]
    let records: [String: RaceRecord]
    let onSelect: (RaceDistance) -> Void

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: MADTheme.Spacing.md
        ) {
            ForEach(distances) { dist in
                let rec = records[dist.key]
                let hasRecord = rec != nil
                Button {
                    if hasRecord { onSelect(dist) }
                } label: {
                    MADStatCard(
                        title: dist.name,
                        value: rec.map { RaceCatalog.formatTime($0.durationSec) } ?? "—",
                        icon: "stopwatch",
                        iconColor: hasRecord ? MADTheme.Colors.madRed : .gray,
                        backgroundColor: (hasRecord ? MADTheme.Colors.madRed : Color.gray).opacity(0.1),
                        // Empty cards reserve the pace line (blank) so every
                        // card is the same height regardless of having a record.
                        subtitle: rec.map { RaceCatalog.formatPace(seconds: $0.durationSec, miles: $0.distanceMiles) } ?? " "
                    )
                    .opacity(hasRecord ? 1 : 0.55)
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(!hasRecord)
            }
        }
    }
}

/// The full catalog — every standard distance, recorded or not — which is
/// what the Stats tab used to show inline.
struct RaceAllDistancesView: View {
    let userId: String?
    let records: [String: RaceRecord]

    @Environment(\.dismiss) private var dismiss
    @State private var selected: RaceDistance?

    var body: some View {
        NavigationStack {
            ScrollView {
                RacePRGrid(distances: RaceCatalog.distances, records: records) { selected = $0 }
                    .padding(MADTheme.Spacing.md)
                    .lockedToScrollWidth()
            }
            .scrollContentBackground(.hidden)
            .background(MADTheme.Colors.appBackgroundGradient.ignoresSafeArea())
            .navigationTitle("Race PRs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selected) { dist in
                RaceHistoryView(userId: userId ?? "", distance: dist)
            }
        }
    }
}

/// Every qualifying run for one distance, newest first. The fastest run is the
/// PR (highlighted at the top); the list below is the full progression.
struct RaceHistoryView: View {
    let userId: String
    let distance: RaceDistance

    @Environment(\.dismiss) private var dismiss
    @State private var history: [RaceRecord] = []
    @State private var isLoading = true
    /// The PR handed to the Share Studio (preview, Instagram, Save…).
    @State private var recordShare: MADStoryContent?

    private var best: RaceRecord? {
        history.min(by: { $0.durationSec < $1.durationSec })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: MADTheme.Spacing.lg) {
                    if let best {
                        prHeader(best)
                        historyList
                    } else if isLoading {
                        ProgressView().padding(.top, 60)
                    } else {
                        emptyState
                    }
                }
                .padding(MADTheme.Spacing.md)
            }
            .scrollContentBackground(.hidden)
            .background(MADTheme.Colors.appBackgroundGradient)
            .navigationTitle(distance.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let best {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            MADHaptics.action()
                            TelemetryService.record(ShareTelemetry.opened)
                            recordShare = MADStoryContent(record: shareRecord(best))
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share this record")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $recordShare) { content in
                ShareStudioView(content: content, initialTemplate: .recordStory)
            }
        }
        .task { await load() }
    }

    /// The studio's model for this distance's best run.
    private func shareRecord(_ rec: RaceRecord) -> ShareRecord {
        ShareRecord(distanceName: distance.name,
                    durationSeconds: rec.durationSec,
                    distanceMiles: rec.distanceMiles,
                    date: FlameyClosetCopy.parseDay(rec.achievedDate))
    }

    private func prHeader(_ rec: RaceRecord) -> some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(MADTheme.Colors.redGradient)
            Text(RaceCatalog.formatTime(rec.durationSec))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text(RaceCatalog.formatPace(seconds: rec.durationSec, miles: rec.distanceMiles))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(MADTheme.Colors.madRed)
            Text("Personal record · \(formatDate(rec.achievedDate))")
                .font(MADTheme.Typography.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(MADTheme.Spacing.lg)
        .madLiquidGlass()
    }

    private var historyList: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            HStack {
                Text("History")
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(.primary)
                Spacer()
                Text("\(history.count) run\(history.count == 1 ? "" : "s")")
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.secondary)
            }
            ForEach(history) { rec in
                HStack {
                    Text(formatDate(rec.achievedDate))
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.primary)
                    if rec.id == best?.id {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(MADTheme.Colors.madRed)
                    }
                    Spacer()
                    Text(RaceCatalog.formatPace(seconds: rec.durationSec, miles: rec.distanceMiles))
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.secondary)
                    Text(RaceCatalog.formatTime(rec.durationSec))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(rec.id == best?.id ? MADTheme.Colors.madRed : .primary)
                        .frame(minWidth: 68, alignment: .trailing)
                }
                .padding(.vertical, MADTheme.Spacing.sm)
                .padding(.horizontal, MADTheme.Spacing.md)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))
            }
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    private var emptyState: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: "stopwatch")
                .font(.system(size: 32, weight: .medium))
                .foregroundColor(.secondary)
            Text("No \(distance.name) runs yet")
                .font(MADTheme.Typography.headline)
                .foregroundColor(.primary)
            Text("Run this distance to set your first PR.")
                .font(MADTheme.Typography.caption)
                .foregroundColor(.secondary)
        }
        .padding(.top, 60)
    }

    private func load() async {
        defer { isLoading = false }
        do {
            history = try await RaceRecordsService.fetchHistory(userId: userId, distanceKey: distance.key)
        } catch {
            print("[RaceHistory] load failed: \(error)")
        }
    }

    /// "YYYY-MM-DD" → "Mar 3, 2026". Falls back to the raw string on parse failure.
    private func formatDate(_ ymd: String) -> String {
        let inFmt = DateFormatter()
        inFmt.dateFormat = "yyyy-MM-dd"
        inFmt.timeZone = TimeZone(identifier: "UTC")
        guard let date = inFmt.date(from: ymd) else { return ymd }
        let outFmt = DateFormatter()
        outFmt.dateStyle = .medium
        outFmt.timeZone = TimeZone(identifier: "UTC")
        return outFmt.string(from: date)
    }
}
