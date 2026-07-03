import { Request, Response } from "express";
import { createRemoteJWKSet, jwtVerify } from "jose";
import { generateAccessToken } from "../services/tokenService.js";
import { logError } from "../services/errorLogService.js";
import {
  getUserByAppleSub,
  getOverview,
  getMilesByDay,
  getErrors,
  getErrorSummary,
} from "../services/adminService.js";

const APPLE_ISS = "https://appleid.apple.com";
const appleJwks = createRemoteJWKSet(
  new URL("https://appleid.apple.com/auth/keys"),
);

/**
 * Verify a Sign in with Apple (web) id_token, confirm the resolved user is an
 * admin, and mint a normal app access token the dashboard replays to the
 * protected /admin endpoints. Public route — this is how you get a token.
 *
 * Web SIWA uses the Services ID as the token audience (distinct from the
 * native app's APPLE_CLIENT_ID), so we verify against APPLE_WEB_CLIENT_ID.
 */
export async function verifyAppleWeb(req: Request, res: Response) {
  const idToken = req.body?.id_token as string | undefined;
  if (!idToken) {
    return res.status(400).json({ error: "id_token required" });
  }

  const audience = process.env.APPLE_WEB_CLIENT_ID;
  if (!audience) {
    console.error("APPLE_WEB_CLIENT_ID not configured");
    return res.status(500).json({ error: "Admin auth not configured" });
  }

  try {
    const { payload } = await jwtVerify(idToken, appleJwks, {
      issuer: APPLE_ISS,
      audience,
    });

    const sub = payload.sub as string;
    const user = await getUserByAppleSub(sub);

    if (!user || user.role !== "admin") {
      logError("auth", "Admin sign-in denied (not an admin)", {
        userId: user?.user_id ?? null,
        context: { email: (payload.email as string) ?? user?.email ?? null },
      });
      return res.status(403).json({ error: "Not authorized" });
    }

    const accessToken = await generateAccessToken(user.user_id);
    return res.json({ accessToken });
  } catch (err) {
    logError("auth", "Admin Apple-web verify failed", {
      context: { reason: err instanceof Error ? err.message : String(err) },
    });
    return res.status(401).json({ error: "Invalid Apple identity token" });
  }
}

export async function overview(_req: Request, res: Response) {
  res.json(await getOverview());
}

export async function milesByDay(_req: Request, res: Response) {
  res.json(await getMilesByDay());
}

export async function errors(req: Request, res: Response) {
  const category =
    typeof req.query.category === "string" && req.query.category
      ? req.query.category
      : null;
  const limit = Math.min(
    Math.max(parseInt(String(req.query.limit ?? "100"), 10) || 100, 1),
    500,
  );
  res.json(await getErrors(category, limit));
}

export async function errorSummary(_req: Request, res: Response) {
  res.json(await getErrorSummary());
}
