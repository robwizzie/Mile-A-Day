import { Router } from "express";
import * as c from "../controllers/runPlansController.js";

// Mounted at /run-plans AFTER authenticateToken in server.ts; self-scoped on
// req.userId. Mile A Day+ only: everything below the gate answers 403
// { error: 'plus_required' } to non-members, except /status (which says so).
// Contract: /p/mad-run-plans-api.
const router = Router();

router.get("/status", c.status);
// The runner's own Claude (coach MCP): status + revoke, outside the Plus gate
// so a lapsed member can still disconnect.
router.get("/claude", c.claudeConnection);
router.delete("/claude", c.revokeClaude);

router.use(c.requirePlus);
router.get("/fitness-profile", c.getProfile);
router.put("/fitness-profile", c.putProfile);

router.post("/preview", c.preview);
router.post("/", c.create);
router.get("/current", c.current);
router.patch("/current", c.update);
router.delete("/current", c.archive);
router.get("/days", c.days);
router.get("/history", c.historyList);

router.get("/proposals", c.listProposals);
router.post("/proposals", c.submitProposal);
router.get("/proposals/:id", c.getProposal);
router.post("/proposals/:id/apply", c.apply);
router.post("/proposals/:id/apply-after-run", c.applyAfterRun);
router.post("/proposals/:id/decline", c.decline);
router.post("/proposals/:id/undo", c.undo);

router.post("/open", c.open);
router.post("/checkins", c.checkin);
router.get("/checkins", c.listCheckins);
router.post("/grades", c.grade);
router.post("/effort", c.submitEffort);
router.get("/effort", c.listEfforts);
router.get("/effort/:workoutId", c.getEffort);
router.post("/effort/:workoutId/rating", c.rateEffort);

router.patch("/coach/settings", c.patchCoachSettings);
router.post("/coach/anthropic-consent", c.anthropicConsent);
router.get("/coach/context", c.coachContext);
router.post("/coach/options", c.coachOptions);
router.post("/coach/build-day", c.coachBuildDay);
router.post("/coach/validate", c.coachValidate);
router.get("/coach/estimate", c.coachEstimate);
router.put("/coach/notes", c.coachNotes);
router.post("/coach/calls", c.coachCalls);
router.post("/coach/anthropic", c.coachAnthropic);

export default router;
