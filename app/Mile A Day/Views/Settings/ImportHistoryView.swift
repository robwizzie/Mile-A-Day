import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Bring years of history in from a platform's own data export.
///
/// Connecting an app is **forward-only** — Strava's or Garmin's Apple Health
/// switch sends workouts from that moment on and never backfills — so this is
/// the only way a user with three years of history gets it counted here. No API
/// can do it: Strava's agreement bars the social surfaces and Garmin's
/// developer program is closed. The user's own export is the lawful route, and
/// it happens to be the complete one.
struct ImportHistoryView: View {
    @ObservedObject var userManager: UserManager
    @Environment(\.dismiss) private var dismiss

    @State private var importService = WorkoutImportService()
    @State private var phase: Phase = .instructions
    @State private var showingFilePicker = false
    @State private var parseResult: ArchiveParseResult?
    @State private var pendingWorkouts: [ImportableWorkout] = []
    @State private var alreadyImported = 0
    @State private var unitOverride: DistanceUnit?
    @State private var rawFileText: String?
    @State private var errorMessage: String?

    enum Phase: Equatable {
        case instructions
        case parsing
        /// Nothing has been written yet — the user still has to confirm.
        case preview
        case importing
        case done
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: MADTheme.Spacing.lg) {
                    switch phase {
                    case .instructions: instructionsSection
                    case .parsing: parsingSection
                    case .preview: previewSection
                    case .importing, .done: progressSection
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(MADTheme.Typography.footnote)
                            .foregroundColor(MADTheme.Colors.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(MADTheme.Spacing.md)
                            .madLiquidGlass()
                    }
                }
                .padding(MADTheme.Spacing.md)
            }
            .background(MADTheme.Colors.appBackgroundGradient)
            .navigationTitle("Import History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(phase == .done ? "Done" : "Cancel") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: Self.allowedTypes,
                allowsMultipleSelection: false
            ) { result in
                handlePickedFile(result)
            }
        }
    }

    /// `.commaSeparatedText` covers activities.csv; GPX and TCX have no system
    /// UTType, so they're matched by filename extension. `.data` is the
    /// catch-all that keeps them selectable at all in the picker.
    private static let allowedTypes: [UTType] = [
        .commaSeparatedText, .xml, .data,
    ]

    // MARK: - Phases

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                Text("Connecting an app only brings in NEW workouts.")
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(.primary)
                Text(
                    "Strava, Garmin and the rest start sending to Apple Health from the "
                        + "moment you connect them — they don't send your past workouts. To "
                        + "count your history here, import it from a file."
                )
                .font(MADTheme.Typography.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass()

            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                Text("Getting your Strava file")
                    .font(MADTheme.Typography.smallBold)
                    .foregroundColor(.primary)

                ForEach(Array(Self.stravaSteps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: MADTheme.Spacing.md) {
                        ZStack {
                            Circle()
                                .fill(MADTheme.Colors.madRed.opacity(0.15))
                                .frame(width: 26, height: 26)
                            Text("\(index + 1)")
                                .font(MADTheme.Typography.caption)
                                .foregroundColor(MADTheme.Colors.madRed)
                        }
                        Text(step)
                            .font(MADTheme.Typography.subheadline)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }

                Text(
                    "Other apps work too — anything that exports a .csv, .gpx or .tcx file."
                )
                .font(MADTheme.Typography.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass()

            Button { showingFilePicker = true } label: {
                Text("Choose File")
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

    private static let stravaSteps = [
        "On strava.com, open Settings → My Account.",
        "Tap \"Download or Delete Your Account\", then \"Request Your Archive\".",
        "Strava emails you a .zip — this can take a few hours.",
        "Unzip it and pick activities.csv here.",
    ]

    private var parsingSection: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            ProgressView()
            Text("Reading your file…")
                .font(MADTheme.Typography.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(MADTheme.Spacing.lg)
        .madLiquidGlass()
    }

    /// The confirmation gate. **Nothing has been written to Apple Health at this
    /// point** — this screen exists so a distance-unit misread shows up as an
    /// obviously wrong total the user can reject, rather than as thousands of
    /// silently wrong workouts in their Health app.
    private var previewSection: some View {
        VStack(spacing: MADTheme.Spacing.lg) {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                Text("Ready to import")
                    .font(MADTheme.Typography.title3)
                    .foregroundColor(.primary)

                statRow("Workouts", "\(pendingWorkouts.count)")
                if let range = dateRangeText {
                    statRow("Date range", range)
                }
                statRow("Total distance", String(format: "%.1f mi", totalMiles))
                if alreadyImported > 0 {
                    statRow("Already imported", "\(alreadyImported) — will be skipped")
                }
                if let skipped = parseResult?.skipped, skipped > 0 {
                    statRow("Not runs or walks", "\(skipped) — won't be imported")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass()

            // Kilometers and miles are indistinguishable from the file alone —
            // the same runs read 5.0 and 3.1 — so the user is the tiebreak.
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                Text("Do those distances look right?")
                    .font(MADTheme.Typography.smallBold)
                    .foregroundColor(.primary)
                Text(
                    "If the total looks too big or too small, your file probably uses "
                        + "different units. Change it here."
                )
                .font(MADTheme.Typography.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Picker(
                    "Units",
                    selection: Binding(
                        get: { unitOverride ?? parseResult?.detectedUnit ?? .meters },
                        set: { newValue in
                            unitOverride = newValue
                            reparse(with: newValue)
                        }
                    )
                ) {
                    ForEach(DistanceUnit.allCases) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass()

            Button {
                Task { await startImport() }
            } label: {
                Text(
                    pendingWorkouts.isEmpty
                        ? "Nothing new to import"
                        : "Import \(pendingWorkouts.count) workouts"
                )
                .font(MADTheme.Typography.bodyBold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, MADTheme.Spacing.md)
                .background(
                    pendingWorkouts.isEmpty
                        ? AnyShapeStyle(Color.secondary.opacity(0.3))
                        : AnyShapeStyle(MADTheme.Colors.redGradient)
                )
                .foregroundColor(.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(pendingWorkouts.isEmpty)

            Button("Choose a different file") { showingFilePicker = true }
                .font(MADTheme.Typography.small)
                .foregroundColor(.secondary)
        }
    }

    private var progressSection: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            switch importService.state {
            case .importing(let p):
                ProgressView(value: p.fraction)
                    .tint(MADTheme.Colors.madRed)
                Text("Adding to Apple Health — \(p.written) of \(p.total)")
                    .font(MADTheme.Typography.subheadline)
                    .foregroundColor(.secondary)
                Text("Keep this screen open.")
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.secondary)

            case .finished(let p):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(MADTheme.Colors.success)
                Text("Imported \(p.written) workouts")
                    .font(MADTheme.Typography.title3)
                    .foregroundColor(.primary)
                if p.failed > 0 {
                    Text("\(p.failed) couldn't be added.")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.secondary)
                }
                Text(
                    "Your streak and totals are being recalculated. This can take a "
                        + "moment to show everywhere."
                )
                .font(MADTheme.Typography.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            case .failed(let message):
                Text(message)
                    .font(MADTheme.Typography.subheadline)
                    .foregroundColor(MADTheme.Colors.error)

            case .idle:
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(MADTheme.Spacing.lg)
        .madLiquidGlass()
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(MADTheme.Typography.small)
                .foregroundColor(.secondary)
            Spacer(minLength: MADTheme.Spacing.sm)
            Text(value)
                .font(MADTheme.Typography.smallBold)
                .foregroundColor(.primary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Derived

    private var totalMiles: Double {
        pendingWorkouts.reduce(0) { $0 + $1.miles }
    }

    private var dateRangeText: String? {
        guard
            let first = pendingWorkouts.map({ $0.start }).min(),
            let last = pendingWorkouts.map({ $0.start }).max()
        else { return nil }
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        let a = f.string(from: first)
        let b = f.string(from: last)
        return a == b ? a : "\(a) – \(b)"
    }

    // MARK: - Actions

    private func handlePickedFile(_ result: Result<[URL], Error>) {
        errorMessage = nil
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            phase = .parsing
            Task { await parse(url) }
        }
    }

    // @MainActor on the async methods that touch @State: a plain `async` method
    // on a View is nonisolated and would mutate view state off the main actor.
    // Parsing is fast enough to sit here (the awaits inside suspend rather than
    // block, and the "Reading your file…" phase covers it).
    @MainActor
    private func parse(_ url: URL) async {
        // A file from the Files app lives outside our sandbox; without the
        // security scope the read fails with a permissions error.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            errorMessage = "Couldn't read that file. Make sure it's a .csv, .gpx or .tcx."
            phase = .instructions
            return
        }

        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.lowercased()

        // Off the main actor: a multi-thousand-row archive is real CPU work, and
        // running it inline would freeze the very spinner that's meant to show
        // it happening. Awaiting here also lets `.parsing` actually paint first.
        let result = await Task.detached(priority: .userInitiated) {
            Self.parseText(text, extension: ext, stem: stem)
        }.value

        let fresh = await importService.filterAlreadyImported(result.workouts)

        // Only a CSV can be re-interpreted with different units; GPX and TCX
        // carry unambiguous ones, so there's nothing to re-read for those.
        rawFileText = (ext == "csv" || ext.isEmpty) ? text : nil
        parseResult = result
        unitOverride = nil
        pendingWorkouts = fresh
        alreadyImported = result.workouts.count - fresh.count
        errorMessage = result.workouts.isEmpty ? "No runs or walks found in that file." : nil
        phase = .preview
    }

    /// Format dispatch. `nonisolated static` so it can run off the main actor —
    /// it touches no view state, only the pure parser.
    private nonisolated static func parseText(
        _ text: String, extension ext: String, stem: String
    ) -> ArchiveParseResult {
        switch ext {
        case "gpx":
            let one = WorkoutArchiveParser.parseGPX(text, activityId: stem)
            return ArchiveParseResult(
                workouts: one.map { [$0] } ?? [],
                skipped: one == nil ? 1 : 0,
                detectedUnit: .meters
            )
        case "tcx":
            let one = WorkoutArchiveParser.parseTCX(text, activityId: stem)
            return ArchiveParseResult(
                workouts: one.map { [$0] } ?? [],
                skipped: one == nil ? 1 : 0,
                detectedUnit: .meters
            )
        default:
            return WorkoutArchiveParser.parseStravaCSV(text)
        }
    }

    /// Re-run the CSV with the user's chosen units. Only meaningful for CSV —
    /// GPX and TCX carry unambiguous units, so there's nothing to re-interpret.
    private func reparse(with unit: DistanceUnit) {
        guard let text = rawFileText else { return }
        let result = WorkoutArchiveParser.parseStravaCSV(text, unitOverride: unit)
        parseResult = result
        let known = Set(pendingWorkouts.map { $0.id })
        pendingWorkouts = result.workouts.filter { known.contains($0.id) }
    }

    @MainActor
    private func startImport() async {
        phase = .importing
        await importService.run(pendingWorkouts, platform: "Strava")
        phase = .done

        // Pull the new workouts into the local index and push them up, then let
        // the server recompute — imported history legitimately changes the
        // streak, and this is what makes local and backend agree in one pass.
        HealthKitManager.shared.fetchAllWorkoutData()
        try? await WorkoutSyncService.shared.syncNewWorkouts()
        await recalibrateStreak()
    }

    @MainActor
    private func recalibrateStreak() async {
        guard let userId = userManager.currentUser.backendUserId, !userId.isEmpty else { return }
        struct Resp: Decodable { let streak: Int }
        _ = try? await APIClient.fancyFetch(
            endpoint: "/workouts/\(userId)/recalibrate-streak",
            method: .POST,
            responseType: Resp.self
        )
    }
}
