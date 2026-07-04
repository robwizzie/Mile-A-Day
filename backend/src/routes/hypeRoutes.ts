import { Router } from "express";
import {
  sendHype,
  getHypeStatus,
  getReceivedHypesController,
  getContextHypersController,
} from "../controllers/hypeController.js";

const router = Router();

router.post("/", sendHype);
router.get("/status", getHypeStatus);
router.get("/received", getReceivedHypesController);
router.get("/hypers", getContextHypersController);

export default router;
