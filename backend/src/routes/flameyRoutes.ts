import { Router } from "express";
import { getFlameySkins } from "../controllers/flameyController.js";

const router = Router();

// Downloadable Flamey skins (docs/flamey-skins.md).
router.get("/skins", getFlameySkins);

export default router;
