import SwiftUI

/// One finished ghost race. Signed margin: positive won, negative lost.
///
/// Plain snake_case with NO explicit `CodingKeys` — a struct with one loses
/// Codable synthesis the moment a property is added without a matching case,
/// and there is no iOS CI to catch it. `local_date` is a `date` column, so a
/// plain string is safe here (only `timestamptz` carries the fractional-seconds
/// trap that breaks `JSONDecoder.iso8601`).
struct GhostRaceRecord: Codable, Identifiable, Equatable {
    let workout_id: String
    let margin_seconds: Double
    let target_seconds: Double
    let local_date: String
    let workout_type: String?
    /// Nil unless the ghost was a friend's mile AND they're still visible.
    let friend_name: String?

    var id: String { workout_id }
    var won: Bool { margin_seconds > 0 }
    var yourSeconds: Double { max(0, target_seconds - margin_seconds) }

    var ghostLabel: String {
        if let friend_name, !friend_name.isEmpty { return friend_name }
        return "your ghost"
    }

    var resultText: String {
        let whole = max(1, Int(abs(margin_seconds).rounded()))
        return won ? "Beat \(ghostLabel) by \(whole)s" : "\(whole)s off \(ghostLabel)"
    }
}

private struct GhostHistoryResponse: Decodable {
    let races: [GhostRaceRecord]
}

/// Your ghost races, newest first — **wins and losses**.
///
/// The losses are the point. A trophy cabinet tells you nothing you didn't
/// already know; "2 seconds off" is the line that gets someone back out. This
/// is the only surface in the app that shows one — the feed, the celebration
/// and the push are all deliberately wins-only.
///
/// Self-contained like `RacePRsSection` beside it: owns its own fetch and
/// state, so the parent just drops it in.
struct GhostRacesSection: View {
    @State private var races: [GhostRaceRecord] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var showingAll = false

    /// Rows on the Stats tab before "See all".
    private static let previewCount = 3

    private var wins: Int { races.filter(\.won).count }

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            header

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MADTheme.Spacing.lg)
            } else if races.isEmpty {
                emptyState
            } else {
                VStack(spacing: MADTheme.Spacing.sm) {
                    ForEach(races.prefix(Self.previewCount)) { race in
                        GhostRaceRow(race: race)
                    }
                }
                if races.count > Self.previewCount {
                    Button {
                        MADHaptics.tap()
                        showingAll = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("See all \(races.count) races")
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
            }
        }
        // The same glass card as Performance and Race PRs on either side of
        // it — the header and rows used to sit loose on the page.
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
        .task {
            await load()
        }
        .sheet(isPresented: $showingAll) {
            GhostRacesListView(races: races)
        }
    }

    private var header: some View {
        HStack(spacing: MADTheme.Spacing.sm) {
            GhostSprite(size: 18, color: MADTheme.Colors.madWhite, floats: false)
            Text("Ghost Races")
                .font(MADTheme.Typography.headline)
                .foregroundStyle(MADTheme.Colors.madWhite)
            Spacer()
            if !races.isEmpty {
                Text("\(wins)–\(races.count - wins)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))
            }
        }
    }

    private var emptyState: some View {
        Text(
            loadFailed
                ? "Couldn't load your races."
                : "No races yet. Pick Ghost Race when you start a mile."
        )
        .font(MADTheme.Typography.caption)
        .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, MADTheme.Spacing.sm)
    }

    private func load() async {
        do {
            let response: GhostHistoryResponse = try await APIClient.fancyFetch(
                endpoint: "/ghosts/history",
                method: .GET,
                body: nil,
                responseType: GhostHistoryResponse.self
            )
            races = response.races
            loadFailed = false
        } catch {
            loadFailed = true
        }
        isLoading = false
    }
}

/// One race: result line, date, your time.
struct GhostRaceRow: View {
    let race: GhostRaceRecord

    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: race.won ? "trophy.fill" : "flag.checkered")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(race.won ? Color.green : Color.orange)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(race.resultText)
                    .font(MADTheme.Typography.smallBold)
                    .foregroundStyle(MADTheme.Colors.madWhite)
                    .lineLimit(1)
                Text(race.local_date)
                    .font(MADTheme.Typography.caption)
                    .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.5))
            }

            Spacer(minLength: MADTheme.Spacing.sm)

            Text(BestEffortStore.formatSeconds(race.yourSeconds))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(MADTheme.Colors.madWhite)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}

/// Every race, wins and losses, newest first.
struct GhostRacesListView: View {
    let races: [GhostRaceRecord]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: MADTheme.Spacing.sm) {
                    ForEach(races) { race in
                        GhostRaceRow(race: race)
                    }
                }
                .padding(MADTheme.Spacing.md)
                .lockedToScrollWidth()
            }
            .scrollContentBackground(.hidden)
            .background(MADTheme.Colors.appBackgroundGradient.ignoresSafeArea())
            .navigationTitle("Ghost Races")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
