import { Router } from "express";
import {
  createSessionController,
  declineSessionController,
  enrollController,
  finishController,
  inviteCandidatesController,
  joinableFriendSessionsController,
  joinByCodeController,
  joinSessionController,
  leaveSessionController,
  mySessionsController,
  progressController,
  readyController,
  recapController,
  sessionStateController,
  startSessionController,
} from "../controllers/buddyController.js";

const router = Router();

// Every route here is authenticated (mounted after authenticateToken in
// server.ts) and authorizes off req.userId. There is no :userId path param, so
// requireSelfAccess has nothing to check — membership is verified inside the
// service against buddy_session_participants instead.

router.post("/enroll", enrollController);
router.get("/candidates", inviteCandidatesController);
// Friends walking RIGHT NOW that the caller could join. The deliberate,
// permission-free substitute for ambient proximity sensing (see the service).
router.get("/joinable", joinableFriendSessionsController);

// Static segments MUST precede "/sessions/:sessionId/..." or "mine" and "join"
// get captured as session ids — the same ordering trap the /friends/close
// routes document.
router.get("/sessions/mine", mySessionsController);
router.post("/sessions/join", joinByCodeController);

router.post("/sessions", createSessionController);
router.get("/sessions/:sessionId/state", sessionStateController);
router.get("/sessions/:sessionId/recap", recapController);
router.post("/sessions/:sessionId/join", joinSessionController);
router.post("/sessions/:sessionId/decline", declineSessionController);
router.post("/sessions/:sessionId/leave", leaveSessionController);
router.post("/sessions/:sessionId/ready", readyController);
router.post("/sessions/:sessionId/start", startSessionController);
router.post("/sessions/:sessionId/progress", progressController);
router.post("/sessions/:sessionId/finish", finishController);

export default router;
