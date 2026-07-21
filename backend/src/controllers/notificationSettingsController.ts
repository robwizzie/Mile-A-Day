import { Response } from "express";
import { AuthenticatedRequest } from "../middleware/auth.js";
import {
  getNotificationPreferences,
  updateNotificationPreferences,
  getFriendNotificationSettings,
  updateFriendNotificationSettings,
} from "../services/notificationSettingsService.js";
import { getCloseFriendIds } from "../services/closeFriendsService.js";
import {
  isWorkoutVisibility,
  WORKOUT_VISIBILITY_VALUES,
} from "../services/visibilityService.js";

export async function getPreferences(req: AuthenticatedRequest, res: Response) {
  try {
    const prefs = await getNotificationPreferences(req.userId!);
    res.status(200).json(prefs);
  } catch (error: any) {
    console.error("Error getting notification preferences:", error.message);
    res.status(500).json({ error: "Error getting notification preferences" });
  }
}

export async function updatePreferences(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    const {
      quiet_hours_start,
      quiet_hours_end,
      daily_reminder_hour,
      timezone_offset_minutes,
      workout_visibility,
    } = req.body;
    // The DB has a CHECK for this too; validating here turns a would-be 500
    // into a clear 400.
    if (
      workout_visibility !== undefined &&
      !isWorkoutVisibility(workout_visibility)
    ) {
      return res.status(400).json({
        error: `workout_visibility must be one of: ${WORKOUT_VISIBILITY_VALUES.join(", ")}`,
      });
    }
    if (
      quiet_hours_start !== undefined &&
      quiet_hours_start !== null &&
      (quiet_hours_start < 0 || quiet_hours_start > 23)
    ) {
      return res
        .status(400)
        .json({ error: "quiet_hours_start must be 0-23 or null" });
    }
    if (
      quiet_hours_end !== undefined &&
      quiet_hours_end !== null &&
      (quiet_hours_end < 0 || quiet_hours_end > 23)
    ) {
      return res
        .status(400)
        .json({ error: "quiet_hours_end must be 0-23 or null" });
    }
    if (
      daily_reminder_hour !== undefined &&
      daily_reminder_hour !== null &&
      (daily_reminder_hour < 0 || daily_reminder_hour > 23)
    ) {
      return res
        .status(400)
        .json({ error: "daily_reminder_hour must be 0-23" });
    }
    // UTC offsets range roughly from -12:00 (-720) to +14:00 (+840) minutes.
    if (
      timezone_offset_minutes !== undefined &&
      timezone_offset_minutes !== null &&
      (timezone_offset_minutes < -720 || timezone_offset_minutes > 840)
    ) {
      return res.status(400).json({
        error: "timezone_offset_minutes must be between -720 and 840",
      });
    }
    // Restricting Head-to-Head to close friends is only enableable when the
    // user actually HAS close friends — otherwise their rival pool would be
    // empty and the challenge would silently vanish from their rotation.
    // Disabling is always allowed.
    if (req.body.h2h_close_friends_only === true) {
      const closeIds = await getCloseFriendIds(req.userId!);
      if (closeIds.length === 0) {
        return res.status(400).json({
          error: "Add at least one close friend before turning this on",
          code: "no_close_friends",
        });
      }
    }

    const updated = await updateNotificationPreferences(req.userId!, req.body);
    res.status(200).json(updated);
  } catch (error: any) {
    console.error("Error updating notification preferences:", error.message);
    res.status(500).json({ error: "Error updating notification preferences" });
  }
}

export async function getFriendSettings(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    const settings = await getFriendNotificationSettings(req.userId!);
    res.status(200).json({ settings });
  } catch (error: any) {
    console.error("Error getting friend notification settings:", error.message);
    res
      .status(500)
      .json({ error: "Error getting friend notification settings" });
  }
}

export async function updateFriendSettings(
  req: AuthenticatedRequest,
  res: Response,
) {
  const friendId = req.params.friendId;
  const { muted, nudges_muted, activity_muted } = req.body;

  try {
    const updated = await updateFriendNotificationSettings(
      req.userId!,
      friendId,
      {
        muted,
        nudges_muted,
        activity_muted,
      },
    );
    res.status(200).json(updated);
  } catch (error: any) {
    console.error(
      "Error updating friend notification settings:",
      error.message,
    );
    res
      .status(500)
      .json({ error: "Error updating friend notification settings" });
  }
}
