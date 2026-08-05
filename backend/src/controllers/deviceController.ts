import { Response } from "express";
import { AuthenticatedRequest } from "../middleware/auth.js";
import {
  registerDeviceToken,
  unregisterDeviceToken,
} from "../services/pushNotificationService.js";
import {
  CLIENT_FEATURES,
  normalizeClientFeatures,
} from "../services/clientFeatures.js";
import { enrollUser } from "../services/buddySessionService.js";
import hasRequiredKeys from "../utils/hasRequiredKeys.js";

export async function registerDevice(req: AuthenticatedRequest, res: Response) {
  if (!hasRequiredKeys(["device_token"], req, res)) return;

  try {
    await registerDeviceToken(
      req.userId!,
      req.body.device_token,
      req.body.environment,
      req.body.client_features,
    );

    // Buddy enrollment rides the registration every build already makes,
    // rather than depending on POST /buddy/enroll landing separately. That
    // call is best-effort on the client and silent on failure, so when the
    // feature flag was off its 404 left every user unenrolled — and an
    // unenrolled user is invisible in their friends' invite pickers, which
    // reads as "nobody has this feature" rather than as an error.
    //
    // Not gated on buddySessionsEnabled: the stamp is just a capability
    // record, so recording it while the kill switch is down means the switch
    // can come back up without waiting a launch cycle for everyone to
    // re-enroll. Idempotent — enrollUser keeps the first timestamp.
    if (
      normalizeClientFeatures(req.body.client_features).includes(
        CLIENT_FEATURES.buddyWalksV1,
      )
    ) {
      await enrollUser(req.userId!);
    }

    res.status(200).json({ message: "Device registered" });
  } catch (error: any) {
    console.error("Error registering device:", error.message);
    res.status(500).json({ error: "Error registering device" });
  }
}

export async function unregisterDevice(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!hasRequiredKeys(["device_token"], req, res)) return;

  try {
    await unregisterDeviceToken(req.userId!, req.body.device_token);
    res.status(200).json({ message: "Device unregistered" });
  } catch (error: any) {
    console.error("Error unregistering device:", error.message);
    res.status(500).json({ error: "Error unregistering device" });
  }
}
