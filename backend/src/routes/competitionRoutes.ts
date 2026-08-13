import { Router } from "express";
import {
  createComp,
  startComp,
  getComp,
  getAllComps,
  inviteUsersToComp,
  removeUserFromComp,
  getCompInvites,
  getCompInviteHandler,
  getCompRecord,
  updateComp,
  deleteComp,
  setCompTeams,
  pickCompTeam,
  getCompTeamStats,
} from "../controllers/competitionController.js";
import { nudgeUser } from "../controllers/nudgeController.js";
import { flexOnUser, getFlexPresets } from "../controllers/flexController.js";

const router = Router();

router.post("/", createComp);
router.get("/", getAllComps);
// Literal paths MUST stay above "/:competitionId" — otherwise Express matches
// them as a competition id and the route 404s on a lookup for "record".
router.get("/invites", getCompInvites);
router.get("/flex/presets", getFlexPresets);
router.get("/record", getCompRecord);
router.get("/:competitionId", getComp);
router.patch("/:competitionId", updateComp);
router.delete("/:competitionId", deleteComp);
router.post("/:competitionId/start", startComp);
router.post("/:competitionId/invite", inviteUsersToComp);
router.put("/:competitionId/teams", setCompTeams);
router.post("/:competitionId/teams/pick", pickCompTeam);
router.get("/:competitionId/teams/stats", getCompTeamStats);
router.delete("/:competitionId/users/:userId", removeUserFromComp);
router.post("/:competitionId/accept", getCompInviteHandler("accepted"));
router.post("/:competitionId/decline", getCompInviteHandler("declined"));
router.post("/:competitionId/nudge", nudgeUser);
router.post("/:competitionId/flex", flexOnUser);

export default router;
