export type CompetitionActivity = "running" | "walking";

export type CompetitionType = "streaks" | "apex" | "clash" | "targets" | "race";

export interface CompetitionOptions {
  history?: boolean;
  interval?: "day" | "week" | "month";
  goal: number;
  unit: "miles" | "steps";
  first_to: number;
  duration_hours?: number;
  lives?: number;
}

// Per-day activity split by workout type ("running"/"walking"):
// { "2026-07-01": { running: { distance: 1.2, count: 1 } } }
export type DailyActivityBreakdown = {
  [localDate: string]: {
    [workoutType: string]: { distance: number; count: number };
  };
};

export interface CompetitionTeam {
  id: string;
  name: string;
  // Derived at read time for started competitions: sum of member scores.
  score?: number;
}

// Stored in competitions.teams (jsonb). NULL column = no team play.
export interface CompetitionTeams {
  member_pick: boolean;
  teams: CompetitionTeam[];
}

export interface CompetitionUser {
  competition_id: string;
  user_id: string;
  invite_status: string;
  team_id?: string | null;
  intervals?: { [intervalKey: string]: number };
  score?: number;
  remaining_lives?: number;
  username?: string;
  placement?: number;
  daily_activity?: DailyActivityBreakdown;
}

export interface Competition {
  id: string;
  competition_name: string;
  start_date: string | null;
  end_date: string | null;
  workouts: CompetitionActivity[];
  type: CompetitionType;
  options: CompetitionOptions;
  owner: string;
  winner: string | null;
  teams?: CompetitionTeams | null;
  users: CompetitionUser[];
}

// MARK: - Competition record (GET /competitions/record)

export interface CompetitionRecordTally {
  wins: number;
  losses: number;
  total: number;
  podiums: number;
  /**
   * How many of `total` actually carry a placement. `competition_users.placement`
   * was added after launch, so competitions resolved before it read NULL — they
   * count toward wins/losses (which come from `competitions.winner`, always
   * stamped) but can't contribute a podium. Surfaced so the client can say
   * "3 podiums of 41 recorded" rather than implying a wrong number.
   */
  podiums_known_of: number;
}

export interface CompetitionRecordByType {
  type: CompetitionType;
  wins: number;
  losses: number;
  total: number;
}

export interface CompetitionRival {
  user_id: string;
  username: string | null;
  first_name: string | null;
  profile_image_url: string | null;
  /** Competitions we both finished where I placed first. */
  wins: number;
  /** ...where they did. */
  losses: number;
  /**
   * Every finished competition we were both in. A competition a THIRD party
   * won counts here and in neither `wins` nor `losses` — it happened, but it
   * wasn't a result between us.
   */
  meetings: number;
  last_competed_on: string | null;
}

export interface CompetitionRecentResult {
  competition_id: string;
  competition_name: string;
  type: CompetitionType;
  end_date: string | null;
  /** NULL for competitions resolved before the placement column existed. */
  placement: number | null;
  participant_count: number;
  winner_user_id: string | null;
  won: boolean;
}

export interface CompetitionRecordResponse {
  record: CompetitionRecordTally;
  win_rate: number;
  current_win_streak: number;
  best_win_streak: number;
  by_type: CompetitionRecordByType[];
  rivals: CompetitionRival[];
  recent: CompetitionRecentResult[];
  /** True when the user has more finished competitions than the read's cap. */
  truncated: boolean;
}
