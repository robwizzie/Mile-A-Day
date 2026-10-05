// postService is a barrel: the implementation lives in ./posts/*, split along
// its existing seams (shared SQL fragments at the bottom of the graph). Every
// name this module ever exported is re-exported here unchanged, so importers
// (controllers, services, cron, and the dist-importing scripts/*.mjs checks)
// never need to know where a symbol lives.
export {
  sanitizeGhostStats,
  MAX_POST_COAUTHORS,
} from "./posts/postTypes.js";
export type {
  PostStatsSnapshot,
  PostCompetitionRef,
  PostCoauthor,
  CommentPreview,
  PostRow,
  StoryGroup,
} from "./posts/postTypes.js";
export {
  CIRCLE_CTE,
  postCommentMatchSql,
} from "./posts/postSql.js";
export {
  POST_WINDOW_MS,
  photoSourceRequiresCameraWindow,
  POST_WINDOW_GRACE_MS,
  getPostWindowStatus,
} from "./posts/postWindow.js";
export type {
  PostPhotoSource,
  PostWindowStatus,
} from "./posts/postWindow.js";
export {
  visiblePostAuthors,
  visiblePostPreviews,
  visiblePostAuthor,
  visibleWorkoutAuthor,
} from "./posts/postAccess.js";
export type {
  VisiblePostAuthors,
  VisiblePostPreview,
} from "./posts/postAccess.js";
export {
  notifyFriendsOfPost,
  notifyCoauthorInvite,
  notifyCrewPhoto,
  notifyCoauthorAccepted,
} from "./posts/postNotifications.js";
export {
  postAuthorId,
  acceptedCoauthorIds,
  respondToMultiCoauthorInvite,
  acceptedCoauthor,
  respondToCoauthorInvite,
  setCoauthorProfileVisibility,
  setCoauthorFeedVisibility,
  setCoauthorRoutePreference,
} from "./posts/coauthors.js";
export {
  buddySessionIdForWorkout,
  createPost,
} from "./posts/createPost.js";
export type {
  CreatePostInput,
} from "./posts/createPost.js";
export {
  getStoriesRail,
  getUserActiveStories,
  markStoryViewed,
  getStoryViewers,
  getStoryReactors,
  ALLOWED_STORY_REACTIONS,
  reactToStory,
} from "./posts/stories.js";
export type {
  StoryViewerRow,
  StoryReactorRow,
} from "./posts/stories.js";
export {
  userOwnsWorkout,
  getOwnedWorkoutDistance,
  getOwnedWorkoutRollupDistance,
} from "./posts/workoutOwnership.js";
export {
  lockUnearnedPhotos,
} from "./posts/photoLock.js";
export type {
  ViewerGoalGate,
} from "./posts/photoLock.js";
export {
  getFeed,
  UNIFIED_FEED_SQL,
  getUnifiedFeed,
  getFeedEntryForPost,
  getPublicPostPreview,
} from "./posts/feed.js";
export type {
  FeedSegment,
  FeedEntryRow,
  PublicPostPreview,
} from "./posts/feed.js";
export {
  getOwnPostMemories,
  POST_PIN_LIMIT,
  parseUserPostsSort,
  parseUserPostsFilter,
  getUserPosts,
  getUserPinnedPosts,
  setPostPinned,
  getUserTaggedPosts,
} from "./posts/grid.js";
export type {
  UserPostsSort,
  UserPostsFilter,
  UserPostsQuery,
} from "./posts/grid.js";
export {
  buddySessionPhotos,
  buddySessionPostIds,
  buddySessionPost,
  addCrewPhoto,
  setCrewCaption,
  sweepCrewPhotoNudges,
} from "./posts/crewPosts.js";
export type {
  BuddySessionPhoto,
  BuddySessionPost,
} from "./posts/crewPosts.js";
export {
  getPostAuthor,
  softDeletePost,
  updateOwnPost,
  moderatorDeletePost,
  hasAcceptedTerms,
  acceptTerms,
} from "./posts/postLifecycle.js";
export type {
  UpdatePostResult,
} from "./posts/postLifecycle.js";
export {
  MAX_HIGHLIGHTS_PER_USER,
  MAX_HIGHLIGHT_ITEMS,
  MAX_HIGHLIGHT_TITLE,
  listUserHighlights,
  getHighlight,
  HIGHLIGHT_SLIDE_WHOLE_POST,
  HIGHLIGHT_SLIDE_MAP,
  createHighlight,
  updateHighlight,
  deleteHighlight,
} from "./posts/highlights.js";
export type {
  PostHighlight,
  HighlightItem,
  HighlightDetail,
  HighlightWriteResult,
  HighlightSlide,
} from "./posts/highlights.js";
