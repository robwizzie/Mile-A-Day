import SwiftUI

/// The three screens a two-sided Streak Assist needs, kept together because
/// they're the same trade seen from three angles:
///
///  - `StreakAssistOfferSheet` — something is waiting on YOUR answer. Either a
///    friend ran you a mile (accept and it costs your token) or a friend asked
///    for one of yours (accept and it costs a mile you already ran).
///  - `DonateMileSheet` — you have spare miles; here's who can use them.
///  - `AskForMileSheet` — you're holding a token and short a mile; here's who
///    to ask.
///
/// None of them can complete a save alone, which is the whole point: a coverage
/// row needs the recipient's token AND the donor's mile, so every screen here
/// ends in a request for the other person's answer.

// MARK: - Answer an offer/request (app-entry popup)

struct StreakAssistOfferSheet: View {
    let offers: [PendingAssistOffer]
    /// Called after every answer so the host can drop the sheet once the queue
    /// empties. Passed the offer that was just resolved.
    var onResolved: (PendingAssistOffer) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var busyOfferId: String?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(offers) { offer in
                        offerCard(offer)
                    }
                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.top, 12)
            }
            .background(MADTheme.Colors.appBackgroundGradient.ignoresSafeArea())
            .navigationTitle("Streak Assist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { dismiss() }
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
    }

    @ViewBuilder
    private func offerCard(_ offer: PendingAssistOffer) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                AvatarView(
                    name: offer.displayName,
                    imageURL: offer.profile_image_url,
                    size: 46
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(headline(offer))
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(SaveFriendStreakView.dayLabel(offer.target_date))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
                TokenMedallion(kind: .assist, held: true, size: 34)
            }

            Text(explanation(offer))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.72))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    respond(offer, accept: false)
                } label: {
                    Text("No thanks")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.06))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    respond(offer, accept: true)
                } label: {
                    Group {
                        if busyOfferId == offer.offer_id {
                            ProgressView().tint(.white).scaleEffect(0.7)
                        } else {
                            Text(offer.isIncomingMile ? "Use My Assist" : "Donate My Mile")
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(MADTheme.Colors.redGradient))
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(busyOfferId != nil)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private func headline(_ offer: PendingAssistOffer) -> String {
        offer.isIncomingMile
            ? "\(offer.displayName) ran you a mile"
            : "\(offer.displayName) needs a mile"
    }

    private func explanation(_ offer: PendingAssistOffer) -> String {
        if offer.isIncomingMile {
            return "They went a mile past their own goal for you. Spend your Streak Assist to take it and your streak lands on \(offer.restored_streak) days."
        }
        return "They're holding a Streak Assist but need someone's spare mile to spend it. Donate one of the miles you ran past your goal today and their streak lands on \(offer.restored_streak) days."
    }

    private func respond(_ offer: PendingAssistOffer, accept: Bool) {
        guard busyOfferId == nil else { return }
        busyOfferId = offer.offer_id
        errorText = nil
        Task { @MainActor in
            defer { busyOfferId = nil }
            do {
                _ = try await StreakFeatureService.respondToOffer(
                    offerId: offer.offer_id, accept: accept
                )
                if accept { MADHaptics.success() } else { MADHaptics.tap() }
                await StreakTokensState.shared.refreshStatus()
                onResolved(offer)
            } catch {
                MADHaptics.warning()
                // The day may have been run, covered by someone else, or the
                // donor's miles re-synced downward — say so rather than
                // leaving a button that silently does nothing.
                errorText = "That one can't be completed anymore — their day may already be covered."
                await StreakTokensState.shared.refreshStatus()
            }
        }
    }
}

// MARK: - Spend today's spare miles

struct DonateMileSheet: View {
    @ObservedObject private var tokensState = StreakTokensState.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header

                    if tokensState.assistableFriends.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 10) {
                            ForEach(tokensState.assistableFriends) { friend in
                                friendRow(friend)
                            }
                        }
                    }
                }
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.top, 12)
            }
            .background(MADTheme.Colors.appBackgroundGradient.ignoresSafeArea())
            .navigationTitle("Donate a Mile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .task { await tokensState.refreshStatus() }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            TokenMedallion(kind: .assist, held: true, size: 52)
            Text(headline)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text("A friend holding a Streak Assist can't spend it without someone's spare mile. Every mile past your own goal today covers one friend.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }

    private var headline: String {
        let remaining = tokensState.donationBudget?.remaining ?? 0
        if remaining <= 0 {
            let toGo = tokensState.donationBudget?.milesToNext ?? 1
            return String(format: "%.2f mi further unlocks a donation", toGo)
        }
        return remaining == 1
            ? "You have 1 mile to give"
            : "You have \(remaining) miles to give"
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(.white.opacity(0.25))
            Text("No friends need a mile right now")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
            Text("They'll show up here when they're holding a Streak Assist and have a day to save.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 30)
    }

    private func friendRow(_ friend: AssistableFriend) -> some View {
        HStack(spacing: 12) {
            AvatarView(
                name: friend.displayName,
                imageURL: friend.profile_image_url,
                size: 42
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                // "Hasn't run today" and "missed yesterday" are very different
                // asks — one is a heads-up, the other is a rescue.
                Text(
                    friend.isToday
                        ? "Hasn't run today · streak stays at \(friend.streakAfterSave)"
                        : "Missed \(SaveFriendStreakView.dayLabel(friend.target_date)) · back to \(friend.streakAfterSave)"
                )
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            SaveFriendStreakView(
                friendId: friend.user_id,
                friendName: friend.displayName,
                style: .compact,
                preloaded: preloaded(for: friend)
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    /// Same shaping the friends list does — one status call already carries
    /// every candidate, so no row needs its own fetch.
    private func preloaded(for friend: AssistableFriend) -> FriendRescueStatus {
        let budget = tokensState.donationBudget
        let outOfMiles = (budget?.remaining ?? 0) < 1
        return FriendRescueStatus(
            available: !friend.alreadyOffered && !outOfMiles,
            target_date: friend.target_date,
            target_kind: friend.target_kind,
            prior_streak: friend.prior_streak,
            restored_streak: friend.restored_streak,
            self_recovery: nil,
            friend_holds_assist: true,
            viewer_budget: budget,
            offer_status: friend.offer_status,
            offer_id: friend.offer_id,
            reason: friend.alreadyOffered ? nil : (outOfMiles ? "no_miles" : nil)
        )
    }
}

// MARK: - Ask a friend for a mile

struct AskForMileSheet: View {
    let savableDay: SavableDay
    @ObservedObject var friendService: FriendService
    @ObservedObject private var tokensState = StreakTokensState.shared
    @Environment(\.dismiss) private var dismiss

    @State private var askedIds: Set<String> = []
    @State private var busyId: String?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    if friendService.friends.isEmpty {
                        Text("Add a friend first — an Assist always takes two people.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.top, 30)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(friendService.friends) { friend in
                                friendRow(friend)
                            }
                        }
                    }
                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.top, 12)
            }
            .background(MADTheme.Colors.appBackgroundGradient.ignoresSafeArea())
            .navigationTitle("Ask for a Mile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            TokenMedallion(kind: .assist, held: true, size: 52)
            Text(
                savableDay.isToday
                    ? "Keep your \(savableDay.restored_streak)-day streak"
                    : "Get back to \(savableDay.restored_streak) days"
            )
            .font(.system(size: 17, weight: .heavy, design: .rounded))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            Text("You're holding a Streak Assist, but spending it takes a mile a friend ran past their own goal. Ask as many as you like — the first to say yes covers \(SaveFriendStreakView.dayLabel(savableDay.local_date)).")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func friendRow(_ friend: BackendUser) -> some View {
        HStack(spacing: 12) {
            AvatarView(
                name: friend.displayName,
                imageURL: friend.profile_image_url,
                size: 42
            )
            Text(friend.username ?? friend.displayName)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
            Spacer(minLength: 6)
            if askedIds.contains(friend.user_id) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                    Text("Asked")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.green.opacity(0.14)))
            } else {
                Button {
                    ask(friend)
                } label: {
                    Group {
                        if busyId == friend.user_id {
                            ProgressView().tint(.white).scaleEffect(0.6)
                        } else {
                            Text("Ask")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(MADTheme.Colors.redGradient))
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(busyId != nil)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func ask(_ friend: BackendUser) {
        guard busyId == nil else { return }
        busyId = friend.user_id
        errorText = nil
        Task { @MainActor in
            defer { busyId = nil }
            do {
                _ = try await StreakFeatureService.requestAssist(friendId: friend.user_id)
                MADHaptics.success()
                _ = askedIds.insert(friend.user_id)
            } catch {
                MADHaptics.warning()
                // Most likely already asked, or the day stopped being savable
                // (they ran it, or it aged out) — both are worth saying.
                errorText = "Couldn't send that ask. You may have already asked \(friend.displayName)."
            }
        }
    }
}
