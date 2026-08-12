export type BadgeCategory =
  | "streak"
  | "miles"
  | "pace"
  | "daily_distance"
  | "challenge"
  | "special"
  | "story"
  | "hype"
  | "nudge"
  | "competition"
  | "buddy"
  | "ghost";
export type BadgeRarity = "common" | "rare" | "legendary";
export type DailyChallengeType =
  | "pace"
  | "distance"
  | "time"
  | "activity"
  | "steps"
  | "social";

export interface Badge {
  badgeId: string;
  category: BadgeCategory;
  name: string;
  description: string;
  icon: string;
  rarity: BadgeRarity;
  requirement: number | null;
  isHidden: boolean;
  sortOrder: number;
}

export interface UserBadge {
  badgeId: string;
  category: BadgeCategory;
  name: string;
  description: string;
  icon: string;
  rarity: BadgeRarity;
  requirement: number | null;
  isHidden: boolean;
  earnedAt: string;
  isNew: boolean;
  pinSlot: number | null;
  triggeringWorkoutId: string | null;
  progressSnapshot: Record<string, unknown> | null;
}

export interface DailyChallenge {
  key: string;
  title: string;
  description: string;
  icon: string;
  gradientStart: string;
  gradientEnd: string;
  type: DailyChallengeType;
}

/** Today's rival for the Head-to-Head challenge. */
/**
 * Someone who picked YOU as their Head-to-Head rival today, other than the
 * rival you were given. Purely for show: only the pinned duel decides whether
 * the challenge completes, and only that one is scored. These are the people
 * who are quietly racing you without you knowing it, which is a much better
 * story to tell the user than nothing at all.
 */
export interface ChallengeChallenger {
  userId: string;
  username: string | null;
  profileImageUrl: string | null;
  miles: number;
}

export interface ChallengeOpponent {
  userId: string;
  username: string | null;
  profileImageUrl: string | null;
  miles: number;
  myMiles: number;
  /** TRUE when the rival got the same matchup back (reciprocal pair). */
  mutual: boolean;
  /**
   * Others who pinned the viewer as THEIR rival today. Never affects the
   * outcome — beating one of these wins nothing. Additive, so older clients
   * ignore it entirely.
   */
  challengers?: ChallengeChallenger[];
}

export interface TodaysChallengeResponse {
  localDate: string;
  challenge: DailyChallenge;
  progress: number;
  completed: boolean;
  completedAt: string | null;
  tomorrowChallenge: DailyChallenge;
  tomorrowLocalDate: string;
  /** Present only for the Head-to-Head challenge. */
  opponent?: ChallengeOpponent | null;
}

export interface ChallengeCompletionHistoryItem {
  localDate: string;
  challengeKey: string;
  title: string;
  icon: string;
  completingWorkoutId: string | null;
  completedAt: string;
}

/**
 * A day inside the history window that went by without its challenge being
 * completed. Carries the challenge itself so the grid can show WHAT was
 * missed rather than a bare empty square.
 */
export interface ChallengeMissedDayItem {
  localDate: string;
  challengeKey: string;
  title: string;
  description: string;
  icon: string;
  gradientStart: string;
  gradientEnd: string;
}

export interface ChallengeCompletionsResponse {
  totalCompleted: number;
  currentStreak: number;
  completions: ChallengeCompletionHistoryItem[];
  /**
   * Additive: the recent days with no completion, newest first. Absent from
   * older servers and ignored by older clients, so the grid degrades to the
   * empty squares it drew before.
   */
  missed: ChallengeMissedDayItem[];
}

export interface FriendTodayChallengeResponse {
  userId: string;
  localDate: string;
  completed: boolean;
  challengeKey: string | null;
  // Enriched so a friend's profile renders the right challenge without relying
  // on a hardcoded client catalog.
  challengeTitle?: string | null;
  challengeIcon?: string | null;
  gradientStart?: string | null;
  gradientEnd?: string | null;
  /** Present only when the friend's today challenge is Head-to-Head. */
  opponent?: ChallengeOpponent | null;
}

/**
 * One finished Head-to-Head duel, from the requesting user's side.
 *
 * `result` is the RACE (who logged more miles, at the 2-decimal precision the
 * duel was scored at); `completed` is the AWARD (whether this duel inserted
 * the day's challenge completion — winning also requires hitting your own
 * goal). The two can disagree and both are true: "you out-ran them but didn't
 * finish your mile" shows a W with no trophy.
 */
export interface MatchupHistoryItem {
  localDate: string;
  rival: {
    userId: string;
    username: string | null;
    profileImageUrl: string | null;
  };
  myMiles: number;
  rivalMiles: number;
  result: "won" | "lost" | "tied";
  mutual: boolean;
  completed: boolean;
}

/** All-time duel record against one rival. */
export interface MatchupRivalRecord {
  userId: string;
  username: string | null;
  profileImageUrl: string | null;
  wins: number;
  losses: number;
  ties: number;
  /** Most recent duel against this rival (yyyy-MM-dd). */
  lastLocalDate: string;
}

export interface MatchupHistoryResponse {
  record: { wins: number; losses: number; ties: number; total: number };
  /** Consecutive duel wins counted back from the most recent resolved duel. */
  currentWinStreak: number;
  bestWinStreak: number;
  /** Sorted by number of duels together, most first. */
  rivals: MatchupRivalRecord[];
  /** Newest first. */
  matchups: MatchupHistoryItem[];
  /**
   * TRUE when the history hit the server's safety cap, meaning `record`,
   * streaks and `rivals` cover only the newest window rather than all time.
   */
  truncated: boolean;
}

// ─── Completion detail (how a past challenge was completed) ─────────

/** Minimal user reference rendered inside a completion detail. */
export interface ChallengeFriendRef {
  userId: string;
  username: string | null;
  profileImageUrl: string | null;
}

/** The finished duel behind a head_to_head completion. */
export interface ChallengeH2hDetail {
  rival: ChallengeFriendRef;
  /** Re-derived from workouts at read time, 2-decimal rounded like scoring. */
  myMiles: number;
  rivalMiles: number;
  result: "won" | "lost" | "tied";
  mutual: boolean;
  /** All-time resolved-duel record against THIS rival. */
  record: { wins: number; losses: number; ties: number };
}

/** The photo post behind a share_journey completion. `mediaUrl` is signed. */
export interface ChallengePostDetail {
  postId: string;
  mediaUrl: string;
  caption: string | null;
  createdAt: string;
}

/** Who was hyped (hype_squad) or nudged (wingman) that day. */
export interface ChallengeSocialDetail {
  /** Distinct friends, capped server-side; `totalActions` is uncapped. */
  friends: ChallengeFriendRef[];
  totalActions: number;
}

export interface ChallengeStepsDetail {
  steps: number;
  goalSteps: number;
}

export interface ChallengePaceDetail {
  /** Fastest qualifying mile split that day, in seconds per mile. */
  bestPaceSecondsPerMile: number | null;
  /** The pace to beat: 720 for speed_round; prior best + 30s for beat_your_pace. */
  targetPaceSecondsPerMile: number | null;
}

export interface ChallengeDistanceDetail {
  miles: number;
  targetMiles: number;
  /** 'walking' when only walk miles counted (walk_it_out). */
  scope: "all" | "walking";
}

export interface ChallengeTimeWindowDetail {
  window: "early" | "late";
  /** Wall-clock finish of the qualifying workout in ITS timezone, "HH:MM" 24h. */
  finishedLocalTime: string | null;
  qualifyingMiles: number | null;
}

export interface ChallengeActivityDetail {
  workoutCount: number;
  runMiles: number;
  walkMiles: number;
  /** Which cross-train variant that day asked for (cross_train only). */
  variant: "walk_today" | "run_today" | "mixed" | null;
}

/**
 * How a past daily challenge was completed. Exactly one of the optional
 * sections is populated, matching the challenge family; every section is
 * re-derived from source tables at read time (nothing extra is stored at
 * award time), so a section can come back null when the underlying rows are
 * gone (deleted post, blocked rival) — clients fall back to the generic
 * header + workouts view.
 */
export interface ChallengeCompletionDetailResponse {
  localDate: string;
  challengeKey: string;
  title: string;
  description: string;
  icon: string;
  gradientStart: string;
  gradientEnd: string;
  completedAt: string | null;
  h2h: ChallengeH2hDetail | null;
  post: ChallengePostDetail | null;
  social: ChallengeSocialDetail | null;
  steps: ChallengeStepsDetail | null;
  pace: ChallengePaceDetail | null;
  distance: ChallengeDistanceDetail | null;
  timeWindow: ChallengeTimeWindowDetail | null;
  activity: ChallengeActivityDetail | null;
  friend: ChallengeFriendRef | null;
}

export interface NewChallengeCompletion {
  localDate: string;
  challengeKey: string;
  challengeTitle: string;
  completingWorkoutId: string | null;
}

export interface RewardEvaluationResult {
  newlyEarnedBadges: UserBadge[];
  newChallengeCompletions: NewChallengeCompletion[];
}

export interface UserAggregates {
  currentStreak: number;
  totalMiles: number;
  fastestSplitPaceMinMi: number;
  mostMilesInOneDay: number;
  challengeCompletionsCount: number;
  // Social / app-function aggregates (v2 medals)
  storyPostsCount: number;
  hypesGivenCount: number;
  nudgesSentCount: number;
  competitionsStarted: number;
  competitionsEntered: number;
  competitionsWon: number;
  // Buddy Walks. `buddyDistinctPartners` counts PEOPLE, not sessions — walking
  // with the same friend fifty times shouldn't unlock the "crew" family.
  buddySessionsCompleted: number;
  buddyDistinctPartners: number;
  buddySessionsWon: number;
  // Ghost races. `workouts.ghost_margin_seconds` is written only on a WIN, so
  // the count is simply how many workouts carry one; `bestGhostMargin` is the
  // biggest single margin, in seconds.
  ghostsBeaten: number;
  bestGhostMargin: number;
}
