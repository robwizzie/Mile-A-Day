/**
 * Flamey's Closet — the canonical cosmetics catalog.
 *
 * Every item sits in exactly ONE slot and is unlocked by exactly one thing:
 * a MEDAL (a `badges.badge_id` the user holds in `user_badges`), `always`
 * (everyone owns it), `plus` (owned while the user is Mile A Day+ — see
 * plusService; a lapse makes it read as "auto" again, never rewriting the
 * stored look) or `month` (a Monthly Flame, owned once that calendar month
 * has been PERFECT in any year — see monthlyFlames.ts). `purchase` is reserved for a future one-off StoreKit item and
 * is owned by nobody. Item ids are stored in `users.flamey_look` and
 * mirrored by the iOS catalog — never rename one; retire it instead (an
 * unknown id is dropped at read, which reads as "auto" for that slot).
 *
 * `scripts/flamey-closet-check.mjs` asserts every badge id here exists in the
 * seeded catalog (badges-seed.sql + seedExtraBadges + holidays).
 */

export const FLAMEY_CATALOG_VERSION = "1";

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

export interface FlameyItem {
  id: string;
  slot: FlameySlot;
  unlock: FlameyUnlock;
}

// [itemId, slot, unlocking badge id | "always" | "plus" | "month:<1-12>"]
const ROWS: ReadonlyArray<readonly [string, FlameySlot, string]> = [
  // color
  ["classic", "color", "always"],
  ["ember", "color", "consistency_3"],
  ["lime", "color", "consistency_5"],
  ["ruby", "color", "streak_7"],
  ["lavender", "color", "streak_10"],
  ["sunflower", "color", "streak_14"],
  ["mint", "color", "streak_21"],
  ["sapphire", "color", "streak_30"],
  ["violet", "color", "streak_45"],
  ["rose", "color", "streak_50"],
  ["teal", "color", "streak_60"],
  ["arctic", "color", "streak_75"],
  ["midnight", "color", "streak_90"],
  ["sunset", "color", "streak_100"],
  ["aurora", "color", "streak_120"],
  ["ocean", "color", "streak_150"],
  ["lava_lamp", "color", "streak_180"],
  ["galaxy", "color", "streak_200"],
  ["candy", "color", "streak_250"],
  ["northern_lights", "color", "streak_300"],
  ["gold", "color", "streak_365"],
  ["prism", "color", "streak_500"],
  ["cosmic", "color", "streak_730"],
  ["eternal", "color", "streak_1000"],
  ["phantom", "color", "ghost_beat_50"],
  // Mile A Day+ colors
  ["electric", "color", "plus"],
  ["rose_gold", "color", "plus"],
  ["obsidian", "color", "plus"],
  ["tropic", "color", "plus"],
  // Monthly Flames — a perfect month (monthlyFlames.ts, same ids)
  ["frostbite", "color", "month:1"],
  ["sweetheart", "color", "month:2"],
  ["lucky_clover", "color", "month:3"],
  ["april_showers", "color", "month:4"],
  ["wildflower", "color", "month:5"],
  ["sunburst", "color", "month:6"],
  ["firecracker", "color", "month:7"],
  ["watermelon", "color", "month:8"],
  ["falling_leaves", "color", "month:9"],
  ["jack_o_lantern", "color", "month:10"],
  ["sweater_weather", "color", "month:11"],
  ["twinkle_lights", "color", "month:12"],
  // head
  ["sweatband", "head", "special_first_mile"],
  ["ball_cap", "head", "miles_25"],
  ["visor", "head", "miles_50"],
  ["beanie", "head", "miles_100"],
  ["bucket_hat", "head", "miles_150"],
  ["safari_hat", "head", "miles_200"],
  ["cowboy_hat", "head", "miles_250"],
  ["aviator_cap", "head", "miles_500"],
  ["headlamp_helmet", "head", "miles_750"],
  ["crown", "head", "miles_1000"],
  ["laurel_wreath", "head", "miles_1500"],
  ["viking_helmet", "head", "miles_2000"],
  ["directors_beret", "head", "story_5"],
  ["santa_hat", "head", "holiday_christmas"],
  ["heart_bopper", "head", "holiday_valentines_day"],
  ["leprechaun_hat", "head", "holiday_st_patricks_day"],
  ["bunny_ears", "head", "holiday_easter"],
  ["star_hat", "head", "holiday_independence_day"],
  ["countdown_hat", "head", "holiday_new_years_eve"],
  // eyes
  ["star_stickers", "eyes", "challenge_1"],
  ["round_specs", "eyes", "challenge_5"],
  ["classic_shades", "eyes", "challenge_10"],
  ["aviators", "eyes", "challenge_25"],
  ["heart_glasses", "eyes", "challenge_50"],
  ["cyber_visor", "eyes", "challenge_100"],
  ["star_glasses", "eyes", "holiday_new_years_day"],
  // chest
  ["bandana", "chest", "special_first_week"],
  ["bow_tie", "chest", "weekly_1"],
  ["finisher_medal", "chest", "weekly_5"],
  ["star_badge", "chest", "weekly_10"],
  ["champion_sash", "chest", "weekly_25"],
  ["gold_chain", "chest", "weekly_streak_4"],
  ["trophy_pendant", "chest", "weekly_streak_12"],
  ["polaroid", "chest", "story_1"],
  ["holiday_scarf", "chest", "holiday_christmas_eve"],
  // back
  ["red_cape", "back", "comp_entered_1"],
  ["blue_cape", "back", "comp_entered_10"],
  ["royal_cape", "back", "comp_entered_50"],
  ["champion_cape", "back", "comp_won_1"],
  ["victory_banner", "back", "comp_won_5"],
  ["golden_wings", "back", "comp_won_25"],
  ["turkey_feathers", "back", "holiday_thanksgiving"],
  // feet
  ["canvas_sneakers", "feet", "pace_12min"],
  ["trainers", "feet", "pace_11min"],
  ["racing_flats", "feet", "pace_10min"],
  ["neon_soles", "feet", "pace_9min"],
  ["track_spikes", "feet", "pace_8min"],
  ["rocket_boots", "feet", "pace_7min"],
  ["lightning_kicks", "feet", "pace_6min"],
  ["winged_sandals", "feet", "pace_5min"],
  // costume
  ["ghost_sheet", "costume", "ghost_beat_10"],
  ["astronaut_helmet", "costume", "miles_2500"],
  ["pumpkin_suit", "costume", "holiday_halloween"],
  // held
  ["checkered_flag", "held", "comp_started_1"],
  ["stopwatch", "held", "comp_started_10"],
  ["pom_poms", "held", "hype_1"],
  ["foam_finger", "held", "hype_25"],
  ["megaphone", "held", "hype_100"],
  ["confetti_cannon", "held", "hype_500"],
  // trail
  ["ember_sparks", "trail", "daily_2"],
  ["dust_puffs", "trail", "daily_3"],
  ["speed_lines", "trail", "daily_5"],
  ["comet_tail", "trail", "daily_10k"],
  ["smoke_rings", "trail", "daily_8"],
  ["star_trail", "trail", "daily_10"],
  ["rainbow_streak", "trail", "daily_half"],
  ["lightning_trail", "trail", "daily_15"],
  ["fireworks", "trail", "daily_20"],
  ["phoenix_feathers", "trail", "daily_marathon"],
  ["aurora_ribbon", "trail", "daily_50k"],
  ["meteor_shower", "trail", "daily_ultra"],
  // companion
  ["spark", "companion", "buddy_done_1"],
  ["firefly", "companion", "buddy_done_10"],
  ["flamey_jr", "companion", "buddy_done_50"],
  ["spark_trio", "companion", "buddy_crew_3"],
  ["lantern", "companion", "buddy_crew_10"],
  ["phoenix_chick", "companion", "buddy_won_1"],
  ["comet_pup", "companion", "buddy_won_10"],
  ["friendly_ghost", "companion", "ghost_beat_1"],
  // aura
  ["spectral_glow", "aura", "ghost_margin_15"],
  ["flicker", "aura", "ghost_margin_45"],
  ["spotlight", "aura", "story_25"],
  ["paparazzi", "aura", "story_100"],
  // bubble
  ["classic_bubble", "bubble", "always"],
  ["comic", "bubble", "nudge_1"],
  ["neon", "bubble", "nudge_25"],
  ["pixel", "bubble", "nudge_100"],
  ["gold_bubble", "bubble", "nudge_500"],
];

function buildCatalog(): ReadonlyMap<string, FlameyItem> {
  const map = new Map<string, FlameyItem>();
  for (const [id, slot, unlock] of ROWS) {
    if (map.has(id)) throw new Error(`flameyCatalog: duplicate item id ${id}`);
    map.set(id, {
      id,
      slot,
      unlock:
        unlock === "always"
          ? { kind: "always" }
          : unlock === "plus"
            ? { kind: "plus" }
            : unlock.startsWith("month:")
              ? { kind: "month", month: Number(unlock.slice("month:".length)) }
              : { kind: "badge", id: unlock },
    });
  }
  return map;
}

/** item id → item, in catalog order. */
export const FLAMEY_CATALOG: ReadonlyMap<string, FlameyItem> = buildCatalog();

export function isFlameySlot(s: unknown): s is FlameySlot {
  return (
    typeof s === "string" && (FLAMEY_SLOTS as readonly string[]).includes(s)
  );
}

/** Every badge id the catalog depends on (for the existence check). */
export function flameyBadgeIds(): string[] {
  const ids = new Set<string>();
  for (const item of FLAMEY_CATALOG.values()) {
    if (item.unlock.kind === "badge") ids.add(item.unlock.id);
  }
  return [...ids];
}

/**
 * Users who own every catalog item regardless of medals (the team, for
 * testing and showing off the closet). Only ownership changes: their medals,
 * streaks and badge rows are untouched.
 */
const FLAMEY_ALL_ACCESS_USER_IDS: ReadonlySet<string> = new Set([
  "be5dd0ffcd874f39ae8824d462d32300", // dave
]);

/**
 * Items owned given the user's earned badge ids, Plus state and perfect
 * months (1–12), in catalog order. `purchase` items are never owned yet.
 */
export function ownedFlameyItemIds(
  earnedBadgeIds: Iterable<string>,
  userId?: string,
  plus = false,
  perfectMonths: ReadonlySet<number> | ReadonlyMap<number, unknown> = new Set<number>(),
): Set<string> {
  if (userId && FLAMEY_ALL_ACCESS_USER_IDS.has(userId)) {
    return new Set(FLAMEY_CATALOG.keys());
  }
  const earned = new Set(earnedBadgeIds);
  const owned = new Set<string>();
  for (const item of FLAMEY_CATALOG.values()) {
    if (item.unlock.kind === "always") owned.add(item.id);
    else if (item.unlock.kind === "plus" && plus) owned.add(item.id);
    else if (item.unlock.kind === "month" && perfectMonths.has(item.unlock.month)) {
      owned.add(item.id);
    }
    else if (item.unlock.kind === "badge" && earned.has(item.unlock.id)) {
      owned.add(item.id);
    }
  }
  return owned;
}
