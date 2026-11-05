import Foundation

// `NotificationPreferences` is one stored blob and one server row
// (`PUT /notifications/preferences`), but two Settings screens own halves of
// it: Notifications owns the alerts, Privacy owns "who sees what". Each screen
// sends ONLY its own keys (the endpoint updates just the fields it's given) and
// writes only its own fields over the stored blob, so neither can push the
// other's stale copy over a newer value.
//
// Lives in the iOS target only: `NotificationPreferences.swift` is also a Watch
// member and has to stay small.

extension NotificationPreferences {
    /// The privacy half: who can see my workouts, what reaches the feed, maps,
    /// flyovers and the profile grid. Owned by `PrivacyHubView`.
    var sharingPayload: [String: Any] {
        [
            "workout_visibility": workoutVisibility.rawValue,
            "share_workouts_to_feed": shareWorkoutsToFeed,
            "share_route_maps": shareRouteMaps,
            "share_live_presence": shareLivePresence,
            // Enforced locally (the app builds that card), sent so the choice
            // survives a reinstall and follows a new phone.
            "auto_post_without_photo": autoPostWithoutPhoto,
            // Server-enforced: the profile grid is built by SQL, and these
            // choices must affect visitors too.
            "auto_posts_on_profile": autoPostsOnProfile,
            "tagged_posts_on_profile": taggedPostsOnProfile,
            // Server-enforced at the feed projection (flyover_allowed).
            "flyover_visibility": flyoverVisibility.rawValue,
        ]
    }

    /// The alerts half. Owned by `NotificationSettingsView`. Never carries
    /// stealth keys (`StealthModeView` owns that PUT) or `route_privacy_meters`
    /// (`RoutePrivacySettingRow` owns that one).
    var alertPayload: [String: Any] {
        [
            "nudges_enabled": friendNudgeEnabled && competitionNudgeEnabled,
            "flexes_enabled": competitionFlexEnabled,
            "hypes_enabled": hypeEnabled,
            "step_goal_enabled": stepGoalEnabled,
            "friend_activity_enabled": friendCompletedEnabled,
            "friend_personal_best_enabled": friendPersonalBestEnabled,
            "competition_invites_enabled": competitionInviteEnabled,
            "competition_updates_enabled": competitionAcceptedEnabled && competitionStartEnabled && competitionFinishEnabled,
            "competition_milestones_enabled": competitionMilestonesEnabled,
            "quiet_hours_start": dndEnabled ? dndStartHour : NSNull(),
            "quiet_hours_end": dndEnabled ? dndEndHour : NSNull(),
            "daily_reminder_enabled": dailyReminderEnabled,
            "daily_reminder_hour": dailyReminderHour,
            "timezone_offset_minutes": TimeZone.current.secondsFromGMT() / 60,
            "friend_posts_enabled": friendPostsEnabled,
            "weekly_recap_enabled": weeklyRecapEnabled,
            // Must reach the server: sent by a cron and by the sync path, so a
            // local-only flag could never silence them (App Review 4.5.4).
            "weekly_challenge_enabled": weeklyChallengeEnabled,
            "friend_request_reminder_enabled": friendRequestReminderEnabled,
            // Must reach the server: it also decides whether you appear in
            // friends' buddy pickers at all, which is a SQL query.
            "buddy_invites_enabled": buddyInvitesEnabled,
        ]
    }

    /// Copies the privacy half from `other`.
    mutating func takeSharing(from other: NotificationPreferences) {
        workoutVisibility = other.workoutVisibility
        shareWorkoutsToFeed = other.shareWorkoutsToFeed
        shareRouteMaps = other.shareRouteMaps
        shareLivePresence = other.shareLivePresence
        autoPostWithoutPhoto = other.autoPostWithoutPhoto
        autoPostsOnProfile = other.autoPostsOnProfile
        taggedPostsOnProfile = other.taggedPostsOnProfile
        flyoverVisibility = other.flyoverVisibility
    }

    /// The privacy half as a value, so a screen can tell "changed by the
    /// user" from "already saved / adopted from the server".
    var sharingSnapshot: SharingSnapshot {
        SharingSnapshot(
            workoutVisibility: workoutVisibility,
            shareWorkoutsToFeed: shareWorkoutsToFeed,
            shareRouteMaps: shareRouteMaps,
            shareLivePresence: shareLivePresence,
            autoPostWithoutPhoto: autoPostWithoutPhoto,
            autoPostsOnProfile: autoPostsOnProfile,
            taggedPostsOnProfile: taggedPostsOnProfile,
            flyoverVisibility: flyoverVisibility
        )
    }

    struct SharingSnapshot: Equatable {
        let workoutVisibility: WorkoutVisibility
        let shareWorkoutsToFeed: Bool
        let shareRouteMaps: Bool
        let shareLivePresence: Bool
        let autoPostWithoutPhoto: Bool
        let autoPostsOnProfile: Bool
        let taggedPostsOnProfile: Bool
        let flyoverVisibility: FlyoverVisibility
    }

    /// Writes this copy's privacy fields over the stored blob, leaving the
    /// alerts and hide-start-&-end as stored.
    func saveSharing() {
        var stored = NotificationPreferences.load()
        stored.takeSharing(from: self)
        stored.save()
    }

    /// Writes this copy's alert fields over the stored blob, leaving the
    /// privacy fields and hide-start-&-end as stored.
    func saveAlerts() {
        let stored = NotificationPreferences.load()
        var merged = self
        merged.takeSharing(from: stored)
        merged.routePrivacyMeters = stored.routePrivacyMeters
        merged.save()
    }

    /// Adopts the values the SERVER enforces (or stores to follow the user to
    /// a new phone). Returns true when anything changed.
    ///
    /// Visibility is a privacy control: showing "Friends only" to someone the
    /// server has as "Everyone" would be a lie about who sees their photos.
    @discardableResult
    mutating func adoptServerValues(_ settings: NotificationSettingsResponse) -> Bool {
        var changed = false
        if let raw = settings.workout_visibility,
           let visibility = WorkoutVisibility(rawValue: raw),
           workoutVisibility != visibility {
            workoutVisibility = visibility
            changed = true
        }
        if let raw = settings.flyover_visibility,
           let flyover = FlyoverVisibility(rawValue: raw),
           flyoverVisibility != flyover {
            flyoverVisibility = flyover
            changed = true
        }
        if let tagged = settings.tagged_posts_on_profile, taggedPostsOnProfile != tagged {
            taggedPostsOnProfile = tagged
            changed = true
        }
        if let buddyInvites = settings.buddy_invites_enabled, buddyInvitesEnabled != buddyInvites {
            buddyInvitesEnabled = buddyInvites
            changed = true
        }
        // Nothing server-side enforces this one, but it's stored remotely so
        // a fresh install adopts it rather than silently posting route cards.
        if let autoPost = settings.auto_post_without_photo, autoPostWithoutPhoto != autoPost {
            autoPostWithoutPhoto = autoPost
            changed = true
        }
        if let autoOnProfile = settings.auto_posts_on_profile, autoPostsOnProfile != autoOnProfile {
            autoPostsOnProfile = autoOnProfile
            changed = true
        }
        return changed
    }
}
