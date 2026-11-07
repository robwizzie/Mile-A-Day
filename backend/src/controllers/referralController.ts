import { Response } from "express";
import { AuthenticatedRequest } from "../middleware/auth.js";
import { claimFreeYear, getReferralStatus, ReferralError, setReferrer } from "../services/referralService.js";

function fail(res: Response, error: any, label: string) {
  if (error instanceof ReferralError) {
    return res.status(error.status).json({ error: error.message, code: error.code });
  }
  console.error(`Error ${label}:`, error.message);
  return res.status(500).json({ error: "Something went wrong" });
}

export async function getReferrals(req: AuthenticatedRequest, res: Response) {
  try {
    return res.status(200).json(await getReferralStatus(req.params.userId));
  } catch (error: any) {
    return fail(res, error, "getting referrals");
  }
}

export async function postReferrer(req: AuthenticatedRequest, res: Response) {
  const username = typeof req.body?.username === "string" ? req.body.username : "";
  if (!username.trim()) return res.status(400).json({ error: "Choose an account", code: "missing" });
  try {
    await setReferrer(req.params.userId, username);
    return res.status(200).json(await getReferralStatus(req.params.userId));
  } catch (error: any) {
    return fail(res, error, "setting referrer");
  }
}

export async function postClaimFreeYear(req: AuthenticatedRequest, res: Response) {
  try {
    return res.status(200).json({ code: await claimFreeYear(req.params.userId) });
  } catch (error: any) {
    return fail(res, error, "claiming reward");
  }
}
