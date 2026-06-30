export type BadgeCategory =
  | "streak"
  | "miles"
  | "pace"
  | "daily_distance"
  | "challenge"
  | "special"
  | "story"
  | "hype"
  | "competition";
export type BadgeRarity = "common" | "rare" | "legendary";
export type DailyChallengeType =
  | "pace"
  | "distance"
  | "time"
  | "activity"
  | "steps";

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

export interface TodaysChallengeResponse {
  localDate: string;
  challenge: DailyChallenge;
  progress: number;
  completed: boolean;
  completedAt: string | null;
  tomorrowChallenge: DailyChallenge;
  tomorrowLocalDate: string;
}

export interface ChallengeCompletionHistoryItem {
  localDate: string;
  challengeKey: string;
  title: string;
  icon: string;
  completingWorkoutId: string | null;
  completedAt: string;
}

export interface ChallengeCompletionsResponse {
  totalCompleted: number;
  currentStreak: number;
  completions: ChallengeCompletionHistoryItem[];
}

export interface FriendTodayChallengeResponse {
  userId: string;
  localDate: string;
  completed: boolean;
  challengeKey: string | null;
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
  competitionsStarted: number;
  competitionsEntered: number;
  competitionsWon: number;
}
