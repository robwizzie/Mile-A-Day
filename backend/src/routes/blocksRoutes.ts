import { Router } from "express";
import {
  blockUserController,
  listBlockedUsersController,
  unblockUserController,
} from "../controllers/blocksController.js";

const router = Router();

router.get("/", listBlockedUsersController);
router.post("/:userId", blockUserController);
router.delete("/:userId", unblockUserController);

export default router;
