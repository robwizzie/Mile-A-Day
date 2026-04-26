-- Daily challenge catalog seed. Idempotent.
-- Rotation: day_of_year(local_date) % count(active=TRUE), matches iOS DailyChallengeCatalog order.
-- Gradient hexes match Apple's standard system colors (SwiftUI named colors).

INSERT INTO daily_challenges (challenge_key, title, description_template, icon, gradient_start, gradient_end, type, active, rotation_index) VALUES
  ('beat_your_pace', 'Beat Your Pace', 'Run faster than {avg_pace} min/mi today',            'bolt.fill',          '#FF9500', '#FF3B30', 'pace',     TRUE, 0),
  ('double_down',    'Double Down',    'Run 2+ miles today instead of just 1',               '2.circle.fill',      '#AF52DE', '#007AFF', 'distance', TRUE, 1),
  ('early_bird',     'Early Bird',     'Complete your mile before noon',                     'sunrise.fill',       '#FFCC00', '#FF9500', 'time',     TRUE, 2),
  ('walk_it_out',    'Walk It Out',    'Walk your mile today — slow and steady',             'figure.walk',        '#34C759', '#5AC8FA', 'activity', TRUE, 3),
  ('speed_round',    'Speed Round',    'Finish your mile in under 12 minutes',               'timer',              '#FF3B30', '#FF2D55', 'pace',     TRUE, 4),
  ('bonus_mile',     'Bonus Mile',     'Run an extra half mile beyond your goal',            'plus.circle.fill',   '#32ADE6', '#007AFF', 'distance', TRUE, 5),
  ('ten_k_steps',    '10K Steps',      'Hit 10,000 steps alongside your mile',               'shoeprints.fill',    '#00C7BE', '#34C759', 'steps',    TRUE, 6)
ON CONFLICT (challenge_key) DO UPDATE SET
  title                = EXCLUDED.title,
  description_template = EXCLUDED.description_template,
  icon                 = EXCLUDED.icon,
  gradient_start       = EXCLUDED.gradient_start,
  gradient_end         = EXCLUDED.gradient_end,
  type                 = EXCLUDED.type,
  active               = EXCLUDED.active,
  rotation_index       = EXCLUDED.rotation_index;
