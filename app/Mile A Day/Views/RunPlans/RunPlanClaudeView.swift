import SwiftUI
import UIKit

/// Connect Claude: the coach MCP connector on mileaday.run. Claude reads the
/// runner's runs, plan and check-ins through THEIR OWN Claude account and
/// proposes changes the same rules engine caps. Plan changes wait for
/// approval unless the runner turns on auto-apply.
struct RunPlanClaudeView: View {
    static let connectorURL = "https://mileaday.run/mcp"
    static let claudeColor = Color(red: 0.85, green: 0.47, blue: 0.34)

    @ObservedObject private var store = RunPlanStore.shared
    @State private var copied = false
    @State private var savingAutoApply = false
    @State private var busyProposalId: String?
    @State private var confirmDisconnect = false
    @State private var disconnecting = false
    @State private var errorText: String?

    private var claude: RunPlanClaudeStatus? { store.current?.claude }
    private var connected: Bool { claude?.connected == true }
    private var autoApply: Bool { store.plan?.autoApplyClaude ?? false }
    private var claudeProposals: [RunPlanProposal] { store.pendingProposals.filter(\.isFromClaude) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                statusCard
                urlCard
                howToCard
                abilitiesCard
                if !claudeProposals.isEmpty { waitingCard }
                disclosure
                if connected { disconnectButton }
            }
            .padding(16)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Claude")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.refresh() }
        .confirmationDialog("Disconnect Claude?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive, action: disconnect)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Claude loses access to your runs and plan right away. You can connect again anytime.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    // MARK: Cards

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Self.claudeColor))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude")
                        .madFont(size: 16, weight: .black, design: .rounded)
                        .foregroundColor(.white)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(connected ? RunPlanColors.green : Color.white.opacity(0.35))
                            .frame(width: 6, height: 6)
                        Text(statusLine)
                            .madFont(size: 12, weight: .bold, design: .rounded)
                            .foregroundColor(connected ? RunPlanColors.green : .white.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            Text("For a deeper review than Flamey can do. Works from Claude on any device, with your own Claude account.")
                .madFont(size: 13, weight: .medium, design: .rounded)
                .foregroundColor(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .runPlanCard()
    }

    private var statusLine: String {
        guard connected else { return "Not connected" }
        guard let used = BuddyDate.parse(claude?.last_used_at) else { return "Connected" }
        let ago = RelativeDateTimeFormatter().localizedString(for: used, relativeTo: Date())
        return "Connected · last used \(ago)"
    }

    private var urlCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Connector URL")
            HStack(spacing: 8) {
                Text(Self.connectorURL)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .textSelection(.enabled)
                Spacer(minLength: 4)
                Button {
                    UIPasteboard.general.string = Self.connectorURL
                    MADHaptics.success()
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .madFont(size: 13, weight: .heavy, design: .rounded, maxScale: 1.4)
                        .foregroundColor(RunPlanColors.orange)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(copied ? "Copied" : "Copy connector URL")
            }
        }
        .runPlanCard(radius: 18, padding: 12)
    }

    private var howToCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("How to connect")
            step(number: 1, title: "Claude app or claude.ai",
                 detail: "Settings › Connectors › Add custom connector. Paste the URL, then sign in with Apple.")
            step(number: 2, title: "Claude Code",
                 detail: "claude mcp add --transport http mile-a-day \(Self.connectorURL)\nthen run /mcp and sign in with Apple.")
            Text("Use the Apple ID you sign in to Mile A Day with.")
                .madFont(size: 12, weight: .medium, design: .rounded)
                .foregroundColor(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .runPlanCard(radius: 18, padding: 12)
    }

    private func step(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .madFont(size: 12, weight: .black, design: .rounded, maxScale: 1.3)
                .foregroundColor(.black)
                .frame(width: 22, height: 22)
                .background(Circle().fill(RunPlanColors.orange))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .madFont(size: 14, weight: .bold, design: .rounded)
                    .foregroundColor(.white)
                Text(detail)
                    .madFont(size: 12.5, weight: .medium, design: .rounded)
                    .foregroundColor(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var abilitiesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("What Claude can do")
            ability("Read your runs and splits")
            ability("Read your plan and check-ins")
            ability("Suggest plan changes, with the same safety caps as Flamey")
            HStack(spacing: 8) {
                Text("Plan changes")
                    .madFont(size: 13, weight: .semibold, design: .rounded)
                    .foregroundColor(.white.opacity(0.7))
                Spacer(minLength: 4)
                if savingAutoApply {
                    ProgressView().tint(RunPlanColors.orange)
                } else {
                    Menu {
                        Picker("Plan changes", selection: Binding(get: { autoApply }, set: { setAutoApply($0) })) {
                            Text("Ask me first").tag(false)
                            Text("Apply automatically").tag(true)
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(autoApply ? "Apply automatically" : "Ask me first")
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .accessibilityHidden(true)
                        }
                        .madFont(size: 13, weight: .black, design: .rounded, maxScale: 1.4)
                        .foregroundColor(RunPlanColors.orange)
                        .frame(minHeight: 44)
                    }
                    .accessibilityLabel("Plan changes from Claude")
                    .accessibilityValue(autoApply ? "Apply automatically" : "Ask me first")
                }
            }
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
            .padding(.top, 4)
            if autoApply {
                Text("Claude's changes apply as soon as it makes them, still inside the plan's safety caps.")
                    .madFont(size: 11.5, weight: .medium, design: .rounded)
                    .foregroundColor(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .runPlanCard(radius: 18, padding: 12)
    }

    private func ability(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .madFont(size: 14, weight: .bold, maxScale: 1.3)
                .foregroundColor(RunPlanColors.green)
                .accessibilityHidden(true)
            Text(text)
                .madFont(size: 13.5, weight: .semibold, design: .rounded)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private var waitingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Waiting for you")
            ForEach(claudeProposals) { proposal in
                RunPlanProposalCard(proposal: proposal, busy: busyProposalId == proposal.id,
                                    applyTitle: "Apply", declineTitle: "Decline",
                                    onApply: { decide(proposal, apply: true) },
                                    onDecline: { decide(proposal, apply: false) })
            }
        }
    }

    private var disclosure: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "lock.fill")
                .madFont(size: 11, weight: .bold, maxScale: 1.3)
                .accessibilityHidden(true)
            Text("Claude is made by Anthropic. Once you connect, Claude can read your runs, plan and check-ins through your own Claude account. Only you can see them, and you can disconnect anytime.")
                .madFont(size: 11, weight: .medium, design: .rounded)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(.white.opacity(0.4))
        .padding(.horizontal, 4)
    }

    private var disconnectButton: some View {
        Button {
            confirmDisconnect = true
        } label: {
            HStack {
                if disconnecting { ProgressView().tint(RunPlanColors.red) }
                Text("Disconnect Claude")
                    .madFont(size: 14, weight: .heavy, design: .rounded)
            }
            .foregroundColor(RunPlanColors.red)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(disconnecting)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .madFont(size: 11, weight: .black, design: .rounded, maxScale: 1.3)
            .tracking(1)
            .foregroundColor(.white.opacity(0.45))
    }

    // MARK: Actions

    private func setAutoApply(_ on: Bool) {
        guard on != autoApply, !savingAutoApply else { return }
        savingAutoApply = true
        Task {
            defer { savingAutoApply = false }
            do {
                try await store.update(RunPlanUpdate(claude_auto_apply: on))
            } catch {
                errorText = RunPlanError.from(error).message
            }
        }
    }

    private func decide(_ proposal: RunPlanProposal, apply: Bool) {
        guard busyProposalId == nil else { return }
        busyProposalId = proposal.id
        Task {
            defer { busyProposalId = nil }
            do {
                if apply { try await store.apply(proposal) } else { try await store.decline(proposal) }
            } catch {
                errorText = RunPlanError.from(error).message
            }
        }
    }

    private func disconnect() {
        disconnecting = true
        Task {
            defer { disconnecting = false }
            do {
                try await store.disconnectClaude()
            } catch {
                errorText = RunPlanError.from(error).message
            }
        }
    }
}
