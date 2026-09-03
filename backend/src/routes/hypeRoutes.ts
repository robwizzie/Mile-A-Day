import { Router } from "express";
import {
  sendHype,
  removeHype,
  getHypeStatus,
  getReceivedHypesController,
  getContextHypersController,
} from "../controllers/hypeController.js";

const router = Router();

router.post("/", sendHype);
router.delete("/", removeHype);
router.get("/status", getHypeStatus);
router.get("/received", getReceivedHypesController);
router.get("/hypers", getContextHypersController);

export default router;
