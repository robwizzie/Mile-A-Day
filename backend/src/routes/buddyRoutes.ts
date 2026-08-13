import { Router } from "express";
import {
  cancelSessionController,
  createSessionController,
  declineSessionController,
  deleteHistoryEntryController,
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
  createRoutineController,
  deleteRoutineController,
  historyController,
  listRoutinesController,
  partnersController,
  updateParticipantController,
  updateRoutineController,
  updateSessionController,
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
// Host-only: call the walk off entirely, while it's still a lobby or still in
// the shared countdown. The exit that didn't exist — Leave abandoned a room
// that then sat open for hours, still invited, still due to auto-start.
router.post("/sessions/:sessionId/cancel", cancelSessionController);
// Host-only, lobby-only: change mode/goal/activity/schedule or add invitees
// after the room exists, so a change of plan doesn't mean a new join code.
router.patch("/sessions/:sessionId", updateSessionController);
// PARTICIPANT-scoped, any phase: indoor vs outdoor is one person's answer
// about where they are, not the host's about what the group is doing — so no
// `not_host` and no lobby-only guard, unlike the PATCH above it.
router.patch("/sessions/:sessionId/me", updateParticipantController);
router.post("/sessions/:sessionId/progress", progressController);
router.post("/sessions/:sessionId/finish", finishController);

// Standing walks ("us, 6pm, weekdays"). A TEMPLATE, not a session: the cron
// spawns a real scheduled session from each one shortly before it's due, so
// everything downstream is the existing lobby machinery. Self-scoped on the
// token; ownership is re-checked in the service.
// Miles walked together, per friend. The number that makes a shared habit
// feel like a thing you have rather than one you keep re-arranging.
router.get("/partners", partnersController);
// The walks themselves — the archive behind the history screen. Keyset
// paginated; `?friendId=` narrows it to walks you finished with one person.
router.get("/history", historyController);
// Take one finished walk out of YOUR archive (a mis-tapped join, a routine
// that fired on a day nobody went out). A per-viewer hide, never a delete —
// the walk belongs to everybody who was on it. `?hidden=false` undoes it.
router.delete("/history/:sessionId", deleteHistoryEntryController);
router.get("/recurring", listRoutinesController);
router.post("/recurring", createRoutineController);
router.patch("/recurring/:routineId", updateRoutineController);
router.delete("/recurring/:routineId", deleteRoutineController);

export default router;
