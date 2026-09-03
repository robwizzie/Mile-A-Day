import { Router } from "express";
import { recordFeatureEventController } from "../controllers/telemetryController.js";

const router = Router();

router.post("/feature", recordFeatureEventController);

export default router;
