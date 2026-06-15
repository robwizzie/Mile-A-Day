import { relations } from "drizzle-orm/relations";
import { workouts, workoutSplits, users, competitions, refreshTokens, deviceTokens, pendingNotifications, userBadges, badges, inAppNotifications, userChallengeCompletions, dailyChallenges, friendships, dailySteps, competitionUsers } from "./schema.js";

export const workoutSplitsRelations = relations(workoutSplits, ({one}) => ({
	workout: one(workouts, {
		fields: [workoutSplits.workoutId],
		references: [workouts.workoutId]
	}),
}));

export const workoutsRelations = relations(workouts, ({many}) => ({
	workoutSplits: many(workoutSplits),
	userBadges: many(userBadges),
	userChallengeCompletions: many(userChallengeCompletions),
}));

export const competitionsRelations = relations(competitions, ({one, many}) => ({
	user_winner: one(users, {
		fields: [competitions.winner],
		references: [users.userId],
		relationName: "competitions_winner_users_userId"
	}),
	user_owner: one(users, {
		fields: [competitions.owner],
		references: [users.userId],
		relationName: "competitions_owner_users_userId"
	}),
	competitionUsers: many(competitionUsers),
}));

export const usersRelations = relations(users, ({many}) => ({
	competitions_winner: many(competitions, {
		relationName: "competitions_winner_users_userId"
	}),
	competitions_owner: many(competitions, {
		relationName: "competitions_owner_users_userId"
	}),
	refreshTokens: many(refreshTokens),
	deviceTokens: many(deviceTokens),
	pendingNotifications: many(pendingNotifications),
	userBadges: many(userBadges),
	inAppNotifications: many(inAppNotifications),
	userChallengeCompletions: many(userChallengeCompletions),
	friendships_userId: many(friendships, {
		relationName: "friendships_userId_users_userId"
	}),
	friendships_friendId: many(friendships, {
		relationName: "friendships_friendId_users_userId"
	}),
	dailySteps: many(dailySteps),
	competitionUsers: many(competitionUsers),
}));

export const refreshTokensRelations = relations(refreshTokens, ({one}) => ({
	user: one(users, {
		fields: [refreshTokens.userId],
		references: [users.userId]
	}),
}));

export const deviceTokensRelations = relations(deviceTokens, ({one}) => ({
	user: one(users, {
		fields: [deviceTokens.userId],
		references: [users.userId]
	}),
}));

export const pendingNotificationsRelations = relations(pendingNotifications, ({one}) => ({
	user: one(users, {
		fields: [pendingNotifications.userId],
		references: [users.userId]
	}),
}));

export const userBadgesRelations = relations(userBadges, ({one}) => ({
	user: one(users, {
		fields: [userBadges.userId],
		references: [users.userId]
	}),
	badge: one(badges, {
		fields: [userBadges.badgeId],
		references: [badges.badgeId]
	}),
	workout: one(workouts, {
		fields: [userBadges.triggeringWorkoutId],
		references: [workouts.workoutId]
	}),
}));

export const badgesRelations = relations(badges, ({many}) => ({
	userBadges: many(userBadges),
}));

export const inAppNotificationsRelations = relations(inAppNotifications, ({one}) => ({
	user: one(users, {
		fields: [inAppNotifications.userId],
		references: [users.userId]
	}),
}));

export const userChallengeCompletionsRelations = relations(userChallengeCompletions, ({one}) => ({
	user: one(users, {
		fields: [userChallengeCompletions.userId],
		references: [users.userId]
	}),
	dailyChallenge: one(dailyChallenges, {
		fields: [userChallengeCompletions.challengeKey],
		references: [dailyChallenges.challengeKey]
	}),
	workout: one(workouts, {
		fields: [userChallengeCompletions.completingWorkoutId],
		references: [workouts.workoutId]
	}),
}));

export const dailyChallengesRelations = relations(dailyChallenges, ({many}) => ({
	userChallengeCompletions: many(userChallengeCompletions),
}));

export const friendshipsRelations = relations(friendships, ({one}) => ({
	user_userId: one(users, {
		fields: [friendships.userId],
		references: [users.userId],
		relationName: "friendships_userId_users_userId"
	}),
	user_friendId: one(users, {
		fields: [friendships.friendId],
		references: [users.userId],
		relationName: "friendships_friendId_users_userId"
	}),
}));

export const dailyStepsRelations = relations(dailySteps, ({one}) => ({
	user: one(users, {
		fields: [dailySteps.userId],
		references: [users.userId]
	}),
}));

export const competitionUsersRelations = relations(competitionUsers, ({one}) => ({
	user: one(users, {
		fields: [competitionUsers.userId],
		references: [users.userId]
	}),
	competition: one(competitions, {
		fields: [competitionUsers.competitionId],
		references: [competitions.id]
	}),
}));