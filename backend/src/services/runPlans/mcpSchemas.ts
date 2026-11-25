/**
 * Zod shapes shared by the two MCP surfaces that propose plan changes: the
 * admin connector's overseer tools (src/mcp/runPlanTools.ts) and the
 * user-facing coach connector (src/coachMcp/tools.ts). Both send DaySpecs;
 * the engine computes every number from them.
 */
import { z } from "zod";
import type { DaySpec } from "./engine.js";

export const daySpec = z
  .object({
    kind: z.enum(["easy", "long", "tempo", "intervals", "race", "calibration", "walk"]),
    distance_mi: z.number().positive().max(60).nullish(),
    work_mi: z.number().positive().max(60).nullish(),
    reps: z.number().int().positive().max(40).nullish(),
    rep_mi: z.number().positive().max(10).nullish(),
    rep_s: z.number().int().positive().max(3600).nullish(),
    recover_s: z.number().int().nonnegative().max(1800).nullish(),
    pace_factor: z.number().min(0.85).max(1.15).nullish(),
    note: z.string().max(600).nullish(),
  })
  .describe(
    "A DaySpec: what kind of day and its shape; the server computes every pace, segment and total. " +
      "easy/long/race/calibration: distance_mi. tempo: distance_mi + work_mi. intervals: reps + (rep_mi | rep_s) + recover_s. walk: nothing. " +
      "pace_factor 0.85–1.15 scales the plan's paces (>1 = slower).",
  );

export const changesSchema = z
  .array(z.object({ local_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/), day: daySpec }))
  .min(1)
  .max(31);

/** Drop absent fields so the engine sees a DaySpec, not a bag of nulls. */
export function cleanDaySpec(d: z.infer<typeof daySpec>): DaySpec {
  return Object.fromEntries(Object.entries(d).filter(([, v]) => v !== undefined && v !== null)) as unknown as DaySpec;
}
