//
//  FriendsOutSheet.swift
//  Mile A Day
//
//  The tap-through from the "X is out right now" pulse on the tracking
//  screen: every friend currently mid-walk/run, each with a Hype button.
//  Hypes ride the existing mile-context endpoint (composite key from the
//  friend's user_id + their local_date, both provided by the heartbeat) —
//  and land on THEIR tracking screen / Live Activity within a heartbeat.
//
//  All feedback renders inside this sheet (house rule: a toast drawn by the
//  presenting view is invisible while a sheet is up).
//

import SwiftUI

struct FriendsOutSheet: View {
    let friends: [LiveFriendOut]

    @Environment(\.dismiss) private var dismiss
    @State private var hypedIds: Set<String> = []
    @State private var sendingIds: Set<String> = []
    @State private var noticeText: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.green.opacity(0.35)).frame(width: 10, height: 10).scaleEffect(1.8)
                    Circle().fill(Color.green).frame(width: 10, height: 10)
                }
                Text("Out right now")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 12)

            if let noticeText {
                Text(noticeText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(friends) { friend in
                        friendRow(friend)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .presentationBackground(.regularMaterial)
    }

    private func friendRow(_ friend: LiveFriendOut) -> some View {
        let hyped = hypedIds.contains(friend.user_id)
        let sending = sendingIds.contains(friend.user_id)

        return HStack(spacing: 12) {
            AvatarView(
                name: friend.displayName,
                imageURL: friend.profile_image_url,
                size: 44
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(friend.displayName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Image(systemName: friend.workout_type == "running" ? "figure.run" : "figure.walk")
                        .font(.system(size: 11, weight: .semibold))
                    Text(activityLine(friend))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                sendHype(to: friend)
            } label: {
                HStack(spacing: 5) {
                    if sending {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: hyped ? "checkmark" : "flame.fill")
                            .font(.system(size: 12, weight: .bold))
                    }
                    Text(hyped ? "Hyped" : "Hype")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                }
                .foregroundColor(hyped ? .secondary : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(hyped ? Color.secondary.opacity(0.15) : MADTheme.Colors.madRed)
                )
            }
            .buttonStyle(.plain)
            .disabled(hyped || sending)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func activityLine(_ friend: LiveFriendOut) -> String {
        let verb = friend.workout_type == "running" ? "On a run" : "On a walk"
        if let minutes = minutesSince(friend.started_at), minutes >= 1 {
            return "\(verb) · \(minutes)m in"
        }
        return "\(verb) · just started"
    }

    private func minutesSince(_ iso: String) -> Int? {
        let parse = ISO8601DateFormatter()
        parse.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parse.date(from: iso) ?? {
            parse.formatOptions = [.withInternetDateTime]
            return parse.date(from: iso)
        }()
        guard let date else { return nil }
        return max(0, Int(Date().timeIntervalSince(date) / 60))
    }

    private func sendHype(to friend: LiveFriendOut) {
        sendingIds.insert(friend.user_id)
        noticeText = nil
        Task {
            defer { _ = sendingIds.remove(friend.user_id) }
            do {
                let context = HypeContext(
                    contextType: "mile",
                    contextId: "\(friend.user_id):\(friend.local_date)",
                    contextLabel: "their live \(friend.workout_type == "running" ? "run" : "walk")"
                )
                _ = try await HypeService.sendHype(targetUserId: friend.user_id, context: context)
                MADHaptics.action()
                hypedIds.insert(friend.user_id)
            } catch APIError.conflict {
                // Already hyped their mile today — reflect it, don't error.
                hypedIds.insert(friend.user_id)
            } catch APIError.rateLimited {
                noticeText = "You're out of hypes for today — they refill at midnight."
            } catch {
                noticeText = "Couldn't send that hype — try again in a moment."
            }
        }
    }
}
