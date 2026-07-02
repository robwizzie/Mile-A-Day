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

export interface CompetitionUser {
  competition_id: string;
  user_id: string;
  invite_status: string;
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
  users: CompetitionUser[];
}
