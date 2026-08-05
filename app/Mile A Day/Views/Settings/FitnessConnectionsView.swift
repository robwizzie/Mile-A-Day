import Foundation
import SwiftUI

/// Duplicate-workout summary from `GET /workouts/:userId/duplicates`.
struct DuplicateSummary: Decodable {
    let pendingCount: Int
    let pendingMiles: Double
    let affectedDays: Int
    let excludedCount: Int
    let apps: [String]

    static let empty = DuplicateSummary(
        pendingCount: 0, pendingMiles: 0, affectedDays: 0, excludedCount: 0, apps: [])
}

enum DuplicateWorkoutService {
    static func fetchSummary(userId: String) async throws -> DuplicateSummary {
        try await APIClient.fancyFetch(
            endpoint: "/workouts/\(userId)/duplicates",
            responseType: DuplicateSummary.self
        )
    }

    struct ResolveResponse: Decodable {
        let resolvedDays: Int
        let removedMiles: Double
        let streak: Int

        enum CodingKeys: String, CodingKey {
            case resolvedDays = "resolved_days"
            case removedMiles = "removed_miles"
            case streak
        }
    }

    static func resolve(userId: String) async throws -> ResolveResponse {
        try await APIClient.fancyFetch(
            endpoint: "/workouts/\(userId)/duplicates/resolve",
            method: .POST,
            responseType: ResolveResponse.self
        )
    }
}

/// "Connected Apps & Devices" — the one place a user goes to get data from
/// Strava, Garmin, WHOOP, Oura, Peloton and the rest into Mile A Day.
///
/// The framing matters and is deliberate: this screen does not *connect*
/// anything, because there is nothing for us to connect. Every one of these
/// platforms writes into Apple Health, and the app already reads every workout
/// in Apple Health regardless of which app wrote it. So the screen's real job
/// is to (1) show the user what is already flowing, which is usually more than
/// they think, and (2) hand them the exact three taps needed in the partner app
/// for anything that isn't.
struct FitnessConnectionsView: View {
    @ObservedObject var userManager: UserManager

    @State private var sourceService = FitnessSourceService()
    @State private var selectedPlatform: FitnessSourcePlatform?
    @State private var duplicates: DuplicateSummary = .empty
    @State private var isResolvingDuplicates = false
    @State private var resolveMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: MADTheme.Spacing.lg) {
                explainerCard

                if case .failed = sourceService.state {
                    healthUnavailableCard
                }

                if !sourceService.thirdPartySources.isEmpty
                    || !sourceService.appleSources.isEmpty
                {
                    connectedSection
                }

                if duplicates.pendingCount > 0 {
                    duplicatesCard
                }

                if !sourceService.availablePlatforms.isEmpty {
                    availableSection
                }

                appleHealthFooter
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, MADTheme.Spacing.md)
        }
        .background(MADTheme.Colors.appBackgroundGradient)
        .navigationTitle("Connected Apps")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await sourceService.refresh()
            await loadDuplicates()
        }
        .refreshable {
            await sourceService.refresh()
            await loadDuplicates()
        }
        .sheet(item: $selectedPlatform) { platform in
            FitnessSourceSetupSheet(platform: platform)
        }
    }

    // MARK: - Sections

    private var explainerCard: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(MADTheme.Colors.redGradient)
                Text("Everything flows through Apple Health")
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(.primary)
            }

            Text(
                "Mile A Day counts every run and walk in Apple Health, no matter which "
                    + "app recorded it. Turn on an app's Apple Health setting once and its "
                    + "workouts start counting toward your streak automatically."
            )
            .font(MADTheme.Typography.footnote)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    private var healthUnavailableCard: some View {
        // A failed HealthKit read is NOT "nothing is connected" — most often the
        // device is simply locked. Say that instead of implying a broken setup.
        VStack(alignment: .leading, spacing: MADTheme.Spacing.xs) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(MADTheme.Colors.warning)
                Text("Couldn't read Apple Health")
                    .font(MADTheme.Typography.smallBold)
                    .foregroundColor(.primary)
            }
            Text(
                "This usually means your phone was locked. Unlock it and pull down to "
                    + "refresh — your connected apps are still syncing."
            )
            .font(MADTheme.Typography.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    private var connectedSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            sectionHeader("Sending data now", systemImage: "checkmark.seal.fill")

            VStack(spacing: 0) {
                ForEach(sourceService.thirdPartySources) { source in
                    connectedRow(source)
                    if source.id != sourceService.thirdPartySources.last?.id
                        || !sourceService.appleSources.isEmpty
                    {
                        Divider().padding(.leading, 52)
                    }
                }
                ForEach(sourceService.appleSources) { source in
                    connectedRow(source)
                    if source.id != sourceService.appleSources.last?.id {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass()
        }
    }

    private func connectedRow(_ source: DetectedFitnessSource) -> some View {
        HStack(spacing: MADTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(source.tint.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: source.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(source.tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                    .font(MADTheme.Typography.smallBold)
                    .foregroundColor(.primary)
                Text(subtitle(for: source))
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: MADTheme.Spacing.sm)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(MADTheme.Colors.success)
        }
        .padding(.vertical, MADTheme.Spacing.sm)
    }

    private func subtitle(for source: DetectedFitnessSource) -> String {
        let workouts = source.workoutCount == 1 ? "1 workout" : "\(source.workoutCount) workouts"
        let miles = String(format: "%.1f mi", source.totalMiles)
        return "\(workouts) · \(miles) · last \(Self.relative(source.lastWorkoutDate))"
    }

    private static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var availableSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            sectionHeader("Add another app", systemImage: "plus.circle.fill")

            VStack(spacing: 0) {
                ForEach(sourceService.availablePlatforms) { platform in
                    Button { selectedPlatform = platform } label: {
                        availableRow(platform)
                    }
                    .buttonStyle(.plain)

                    if platform.id != sourceService.availablePlatforms.last?.id {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass()
        }
    }

    private func availableRow(_ platform: FitnessSourcePlatform) -> some View {
        HStack(spacing: MADTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(platform.tint.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: platform.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(platform.tint)
            }

            Text(platform.name)
                .font(MADTheme.Typography.smallBold)
                .foregroundColor(.primary)

            Spacer(minLength: MADTheme.Spacing.sm)

            Text("Set up")
                .font(MADTheme.Typography.caption)
                .foregroundColor(.secondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, MADTheme.Spacing.sm)
        .contentShape(Rectangle())
    }

    /// Only appears when the server has actually found duplicates in this
    /// user's history. Nothing is changed until they tap the button — their
    /// existing miles and streak are never rewritten behind their back.
    private var duplicatesCard: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(MADTheme.Colors.warning)
                Text("Duplicate workouts found")
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(.primary)
            }

            Text(duplicateExplainer)
                .font(MADTheme.Typography.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let resolveMessage {
                Text(resolveMessage)
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(MADTheme.Colors.success)
            }

            Button {
                Task { await resolveDuplicates() }
            } label: {
                HStack(spacing: MADTheme.Spacing.sm) {
                    if isResolvingDuplicates {
                        ProgressView().tint(.white)
                    }
                    Text(isResolvingDuplicates ? "Cleaning up…" : "Stop counting duplicates")
                        .font(MADTheme.Typography.smallBold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, MADTheme.Spacing.sm)
                .background(MADTheme.Colors.redGradient)
                .foregroundColor(.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isResolvingDuplicates)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    private var duplicateExplainer: String {
        let count = duplicates.pendingCount
        let workouts = count == 1 ? "1 workout" : "\(count) workouts"
        let miles = String(format: "%.2f", duplicates.pendingMiles)
        return
            "\(workouts) in your history look like the same run recorded by two apps, "
            + "adding about \(miles) extra miles to your totals. Going forward these are "
            + "already filtered out. Cleaning up your history is optional and will lower "
            + "your past mileage."
    }

    private var appleHealthFooter: some View {
        Button {
            FitnessSourceLauncher.openAppleHealth()
        } label: {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "heart.fill")
                    .foregroundColor(MADTheme.Colors.madRed)
                Text("Open Apple Health")
                    .font(MADTheme.Typography.smallBold)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass()
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MADTheme.Colors.redGradient)
            Text(title)
                .font(MADTheme.Typography.smallBold)
                .foregroundColor(.primary)
        }
        .padding(.leading, MADTheme.Spacing.xs)
    }

    // MARK: - Data

    /// Self-scoped id, from the same two places the rest of the app reads it
    /// (`currentUser.backendUserId`, else the standalone UserDefaults key). Both
    /// are checked because a self-scoped URL built from a drifted id gets a 403,
    /// not a 401, and nothing recovers from that — see TokenUtils/SessionIdentity.
    private var resolvedUserId: String? {
        if let id = userManager.currentUser.backendUserId, !id.isEmpty { return id }
        let stored = UserDefaults.standard.string(forKey: "backendUserId")
        return (stored?.isEmpty == false) ? stored : nil
    }

    // @MainActor because these mutate @State. A plain `async` method on a View
    // is nonisolated and would hop off the main actor to do it.
    @MainActor
    private func loadDuplicates() async {
        guard let userId = resolvedUserId else { return }
        do {
            duplicates = try await DuplicateWorkoutService.fetchSummary(userId: userId)
        } catch {
            // Non-fatal: the card simply doesn't appear. Never block the screen
            // on it — the connection guidance is the point.
            print("[Connections] duplicate summary failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func resolveDuplicates() async {
        guard let userId = resolvedUserId else { return }
        isResolvingDuplicates = true
        defer { isResolvingDuplicates = false }
        do {
            let result = try await DuplicateWorkoutService.resolve(userId: userId)
            resolveMessage = String(
                format: "Removed %.2f duplicate miles across %d days.",
                result.removedMiles, result.resolvedDays)
            duplicates = try await DuplicateWorkoutService.fetchSummary(userId: userId)
        } catch {
            resolveMessage = "Couldn't clean up right now. Try again later."
        }
    }
}

/// Per-app setup instructions. Text and a button — the connection itself
/// happens inside the partner app, which is the whole point.
struct FitnessSourceSetupSheet: View {
    let platform: FitnessSourcePlatform
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
                    header

                    VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                        ForEach(Array(platform.setupSteps.enumerated()), id: \.offset) {
                            index, step in
                            HStack(alignment: .top, spacing: MADTheme.Spacing.md) {
                                ZStack {
                                    Circle()
                                        .fill(platform.tint.opacity(0.15))
                                        .frame(width: 26, height: 26)
                                    Text("\(index + 1)")
                                        .font(MADTheme.Typography.caption)
                                        .foregroundColor(platform.tint)
                                }
                                Text(step)
                                    .font(MADTheme.Typography.subheadline)
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(MADTheme.Spacing.md)
                    .madLiquidGlass()

                    if let caveat = platform.caveat {
                        HStack(alignment: .top, spacing: MADTheme.Spacing.sm) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(MADTheme.Colors.warning)
                            Text(caveat)
                                .font(MADTheme.Typography.footnote)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(MADTheme.Spacing.md)
                        .madLiquidGlass()
                    }

                    Button {
                        FitnessSourceLauncher.open(platform)
                    } label: {
                        Text("Open \(platform.name)")
                            .font(MADTheme.Typography.bodyBold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, MADTheme.Spacing.md)
                            .background(MADTheme.Colors.redGradient)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Text(
                        "Once it's on, your workouts appear here automatically — usually "
                            + "within a few minutes of finishing."
                    )
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                }
                .padding(MADTheme.Spacing.md)
            }
            .background(MADTheme.Colors.appBackgroundGradient)
            .navigationTitle(platform.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(platform.tint.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: platform.symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(platform.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Connect \(platform.name)")
                    .font(MADTheme.Typography.title3)
                    .foregroundColor(.primary)
                Text("Three quick taps in the \(platform.name) app")
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}
