import SwiftUI

/// Everything about referrals in one place: how it works, what you've earned,
/// how each friend is doing, and who to ask when something looks wrong.
struct ReferralsView: View {
    private let service = ReferralService.shared
    @State private var pick: BackendUser?
    @State private var isSaving = false
    @State private var redeeming = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let status = service.status {
                    summary(status)
                    howItWorks(status)
                    if status.can_add_referrer { addReferrer }
                    rewards(status)
                    if !status.friends.isEmpty { friends(status) }
                    if let by = status.referred_by { referredBy(by, status: status) }
                    help(status)
                } else {
                    ProgressView().tint(.white).frame(maxWidth: .infinity).padding(40)
                }
            }
            .padding(16)
            .lockedToScrollWidth()
        }
        .background(MADTheme.Colors.appBackgroundGradient.ignoresSafeArea())
        .navigationTitle("Invite friends")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await service.refresh() }
        .task { await service.refresh() }
        .alert("Couldn't do that", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func summary(_ status: ReferralStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(status.qualified)")
                    .madFont(size: 40, weight: .heavy, design: .rounded)
                    .foregroundColor(.white)
                Text(status.qualified == 1 ? "referral" : "referrals")
                    .madFont(size: 16, weight: .bold, design: .rounded)
                    .foregroundColor(.white.opacity(0.7))
            }
            if let next = status.nextReward {
                let left = next.count - status.qualified
                Text("\(left) more for \(next.title)")
                    .madFont(size: 14, weight: .semibold, design: .rounded, maxScale: 1.4)
                    .foregroundColor(.white.opacity(0.75))
            }
            if let username = status.username {
                ShareLink(
                    item: URL(string: "https://mileaday.run/u/\(username)")!,
                    message: Text("Join me on Mile A Day! When you sign up, choose \"Friend or family\" and pick @\(username).")
                ) {
                    Text("Invite a friend")
                        .madFont(size: 16, weight: .bold, design: .rounded)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Capsule().fill(MADTheme.Colors.madRed))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .referralCard()
    }

    private func howItWorks(_ status: ReferralStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            label("How it works")
            step(1, "Send your friend your invite.")
            step(2, "When they sign up, they choose \"Friend or family\" and pick your account.")
            step(3, "It counts once they've walked a mile on \(status.days_needed) different days within \(status.window_days) days of joining.")
        }
        .referralCard()
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .madFont(size: 14, weight: .heavy, design: .rounded, maxScale: 1.3)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.1)))
                .accessibilityHidden(true)
            Text(text)
                .madFont(size: 14, weight: .medium, design: .rounded, maxScale: 1.4)
                .foregroundColor(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var addReferrer: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("Who referred you?")
            ReferrerPicker(selection: $pick)
            if let pick, let username = pick.username {
                Button {
                    Task { await save(username) }
                } label: {
                    Text(isSaving ? "Saving…" : "Save")
                        .madFont(size: 15, weight: .bold, design: .rounded)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(MADTheme.Colors.madRed))
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
        }
        .referralCard()
    }

    private func save(_ username: String) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await service.setReferrer(username: username)
            pick = nil
            MADHaptics.success()
        } catch {
            errorMessage = "That didn't save. Check it's the right account, or contact us below."
        }
    }

    private func rewards(_ status: ReferralStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            label("Rewards")
            ForEach(status.rewards) { reward in
                rewardRow(reward, status: status)
            }
        }
        .referralCard()
    }

    private func rewardRow(_ reward: ReferralStatus.Reward, status: ReferralStatus) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(reward.count)")
                .madFont(size: 15, weight: .heavy, design: .rounded, maxScale: 1.3)
                .foregroundColor(reward.isReached ? .black : .white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(reward.isReached ? Color.green : Color.white.opacity(0.1)))
                .accessibilityLabel("\(reward.count) referrals")
            VStack(alignment: .leading, spacing: 2) {
                Text(reward.title)
                    .madFont(size: 15, weight: .bold, design: .rounded)
                    .foregroundColor(.white)
                Text(reward.description)
                    .madFont(size: 13, weight: .medium, design: .rounded, maxScale: 1.4)
                    .foregroundColor(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                if reward.kind == "free_year", reward.isReached {
                    freeYearAction(reward, status: status)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Already on Plus: the reward waits, rather than being spent on nothing.
    @ViewBuilder
    private func freeYearAction(_ reward: ReferralStatus.Reward, status: ReferralStatus) -> some View {
        if status.has_plus && reward.code == nil {
            Text("You already have Plus, so this stays here for later.")
                .madFont(size: 13, weight: .semibold, design: .rounded, maxScale: 1.4)
                .foregroundColor(.green)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Button(reward.code == nil ? "Claim your free year" : "Open your code") {
                    Task { await claim(reward) }
                }
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(MADTheme.Colors.madRed)
                .disabled(redeeming)
                Text("Redeemed through Apple. It renews at the regular price after the free year unless you cancel.")
                    .madFont(size: 12, weight: .medium, design: .rounded, maxScale: 1.4)
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
    }

    private func claim(_ reward: ReferralStatus.Reward) async {
        if let code = reward.code {
            ReferralService.openRedemption(code: code)
            return
        }
        redeeming = true
        defer { redeeming = false }
        do {
            try await service.redeemFreeYear()
        } catch {
            errorMessage = "We couldn't get your code just now. Try again soon, or contact us below."
        }
    }

    private func friends(_ status: ReferralStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            label("Your friends")
            ForEach(status.friends) { friend in
                HStack(spacing: 10) {
                    AvatarWithRing(name: friend.displayName, imageURL: friend.profile_image_url,
                                   progress: Double(friend.days) / Double(status.days_needed), size: 40)
                    Text(friend.displayName)
                        .madFont(size: 15, weight: .bold, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(friendLine(friend, status: status))
                        .madFont(size: 13, weight: .semibold, design: .rounded, maxScale: 1.3)
                        .foregroundColor(friend.status == "qualified" ? .green : .white.opacity(0.65))
                        .lineLimit(1)
                }
            }
        }
        .referralCard()
    }

    private func friendLine(_ friend: ReferralStatus.Friend, status: ReferralStatus) -> String {
        switch friend.status {
        case "qualified": return "Counted"
        case "expired": return "Didn't reach \(status.days_needed) days"
        default: return "\(friend.days) of \(status.days_needed) days"
        }
    }

    private func referredBy(_ by: ReferralStatus.ReferredBy, status: ReferralStatus) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            label("Referred by")
            Text(by.first_name ?? by.username ?? "A friend")
                .madFont(size: 16, weight: .bold, design: .rounded)
                .foregroundColor(.white)
            Text(by.status == "qualified" ? "Your referral has counted. Thanks for walking."
                                          : "\(min(by.days, status.days_needed)) of \(status.days_needed) days walked.")
                .madFont(size: 13, weight: .medium, design: .rounded, maxScale: 1.4)
                .foregroundColor(.white.opacity(0.65))
        }
        .referralCard()
    }

    @ViewBuilder
    private func help(_ status: ReferralStatus) -> some View {
        if let url = ReferralService.supportURL(username: status.username) {
            Link(destination: url) {
                HStack(spacing: 10) {
                    Image(systemName: "envelope.fill")
                        .foregroundColor(MADTheme.Colors.madRed)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Referral not showing up?")
                            .madFont(size: 15, weight: .bold, design: .rounded)
                            .foregroundColor(.white)
                        Text("Email us and we'll connect it.")
                            .madFont(size: 13, weight: .medium, design: .rounded, maxScale: 1.4)
                            .foregroundColor(.white.opacity(0.65))
                    }
                    Spacer(minLength: 0)
                }
                .referralCard()
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .madFont(size: 12, weight: .bold, design: .rounded, maxScale: 1.4)
            .foregroundColor(.white.opacity(0.65))
            .lineLimit(1)
    }
}

private extension View {
    func referralCard() -> some View {
        padding(DashboardCardSurface.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DashboardCardSurface(style: .fun))
    }
}
