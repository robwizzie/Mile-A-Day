import { Request, Response } from "express";
import fs from "fs";
import path from "path";
import sharp from "sharp";
import {
  countShoes,
  createShoe,
  deleteShoe,
  getShoe,
  getWorkoutShoe,
  listShoes,
  listShoeWorkouts,
  MAX_SHOES_PER_USER,
  setShoeImage,
  setWorkoutShoe,
  shoeExists,
  ShoeInput,
  updateShoe,
} from "../services/shoeService.js";

// Every route here is `requireSelfAccess('userId')`: shoes are the owner's
// alone, so there is no viewer to authorise beyond "is it you".

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_MILES = 10000;

export const SHOE_IMAGE_DIR = path.join(process.cwd(), "uploads", "shoes");

/** Best-effort removal of a shoe image we wrote; never throws. */
function unlinkShoeImageQuietly(relativePath: unknown) {
  if (
    typeof relativePath !== "string" ||
    !relativePath.startsWith("/uploads/shoes/")
  )
    return;
  try {
    const full = path.join(process.cwd(), relativePath);
    if (fs.existsSync(full)) fs.unlinkSync(full);
  } catch (error) {
    console.warn("[shoes] could not remove image", relativePath, error);
  }
}

class InvalidInput extends Error {}

function optionalText(
  value: unknown,
  field: string,
  max: number,
): string | null | undefined {
  if (value === undefined) return undefined;
  if (value === null) return null;
  if (typeof value !== "string")
    throw new InvalidInput(`${field} must be a string`);
  const trimmed = value.replace(/\s+/g, " ").trim();
  if (trimmed.length > max) throw new InvalidInput(`${field} is too long`);
  return trimmed === "" ? null : trimmed;
}

function optionalMiles(
  value: unknown,
  field: string,
  min: number,
): number | null | undefined {
  if (value === undefined) return undefined;
  if (value === null) return null;
  if (
    typeof value !== "number" ||
    !Number.isFinite(value) ||
    value < min ||
    value > MAX_MILES
  ) {
    throw new InvalidInput(`${field} must be between ${min} and ${MAX_MILES}`);
  }
  return value;
}

function optionalBool(value: unknown, field: string): boolean | undefined {
  if (value === undefined) return undefined;
  if (typeof value !== "boolean")
    throw new InvalidInput(`${field} must be a boolean`);
  return value;
}

/** Parses the writable fields of a shoe body; `undefined` = leave alone. */
function parseShoeBody(body: any): ShoeInput {
  const b = body ?? {};
  const input: ShoeInput = {};

  const name = optionalText(b.name, "name", 120);
  if (name === null) throw new InvalidInput("name cannot be empty");
  if (name !== undefined) input.name = name;

  const brand = optionalText(b.brand, "brand", 60);
  if (brand !== undefined) input.brand = brand;
  const colorway = optionalText(b.colorway, "colorway", 120);
  if (colorway !== undefined) input.colorway = colorway;

  const starting = optionalMiles(b.starting_miles, "starting_miles", 0);
  if (starting !== undefined) input.starting_miles = starting ?? 0;
  const replaceAt = optionalMiles(b.replace_at_miles, "replace_at_miles", 1);
  if (replaceAt !== undefined) input.replace_at_miles = replaceAt;

  const isDefault = optionalBool(b.is_default, "is_default");
  if (isDefault !== undefined) input.is_default = isDefault;
  const retired = optionalBool(b.retired, "retired");
  if (retired !== undefined) input.retired = retired;

  return input;
}

function handle(res: Response, label: string, err: unknown) {
  if (err instanceof InvalidInput) {
    return res.status(400).json({ error: err.message });
  }
  console.error(`[shoes] ${label}:`, err instanceof Error ? err.message : err);
  return res.status(500).json({ error: `Error ${label}` });
}

export async function getShoesController(req: Request, res: Response) {
  try {
    const shoes = await listShoes(req.params.userId as string);
    return res.status(200).json({ shoes });
  } catch (err) {
    return handle(res, "listing shoes", err);
  }
}

export async function createShoeController(req: Request, res: Response) {
  const userId = req.params.userId as string;
  try {
    const input = parseShoeBody(req.body);
    if (!input.name) throw new InvalidInput("name is required");
    if ((await countShoes(userId)) >= MAX_SHOES_PER_USER) {
      return res
        .status(409)
        .json({ error: `You can track up to ${MAX_SHOES_PER_USER} shoes` });
    }
    const shoe = await createShoe(userId, { ...input, name: input.name });
    return res.status(201).json(shoe);
  } catch (err) {
    return handle(res, "creating shoe", err);
  }
}

export async function updateShoeController(req: Request, res: Response) {
  const { userId, shoeId } = req.params as { userId: string; shoeId: string };
  if (!UUID_RE.test(shoeId))
    return res.status(404).json({ error: "Shoe not found" });
  try {
    const shoe = await updateShoe(userId, shoeId, parseShoeBody(req.body));
    if (!shoe) return res.status(404).json({ error: "Shoe not found" });
    return res.status(200).json(shoe);
  } catch (err) {
    return handle(res, "updating shoe", err);
  }
}

export async function deleteShoeController(req: Request, res: Response) {
  const { userId, shoeId } = req.params as { userId: string; shoeId: string };
  if (!UUID_RE.test(shoeId))
    return res.status(404).json({ error: "Shoe not found" });
  try {
    const { deleted, imageUrl } = await deleteShoe(userId, shoeId);
    if (!deleted) return res.status(404).json({ error: "Shoe not found" });
    unlinkShoeImageQuietly(imageUrl);
    return res.status(200).json({ success: true });
  } catch (err) {
    return handle(res, "deleting shoe", err);
  }
}

/**
 * The pair's photo, from the owner's camera roll. Normalised to a JPEG,
 * flattened onto white so a transparent PNG can't draw black on a dark card.
 */
export async function uploadShoeImageController(req: Request, res: Response) {
  const { userId, shoeId } = req.params as { userId: string; shoeId: string };
  if (!UUID_RE.test(shoeId))
    return res.status(404).json({ error: "Shoe not found" });
  if (!req.file)
    return res.status(400).json({ error: "No image file provided" });
  try {
    if (!(await shoeExists(userId, shoeId))) {
      return res.status(404).json({ error: "Shoe not found" });
    }
    const filename = `${userId}-${shoeId}-${Date.now()}.jpg`;
    await sharp(req.file.buffer)
      .rotate()
      .resize(900, 900, { fit: "inside", withoutEnlargement: true })
      .flatten({ background: "#ffffff" })
      .jpeg({ quality: 85 })
      .toFile(path.join(SHOE_IMAGE_DIR, filename));

    const imageUrl = `/uploads/shoes/${filename}`;
    const { found, previous } = await setShoeImage(userId, shoeId, imageUrl);
    if (!found) {
      unlinkShoeImageQuietly(imageUrl);
      return res.status(404).json({ error: "Shoe not found" });
    }
    unlinkShoeImageQuietly(previous);
    return res.status(200).json(await getShoe(userId, shoeId));
  } catch (err) {
    return handle(res, "uploading shoe image", err);
  }
}

export async function getShoeWorkoutsController(req: Request, res: Response) {
  const { userId, shoeId } = req.params as { userId: string; shoeId: string };
  if (!UUID_RE.test(shoeId))
    return res.status(404).json({ error: "Shoe not found" });
  try {
    if (!(await shoeExists(userId, shoeId))) {
      return res.status(404).json({ error: "Shoe not found" });
    }
    const workouts = await listShoeWorkouts(userId, shoeId);
    return res.status(200).json({ workouts });
  } catch (err) {
    return handle(res, "listing shoe workouts", err);
  }
}

function validWorkoutId(id: unknown): id is string {
  return typeof id === "string" && id.length > 0 && id.length <= 255;
}

export async function getWorkoutShoeController(req: Request, res: Response) {
  const { userId, workoutId } = req.params as {
    userId: string;
    workoutId: string;
  };
  if (!validWorkoutId(workoutId))
    return res.status(400).json({ error: "Invalid workout id" });
  try {
    return res.status(200).json(await getWorkoutShoe(userId, workoutId));
  } catch (err) {
    return handle(res, "reading workout shoe", err);
  }
}

/** `{ shoe_id: "<uuid>" }` picks a pair; `{ shoe_id: null }` records "no shoe". */
export async function putWorkoutShoeController(req: Request, res: Response) {
  const { userId, workoutId } = req.params as {
    userId: string;
    workoutId: string;
  };
  if (!validWorkoutId(workoutId))
    return res.status(400).json({ error: "Invalid workout id" });
  const shoeId = req.body?.shoe_id;
  if (
    shoeId !== null &&
    (typeof shoeId !== "string" || !UUID_RE.test(shoeId))
  ) {
    return res.status(400).json({ error: "shoe_id must be a shoe id or null" });
  }
  try {
    if (shoeId !== null && !(await shoeExists(userId, shoeId))) {
      return res.status(404).json({ error: "Shoe not found" });
    }
    await setWorkoutShoe(userId, workoutId, shoeId);
    return res.status(200).json(await getWorkoutShoe(userId, workoutId));
  } catch (err) {
    return handle(res, "setting workout shoe", err);
  }
}
