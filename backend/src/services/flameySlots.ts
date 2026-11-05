/**
 * Flamey's slots and unlock kinds — a dependency-free leaf so both the
 * catalog (flameyCatalog.ts) and the skin loader (flameySkins.ts) can use
 * them without an import cycle. flameyCatalog.ts re-exports everything here;
 * import from there.
 */

export const FLAMEY_SLOTS = [
  "color",
  "head",
  "eyes",
  "chest",
  "back",
  "feet",
  "costume",
  "held",
  "trail",
  "companion",
  "aura",
  "bubble",
] as const;

export type FlameySlot = (typeof FLAMEY_SLOTS)[number];

export type FlameyUnlock =
  | { kind: "always" }
  | { kind: "badge"; id: string }
  | { kind: "plus" }
  | { kind: "month"; month: number }
  | { kind: "purchase"; productId: string };

export function isFlameySlot(s: unknown): s is FlameySlot {
  return (
    typeof s === "string" && (FLAMEY_SLOTS as readonly string[]).includes(s)
  );
}
