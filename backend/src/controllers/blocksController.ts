import { Response } from "express";
import { AuthenticatedRequest } from "../middleware/auth.js";
import { blockUser, unblockUser } from "../services/moderationService.js";

export async function blockUserController(
  req: AuthenticatedRequest,
  res: Response,
) {
  const blockerId = req.userId!;
  const blockedId = req.params.userId;
  try {
    if (blockerId === blockedId) {
      return res.status(400).json({ error: "You can't block yourself" });
    }
    await blockUser(blockerId, blockedId);
    res.json({ ok: true });
  } catch (error: any) {
    console.error("Error blocking user:", error.message);
    res.status(500).json({ error: "Error blocking user" });
  }
}

export async function unblockUserController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    await unblockUser(req.userId!, req.params.userId);
    res.json({ ok: true });
  } catch (error: any) {
    console.error("Error unblocking user:", error.message);
    res.status(500).json({ error: "Error unblocking user" });
  }
}
