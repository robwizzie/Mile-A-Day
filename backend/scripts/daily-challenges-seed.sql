-- Daily challenge catalog seed. Idempotent. File is UTF-8 (contains em-dash characters).
-- Rotation: day_of_year(local_date) % count(active=TRUE), ordered by rotation_index.
-- Gradient hexes match Apple's standard system colors (SwiftUI named colors).
--
-- Notes on dynamic challenges:
--   * cross_train: title/description/icon are overridden per-user at request time
--     based on the user's last-7-day running vs walking mix. The seed values here
--     are the "balanced" defaults shown if we have no history yet.
--   * early_or_late: completed by finishing a goal-mile before 9 AM OR after 8 PM
--     local time. Either window counts.

BEGIN;

-- Retire legacy keys that were replaced. Run FIRST so their rotation_index frees up before
-- the new rows below claim the same slots. Keep rows so historical completions still resolve
-- titles/icons via the JOIN — just mark inactive and push rotation_index out of the live range.
UPDATE daily_challenges SET active = FALSE, rotation_index = 100 WHERE challenge_key = 'early_bird';
UPDATE daily_challenges SET active = FALSE, rotation_index = 101 WHERE challenge_key = 'walk_it_out';

-- Active rotation (7 challenges, ~weekly cycle).
INSERT INTO daily_challenges (challenge_key, title, description_template, icon, gradient_start, gradient_end, type, active, rotation_index) VALUES
  ('beat_your_pace', 'Beat Your Pace',          'Run faster than {avg_pace} min/mi today',         'bolt.fill',           '#FF9500', '#FF3B30', 'pace',     TRUE, 0),
  ('double_down',    'Double Down',             'Run 2+ miles today instead of just 1',            '2.circle.fill',       '#AF52DE', '#007AFF', 'distance', TRUE, 1),
  ('early_or_late',  'Early Bird or Night Owl', 'Finish a mile before 9 AM or after 8 PM',         'moon.stars.fill',     '#FFCC00', '#5856D6', 'time',     TRUE, 2),
  ('cross_train',    'Cross-Train',             'Mix it up — log both a walk and a run today',     'figure.mixed.cardio', '#34C759', '#5AC8FA', 'activity', TRUE, 3),
  ('speed_round',    'Speed Round',             'Finish your mile in under 12 minutes',            'timer',               '#FF3B30', '#FF2D55', 'pace',     TRUE, 4),
  ('bonus_mile',     'Bonus Mile',              'Run an extra half mile beyond your goal',         'plus.circle.fill',    '#32ADE6', '#007AFF', 'distance', TRUE, 5),
  ('ten_k_steps',    '10K Steps',               'Hit 10,000 steps alongside your mile',            'shoeprints.fill',     '#00C7BE', '#34C759', 'steps',    TRUE, 6),
  -- v2 additions (also auto-seeded idempotently at startup via seedExtraChallenges).
  -- `social` challenges are skipped per-user when the user has no friends.
  ('five_k_day',     '5K Day',                  'Go the distance — cover 3.1 miles (a full 5K) today', 'figure.run',              '#FF9500', '#FF3B30', 'distance', TRUE, 7),
  ('ten_k_day',      '10K Day',                 'Big effort — cover 6.2 miles (a full 10K) today',     'figure.run.circle.fill',  '#AF52DE', '#FF2D55', 'distance', TRUE, 8),
  ('two_a_day',      'Two-a-Day',               'Log two separate workouts today',                     'arrow.triangle.2.circlepath', '#5AC8FA', '#34C759', 'activity', TRUE, 9),
  ('hype_squad',     'Hype Squad',              'Cheer on 3 different friends today',                   'hands.clap.fill',         '#FF2D55', '#FF9500', 'social',   TRUE, 10),
  ('share_journey',  'Share the Journey',       'Post a photo to the feed today',                      'camera.fill',             '#007AFF', '#AF52DE', 'social',   TRUE, 11),
  ('head_to_head',   'Head-to-Head',            'Out-run a friend today — log more miles than them!',  'flag.2.crossed.fill',     '#FF3B30', '#5856D6', 'social',   TRUE, 12)
ON CONFLICT (challenge_key) DO UPDATE SET
  title                = EXCLUDED.title,
  description_template = EXCLUDED.description_template,
  icon                 = EXCLUDED.icon,
  gradient_start       = EXCLUDED.gradient_start,
  gradient_end         = EXCLUDED.gradient_end,
  type                 = EXCLUDED.type,
  active               = EXCLUDED.active,
  rotation_index       = EXCLUDED.rotation_index;

COMMIT;
