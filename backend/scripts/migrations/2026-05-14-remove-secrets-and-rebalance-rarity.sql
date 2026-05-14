-- Remove all hidden/secret badges and rebalance rarity to be monotonic with difficulty.
-- Idempotent: safe to re-run.
--
-- 1. Drop all hidden badges (and any user_badge rows referencing them).
-- 2. Re-tier streak/miles/daily badges so rarity never decreases as the requirement grows.
--    Only upgrades — no user loses rarity on a badge they've already earned.

BEGIN;

-- Hidden badges: delete user-earned rows first (FK-safe), then catalog rows.
DELETE FROM user_badges WHERE badge_id IN (SELECT badge_id FROM badges WHERE category = 'hidden');
DELETE FROM badges WHERE category = 'hidden';

-- Streak rebalance: 50-300 days -> rare, 730 days -> legendary.
UPDATE badges SET rarity = 'rare' WHERE badge_id IN (
  'streak_60', 'streak_90', 'streak_120', 'streak_180', 'streak_250', 'streak_300'
);
UPDATE badges SET rarity = 'legendary' WHERE badge_id = 'streak_730';

-- Miles rebalance: 1500/2000 -> legendary (in line with 1000 and 2500).
UPDATE badges SET rarity = 'legendary' WHERE badge_id IN ('miles_1500', 'miles_2000');

-- Daily distance rebalance: 50K (31 mi) -> legendary (in line with marathon and ultra).
UPDATE badges SET rarity = 'legendary' WHERE badge_id = 'daily_50k';

COMMIT;

-- Sanity check: print categories with non-monotonic rarity (should return 0 rows).
WITH ranked AS (
  SELECT category, badge_id, requirement,
         CASE rarity WHEN 'common' THEN 1 WHEN 'rare' THEN 2 WHEN 'legendary' THEN 3 END AS r
  FROM badges
  WHERE category IN ('streak', 'miles', 'daily_distance', 'challenge')
)
SELECT a.category, a.badge_id AS lower_req, b.badge_id AS higher_req, a.r AS lower_rarity, b.r AS higher_rarity
FROM ranked a
JOIN ranked b ON a.category = b.category AND a.requirement < b.requirement
WHERE a.r > b.r;
