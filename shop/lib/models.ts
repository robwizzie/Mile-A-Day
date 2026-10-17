// The 3D garment models the rack renders, and where each came from. All are
// CC BY 4.0 (commercial use allowed with credit): MODEL_CREDITS is shown in
// the footer, and must stay there while a model is used.
//
// public/models/<id>.glb is made from the Sketchfab download by
// `npm run models` (scripts/prep-models.ts); measurements are in
// lib/model-bounds.ts.

import { MODEL_BOUNDS, type ModelBounds } from "./model-bounds";

export type ModelId = "tee" | "longsleeve" | "tank" | "hoodie";

export const MODEL_CREDITS: Record<ModelId, { title: string; author: string; url: string }> = {
  tee: { title: "Standard T-shirt", author: "Pieter Ferreira (Badboy17Aiden)", url: "https://sketchfab.com/3d-models/1815c01895bd4538bc0bd05c3394698d" },
  longsleeve: { title: "T-shirt - Lengan Panjang", author: "Ikal.Ichwan", url: "https://sketchfab.com/3d-models/86d4292baa6c489ab5fab374bf803106" },
  tank: { title: "Tank Top", author: "Shift4cube", url: "https://sketchfab.com/3d-models/d6b2561de39f423f9c7a2e7944485beb" },
  hoodie: { title: "HOODIE", author: "Obridje", url: "https://sketchfab.com/3d-models/ab78848ab3404a2e877929d5f8774c54" },
};

export const LICENSE = { name: "CC BY 4.0", url: "https://creativecommons.org/licenses/by/4.0/" };

export function modelUrl(id: ModelId) {
  return `/models/${id}.glb`;
}

export function bounds(id: ModelId): ModelBounds {
  return MODEL_BOUNDS[id];
}

/** How far the hanger's hook rises above the top of the garment, in metres. */
export const HOOK_RISE = 0.075;

/**
 * Where the hanger's neck runs, front to back (z, metres). A hoodie's rides
 * up the back of the hood, as on a real hanger, not through its face
 * opening. The hook is the pivot: the garment is shifted so it sits at z = 0.
 */
export const HOOK_Z: Partial<Record<ModelId, number>> = { hoodie: -0.1 };
