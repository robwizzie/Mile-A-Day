-- Badge catalog seed. Idempotent: re-runs overwrite name/description/icon/rarity/etc. for tuning.
--
-- Rarity is monotonic with difficulty within each category:
--   streak:    common <=45 days, rare 50-300 days, legendary >=365 days
--   miles:     common <=250 mi,  rare 500-750 mi,  legendary >=1000 mi
--   pace:      common 9-12 min,  rare 7-8 min,     legendary <=6 min  (lower = harder)
--   daily:     common <=10 mi,   rare 13.1-20 mi,  legendary >=26.2 mi
--   challenge: common <=10,      rare 25-50,       legendary >=100
--   special:   rare

INSERT INTO badges (badge_id, category, name, description, icon, rarity, requirement, is_hidden, sort_order) VALUES
  -- Streak (23)
  ('consistency_3',  'streak',          'Getting Started',       '3 day streak!',    'flame.fill',  'common',     3,    FALSE, 10),
  ('consistency_5',  'streak',          'Building Habits',       '5 day streak!',    'flame.fill',  'common',     5,    FALSE, 11),
  ('streak_7',       'streak',          'Week Warrior',          '7 day streak!',    'flame.fill',  'common',     7,    FALSE, 12),
  ('streak_10',      'streak',          'Ten Days Strong',       '10 day streak!',   'flame.fill',  'common',     10,   FALSE, 13),
  ('streak_14',      'streak',          'Fortnight Fighter',     '14 day streak!',   'flame.fill',  'common',     14,   FALSE, 14),
  ('streak_21',      'streak',          'Three Week Champion',   '21 day streak!',   'flame.fill',  'common',     21,   FALSE, 15),
  ('streak_30',      'streak',          'Monthly Master',        '30 day streak!',   'flame.fill',  'common',     30,   FALSE, 16),
  ('streak_45',      'streak',          '45 Day Legend',         '45 day streak!',   'flame.fill',  'common',     45,   FALSE, 17),
  ('streak_50',      'streak',          'Half Century',          '50 day streak!',   'flame.fill',  'rare',       50,   FALSE, 18),
  ('streak_60',      'streak',          'Two Month Milestone',   '60 day streak!',   'flame.fill',  'rare',       60,   FALSE, 19),
  ('streak_75',      'streak',          'Consistency King',      '75 day streak!',   'flame.fill',  'rare',       75,   FALSE, 20),
  ('streak_90',      'streak',          'Quarter Year Hero',     '90 day streak!',   'flame.fill',  'rare',       90,   FALSE, 21),
  ('streak_100',     'streak',          'Century Club',          '100 day streak!',  'flame.fill',  'rare',       100,  FALSE, 22),
  ('streak_120',     'streak',          'Four Month Fury',       '120 day streak!',  'flame.fill',  'rare',       120,  FALSE, 23),
  ('streak_150',     'streak',          'Unstoppable Force',     '150 day streak!',  'flame.fill',  'rare',       150,  FALSE, 24),
  ('streak_180',     'streak',          'Half Year Hero',        '180 day streak!',  'flame.fill',  'rare',       180,  FALSE, 25),
  ('streak_200',     'streak',          'Double Century',        '200 day streak!',  'flame.fill',  'rare',       200,  FALSE, 26),
  ('streak_250',     'streak',          'Legendary Streak',      '250 day streak!',  'flame.fill',  'rare',       250,  FALSE, 27),
  ('streak_300',     'streak',          '300 Club',              '300 day streak!',  'flame.fill',  'rare',       300,  FALSE, 28),
  ('streak_365',     'streak',          'Year Warrior',          '365 day streak!',  'flame.fill',  'legendary',  365,  FALSE, 29),
  ('streak_500',     'streak',          'Elite Runner',          '500 day streak!',  'flame.fill',  'legendary',  500,  FALSE, 30),
  ('streak_730',     'streak',          'Two Year Titan',        '730 day streak!',  'flame.fill',  'legendary',  730,  FALSE, 31),
  ('streak_1000',    'streak',          'Immortal',              '1000 day streak!', 'flame.fill',  'legendary',  1000, FALSE, 32),

  -- Miles (12)
  ('miles_25',       'miles',           '25 Mile Mark',          'Ran 25 total miles!',   'figure.run', 'common',    25,   FALSE, 110),
  ('miles_50',       'miles',           '50 Mile Club',          'Ran 50 total miles!',   'figure.run', 'common',    50,   FALSE, 111),
  ('miles_100',      'miles',           'Century Runner',        'Ran 100 total miles!',  'figure.run', 'common',    100,  FALSE, 112),
  ('miles_150',      'miles',           '150 Mile Mark',         'Ran 150 total miles!',  'figure.run', 'common',    150,  FALSE, 113),
  ('miles_200',      'miles',           '200 Mile Mark',         'Ran 200 total miles!',  'figure.run', 'common',    200,  FALSE, 114),
  ('miles_250',      'miles',           '250 Mile Club',         'Ran 250 total miles!',  'figure.run', 'common',    250,  FALSE, 115),
  ('miles_500',      'miles',           '500 Mile Club',         'Ran 500 total miles!',  'figure.run', 'rare',      500,  FALSE, 116),
  ('miles_750',      'miles',           '750 Mile Club',         'Ran 750 total miles!',  'figure.run', 'rare',      750,  FALSE, 117),
  ('miles_1000',     'miles',           '1000 Mile Club',        'Ran 1000 total miles!', 'figure.run', 'legendary', 1000, FALSE, 118),
  ('miles_1500',     'miles',           '1500 Mile Legend',      'Ran 1500 total miles!', 'figure.run', 'legendary', 1500, FALSE, 119),
  ('miles_2000',     'miles',           '2000 Mile Legend',      'Ran 2000 total miles!', 'figure.run', 'legendary', 2000, FALSE, 120),
  ('miles_2500',     'miles',           'Ultra Runner',          'Ran 2500 total miles!', 'figure.run', 'legendary', 2500, FALSE, 121),

  -- Pace (8). `requirement` is max min/mi (lower = faster).
  ('pace_12min',     'pace',            'Getting Faster',        'Sub-12 minute mile!',  'bolt.fill', 'common',    12,  FALSE, 210),
  ('pace_11min',     'pace',            'Picking Up Speed',      'Sub-11 minute mile!',  'bolt.fill', 'common',    11,  FALSE, 211),
  ('pace_10min',     'pace',            'Double Digits',         'Sub-10 minute mile!',  'bolt.fill', 'common',    10,  FALSE, 212),
  ('pace_9min',      'pace',            'Solid Pace',            'Sub-9 minute mile!',   'bolt.fill', 'common',    9,   FALSE, 213),
  ('pace_8min',      'pace',            'Fast Runner',           'Sub-8 minute mile!',   'bolt.fill', 'rare',      8,   FALSE, 214),
  ('pace_7min',      'pace',            'Quick Runner',          'Sub-7 minute mile!',   'bolt.fill', 'rare',      7,   FALSE, 215),
  ('pace_6min',      'pace',            'Speed Demon',           'Sub-6 minute mile!',   'bolt.fill', 'legendary', 6,   FALSE, 216),
  ('pace_5min',      'pace',            'Elite Speed',           'Sub-5 minute mile! Incredible!', 'bolt.fill', 'legendary', 5, FALSE, 217),

  -- Daily distance (12)
  ('daily_2',        'daily_distance',  '2 Mile Day',            'Ran 2+ miles in one day!',        'location.fill', 'common',    2,    FALSE, 310),
  ('daily_3',        'daily_distance',  '5K Runner',             'Ran 3+ miles (5K) in one day!',   'location.fill', 'common',    3,    FALSE, 311),
  ('daily_5',        'daily_distance',  '5 Mile Day',            'Ran 5+ miles in one day!',        'location.fill', 'common',    5,    FALSE, 312),
  ('daily_10k',      'daily_distance',  '10K Runner',            'Ran 6.2+ miles (10K) in one day!', 'location.fill', 'common',   6.2,  FALSE, 313),
  ('daily_8',        'daily_distance',  '8 Mile Day',            'Ran 8+ miles in one day!',        'location.fill', 'common',    8,    FALSE, 314),
  ('daily_10',       'daily_distance',  '10 Mile Day',           'Ran 10+ miles in one day!',       'location.fill', 'common',    10,   FALSE, 315),
  ('daily_half',     'daily_distance',  'Half Marathon',         'Ran 13.1+ miles in one day!',     'location.fill', 'rare',      13.1, FALSE, 316),
  ('daily_15',       'daily_distance',  '15 Mile Day',           'Ran 15+ miles in one day!',       'location.fill', 'rare',      15,   FALSE, 317),
  ('daily_20',       'daily_distance',  '20 Mile Day',           'Ran 20+ miles in one day!',       'location.fill', 'rare',      20,   FALSE, 318),
  ('daily_marathon', 'daily_distance',  'Marathon Runner',       'Ran 26.2+ miles in one day!',     'location.fill', 'legendary', 26.2, FALSE, 319),
  ('daily_50k',      'daily_distance',  '50K Ultra',             'Ran 31+ miles (50K) in one day!', 'location.fill', 'legendary', 31,   FALSE, 320),
  ('daily_ultra',    'daily_distance',  'Ultra Legend',          'Ran 50+ miles in one day!',       'location.fill', 'legendary', 50,   FALSE, 321),

  -- Challenge (6)
  ('challenge_1',    'challenge',       'Challenge Accepted',    'Complete your first daily challenge!', 'star.fill', 'common',    1,   FALSE, 410),
  ('challenge_5',    'challenge',       'Challenge Seeker',      'Complete 5 daily challenges!',         'star.fill', 'common',    5,   FALSE, 411),
  ('challenge_10',   'challenge',       'Challenge Pro',         'Complete 10 daily challenges!',        'star.fill', 'common',    10,  FALSE, 412),
  ('challenge_25',   'challenge',       'Challenge Master',      'Complete 25 daily challenges!',        'star.fill', 'rare',      25,  FALSE, 413),
  ('challenge_50',   'challenge',       'Challenge Legend',      'Complete 50 daily challenges!',        'star.fill', 'rare',      50,  FALSE, 414),
  ('challenge_100',  'challenge',       'Challenge Immortal',    'Complete 100 daily challenges!',       'star.fill', 'legendary', 100, FALSE, 415),

  -- Special (2)
  ('special_first_mile', 'special',     'First Mile',            'Completed your first mile! The journey begins!', 'checkmark.seal.fill', 'rare', 1, FALSE, 510),
  ('special_first_week', 'special',     'Perfect Week',          'Ran at least a mile every day for a week!',      'checkmark.seal.fill', 'rare', 7, FALSE, 511)
ON CONFLICT (badge_id) DO UPDATE SET
  category    = EXCLUDED.category,
  name        = EXCLUDED.name,
  description = EXCLUDED.description,
  icon        = EXCLUDED.icon,
  rarity      = EXCLUDED.rarity,
  requirement = EXCLUDED.requirement,
  is_hidden   = EXCLUDED.is_hidden,
  sort_order  = EXCLUDED.sort_order;
