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
    @State private var duplicates: DuplicateSummary = .empty
    @State private var isResolvingDuplicates = false
    @State private var resolveMessage: String?
    @State private var activeSheet: ConnectionSheet?
    @State private var searchText = ""

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

                importHistoryCard

                if !filteredPlatforms.isEmpty || !searchText.isEmpty {
                    availableSection
                }

                troubleshootingCard

                limitationsSection

                appleHealthFooter
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, MADTheme.Spacing.md)
        }
        .background(MADTheme.Colors.appBackgroundGradient)
        .navigationTitle("Connected Apps")
        .navigationBarTitleDisplayMode(.large)
        .task {
            // Icons first and independently: they're cosmetic, cached, and must
            // never gate the HealthKit read that actually populates the screen.
            await AppIconLoader.shared.loadIfNeeded(
                for: FitnessSourceCatalog.all.map { $0.appStoreId })
            await sourceService.refresh()
            await loadDuplicates()
        }
        .refreshable {
            await sourceService.refresh()
            await loadDuplicates()
        }
        // ONE sheet modifier, driven by an enum.
        //
        // Three stacked `.sheet`s on the same node is the trap this repo
        // already documents for fullScreenCover: they compete, and one of them
        // silently never presents — a button that "does nothing". Routing every
        // destination through a single Identifiable item removes the race
        // entirely, and makes handing off between destinations explicit.
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .setup(let platform):
                FitnessSourceSetupSheet(platform: platform)
            case .limitation(let limitation):
                FitnessLimitationSheet(
                    limitation: limitation,
                    // Close this sheet, THEN open the importer — never swap the
                    // item while presented. SwiftUI drops one of two
                    // presentations made in the same transaction (the same race
                    // PostDeepLink.openAfterDismiss exists to avoid), which
                    // would leave "Import My History" doing nothing at all.
                    onImport: {
                        activeSheet = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            activeSheet = .importHistory
                        }
                    }
                )
            case .importHistory:
                ImportHistoryView(userManager: userManager)
            }
        }
    }

    /// Every modal this screen can show. Identifiable so one `.sheet(item:)`
    /// can drive all of them.
    enum ConnectionSheet: Identifiable {
        case setup(FitnessSourcePlatform)
        case limitation(FitnessSourceLimitation)
        case importHistory

        var id: String {
            switch self {
            case .setup(let p): return "setup-\(p.id)"
            case .limitation(let l): return "limitation-\(l.id)"
            case .importHistory: return "import"
            }
        }
    }

    /// Catalog entries matching the search box. The list runs to a dozen-plus
    /// platforms, which is past the point where scanning beats typing.
    private var filteredPlatforms: [FitnessSourcePlatform] {
        let available = sourceService.availablePlatforms
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return available }
        return available.filter { $0.name.lowercased().contains(query) }
    }

    /// The single most useful thing on this screen: connecting an app is
    /// forward-only, and almost nobody expects that. Stated up front, with the
    /// fix attached rather than left as a dead end.
    private var importHistoryCard: some View {
        Button { activeSheet = .importHistory } label: {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                HStack(spacing: MADTheme.Spacing.sm) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(MADTheme.Colors.redGradient)
                    Text("Bring in your past workouts")
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(.primary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                Text(
                    "Connecting an app only sends workouts from that moment on — it won't "
                        + "backfill your history. Import a file from Strava, Garmin or "
                        + "anywhere else to count everything you've already done."
                )
                .font(MADTheme.Typography.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass()
        }
        .buttonStyle(.plain)
    }

    private var troubleshootingCard: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                ForEach(Self.troubleshootingTips, id: \.self) { tip in
                    HStack(alignment: .top, spacing: MADTheme.Spacing.sm) {
                        Text("•").foregroundColor(.secondary)
                        Text(tip)
                            .font(MADTheme.Typography.footnote)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.top, MADTheme.Spacing.sm)
        } label: {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.orange)
                Text("Workouts not showing up?")
                    .font(MADTheme.Typography.smallBold)
                    .foregroundColor(.primary)
            }
        }
        .tint(.secondary)
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    private static let troubleshootingTips = [
        "Check the app's own Apple Health setting is on — that switch, not this screen, is what actually sends data.",
        "Make sure Mile A Day can read Workouts: Settings → Health → Data Access & Devices → Mile A Day.",
        "Strava only sends activities recorded in Strava itself. If your run came from a watch, connect that watch's app too.",
        "This list only counts the last 90 days, so an app you haven't used recently won't appear.",
        "Workouts recorded before you connected an app never sync — use Bring in your past workouts above.",
    ]

    /// Why some big names aren't in the list above. Every entry names the real
    /// reason, and offers the import where the platform has an export.
    private var limitationsSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            sectionHeader("Why isn't my app here?", systemImage: "info.circle.fill")

            VStack(spacing: 0) {
                ForEach(FitnessSourceCatalog.limitations) { limitation in
                    Button { activeSheet = .limitation(limitation) } label: {
                        HStack(spacing: MADTheme.Spacing.md) {
                            ZStack {
                                Circle()
                                    .fill(Color.secondary.opacity(0.15))
                                    .frame(width: 36, height: 36)
                                Image(systemName: limitation.symbol)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(limitation.name)
                                    .font(MADTheme.Typography.smallBold)
                                    .foregroundColor(.primary)
                                Text(
                                    limitation.isPartial
                                        ? "Connects, with limits" : "Can't connect"
                                )
                                .font(MADTheme.Typography.caption)
                                .foregroundColor(.secondary)
                            }
                            Spacer(minLength: MADTheme.Spacing.sm)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, MADTheme.Spacing.sm)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if limitation.id != FitnessSourceCatalog.limitations.last?.id {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass()
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
            PlatformIconView(
                symbol: source.symbol,
                tint: source.tint,
                // Nil for a HealthKit source we don't recognise — it still
                // renders, just with the generic symbol.
                appStoreId: source.platform?.appStoreId
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                    .font(MADTheme.Typography.smallBold)
                    .foregroundColor(.primary)
                Text(subtitle(for: source))
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: MADTheme.Spacing.sm)

            // Never a bare green check: a wired-up app that hasn't sent anything
            // in a month reads as broken under one, and the user goes looking
            // for a connection problem that isn't there.
            Image(systemName: source.status.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(source.status.tint)
        }
        .padding(.vertical, MADTheme.Spacing.sm)
    }

    private func subtitle(for source: DetectedFitnessSource) -> String {
        let workouts = source.workoutCount == 1 ? "1 workout" : "\(source.workoutCount) workouts"
        let miles = String(format: "%.1f mi", source.totalMiles)
        let recency = "last \(Self.relative(source.lastWorkoutDate))"
        guard source.status == .quiet else {
            return "\(workouts) · \(miles) · \(recency)"
        }
        return "\(source.status.label) · \(workouts) · \(recency)"
    }

    private static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var availableSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            sectionHeader("Add another app", systemImage: "plus.circle.fill")

            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                TextField("Search apps", text: $searchText)
                    .font(MADTheme.Typography.small)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, MADTheme.Spacing.sm)
            .madLiquidGlass()

            VStack(spacing: 0) {
                if filteredPlatforms.isEmpty {
                    Text("No apps match \"\(searchText)\". Check \"Why isn't my app here?\" below.")
                        .font(MADTheme.Typography.footnote)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, MADTheme.Spacing.sm)
                }
                ForEach(filteredPlatforms) { platform in
                    Button { activeSheet = .setup(platform) } label: {
                        availableRow(platform)
                    }
                    .buttonStyle(.plain)

                    if platform.id != filteredPlatforms.last?.id {
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
            PlatformIconView(
                symbol: platform.symbol,
                tint: platform.tint,
                appStoreId: platform.appStoreId
            )

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

/// Why a given platform can't (fully) connect, and what to do instead.
///
/// The point of this screen is that a dead end always ends in an action: where
/// the platform offers a data export, the answer is the history importer rather
/// than an apology.
struct FitnessLimitationSheet: View {
    let limitation: FitnessSourceLimitation
    let onImport: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                        Label(
                            limitation.isPartial
                                ? "Connects, with limits" : "Can't connect to Apple Health",
                            systemImage: limitation.symbol
                        )
                        .font(MADTheme.Typography.smallBold)
                        .foregroundColor(
                            limitation.isPartial ? MADTheme.Colors.warning : .secondary)

                        Text(limitation.reason)
                            .font(MADTheme.Typography.subheadline)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(MADTheme.Spacing.md)
                    .madLiquidGlass()

                    VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                        Text("What you can do")
                            .font(MADTheme.Typography.smallBold)
                            .foregroundColor(.primary)
                        Text(limitation.workaround)
                            .font(MADTheme.Typography.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(MADTheme.Spacing.md)
                    .madLiquidGlass()

                    if limitation.offersImport {
                        Button(action: onImport) {
                            Text("Import My History")
                                .font(MADTheme.Typography.bodyBold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, MADTheme.Spacing.md)
                                .background(MADTheme.Colors.redGradient)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(MADTheme.Spacing.md)
            }
            .background(MADTheme.Colors.appBackgroundGradient)
            .navigationTitle(limitation.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
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

                    // ONE destination, and it's the App Store product page.
                    // There was a "launch the app directly" button above this
                    // using a custom URL scheme; schemes can be registered by
                    // anyone, so a guessed one opened a completely unrelated
                    // app. The product page always resolves to the right app and
                    // carries its own Open button when it's installed.
                    Button {
                        FitnessSourceLauncher.openAppStore(for: platform)
                    } label: {
                        HStack(spacing: MADTheme.Spacing.sm) {
                            Image(systemName: "arrow.up.forward.app.fill")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Find \(platform.name) in the App Store")
                                .font(MADTheme.Typography.bodyBold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MADTheme.Spacing.md)
                        .background(MADTheme.Colors.redGradient)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Text(
                        "Already have it? Tap Open on the App Store page. Once the Health "
                            + "setting is on, your workouts appear here automatically — "
                            + "usually within a few minutes of finishing."
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
            PlatformIconView(
                symbol: platform.symbol,
                tint: platform.tint,
                appStoreId: platform.appStoreId,
                size: 48
            )
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
