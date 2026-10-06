import { Router } from "express";
import multer from "multer";
import {
  clearAutoAssignedController,
  createShoeController,
  deleteShoeController,
  getShoesController,
  getShoeWorkoutsController,
  getWorkoutShoeController,
  putShoeDefaultController,
  putWorkoutShoeController,
  updateShoeController,
  uploadShoeImageController,
} from "../controllers/shoesController.js";
import { requireSelfAccess } from "../middleware/auth.js";

// Shoes are private gear: every route is self-only, and none of this data is
// served on any feed, profile or friend surface.

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 8 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (["image/jpeg", "image/png", "image/webp"].includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error("Only JPEG, PNG, and WebP images are allowed"));
    }
  },
});

const router = Router();
const self = requireSelfAccess("userId");

router.get("/:userId/shoes", self, getShoesController);
router.post("/:userId/shoes", self, createShoeController);
router.patch("/:userId/shoes/:shoeId", self, updateShoeController);
router.delete("/:userId/shoes/:shoeId", self, deleteShoeController);
router.post(
  "/:userId/shoes/:shoeId/image",
  self,
  upload.single("image"),
  uploadShoeImageController,
);
router.get("/:userId/shoes/:shoeId/workouts", self, getShoeWorkoutsController);
router.post(
  "/:userId/shoes/:shoeId/clear-auto",
  self,
  clearAutoAssignedController,
);
router.put("/:userId/shoe-defaults/:activity", self, putShoeDefaultController);
router.get("/:userId/workout-shoes/:workoutId", self, getWorkoutShoeController);
router.put("/:userId/workout-shoes/:workoutId", self, putWorkoutShoeController);

export default router;
