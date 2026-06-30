import { Router } from "express";
import {
  blockUserController,
  unblockUserController,
} from "../controllers/blocksController.js";

const router = Router();

router.post("/:userId", blockUserController);
router.delete("/:userId", unblockUserController);

export default router;
