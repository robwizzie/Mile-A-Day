---
paths: app/**
---

# iOS App Conventions
One line per rule. The why, incidents and evidence live in `docs/conventions/ios.md` under the same heading: read it before changing that area, and put any new explanation there, not here.

## HealthKit
Details: docs/conventions/ios.md § HealthKit
- Workout sync: HealthKit -> WorkoutProcessor -> WorkoutSyncService -> Backend API
- `syncNewWorkouts`'s `isSyncing` clears via `defer`; its incremental filter scans 48h behind `lastSyncDate`, never strict `endDate > lastSync`.
- A workout's day is `HealthKitManager.localDay(for:)` everywhere; never "correct" an HKWorkout's clock or use `end - duration`; bump `WorkoutIndex.load()`'s version for persisted fixes.
- Builders use `HealthKitManager.healthStore`, never inline `HKHealthStore()`; route points strictly ascending (`WorkoutRouteCleanup`) with speed/course; phone energy (`WorkoutEnergyEstimate`) rides the distance batch, never a second `add`.
- A HealthKit query ERROR (locked device) is never 0 miles; only a successful empty result is.
- In-app workouts `finishRoute` after `finishWorkout` (`workoutRoute()` in the SHARE set), then call `WorkoutSyncService.uploadWorkout(withId:)`.
- Project lines on an `MKMapSnapshotter` image via `snapshot.point(for:)` at the view's size (`RouteMapSnapshot`); per-line timing via `.animation(_:value:)`; crew colours via `companionColors(count:avoiding:)`.
- Widgets render statically (no `.onAppear` animations; bake `Timeline` entries); `WidgetDataStore` is day-stamped and skips no-op writes; mirror app prefs to the App Group; new widget files go in `app/MileADayWidgets/`.
- Dashboard styles offered = `DashboardStylePreference.offered` (Fun only; `enforceOffered()` at launch); gate style pickers on `offersChoice`; flame size (never opacity) shows time, all sizing reads `FlameBuddyView.sizingDate`; `.coal` origin only at streak <= 1; warm one figure (`blaze:`), never crossfade two; one `HeroStatColumn`; derive widget layout from `GeometryReader` (`FlameColumnMetrics.fitting`), never predict.
- Widgets never poll `.after(interval)`: only `.after(MADWidgetClock.endOfDay())` + `hourlyEntryDates()` + a midnight entry; countdowns via `MADWidgetCountdown.text(to:)`.
- Resolve Flamey's mood once via `FlameMoodKind` for every surface; widgets resolve per entry date; static drawing is `FlameyDressedFigure(mood:)`; poke-wake mirrors via `save(flameyWokenDay:)`.
- Competition/Leaderboard widgets refresh only via the `widget_refresh` silent push (`WidgetLiveRefresh.handleRefreshPush`, shared snapshot builders); needs `remote-notification` in `UIBackgroundModes`; new kinds go in server `WIDGET_KINDS`.
- Background reads gate on `hasLoadedInitialData`; writes of today's miles wait for `fetchTodaysDistance(completion:)` → `true` (on `false` write nothing, retry later); `MADBackgroundService` uses `UserManager.shared`/`HealthKitManager.shared`; `checkForMileCompletion` never calls `completeRun`.
- `WorkoutIndex` incremental updates keep the 48h lookback + record-id dedup; `repairWorkoutIndexIfStale` rebuilds.
- `cachedWorkouts` grows mid-session only via `fetchRecentWorkouts` → `updateCachedWorkoutData` (`fetchWorkoutsSmartly` no-ops with an index); never seed an EMPTY cache.
- Splits only via `SplitCalculator`: a sample > ½ mi is timed from the route (`splitsFromRoute`, pauses excluded); no route + a whole-mile sample ⇒ `[]`, never interpolated averages; the file is also a Watch member, so the route path stays `#if !os(watchOS)`.
- Never write `hk.retroactiveStreak` raw to UI/widgets/watch: go through `updateUserWithHealthKitData` (`vettedHealthKitStreak`) / `max(hk, user.streak)`.
- Never claim HealthKit READ auth (`HealthAccessMonitor`); offer "Grant access" only on `.needsRequest`; keep `healthKitReadTypes/WriteTypes` non-private.
- One settings page, `MADSettingsView`, behind the Dashboard gear; it owns its alerts, sheets and account actions.
- Recalibrate's running state is `WorkoutSyncService.recalibration` (drives `SyncStatusBanner` + the Settings row), never view `@State`.
- `PostGridFilter` is `all`/`collabs`; grid prefs and pins apply to the OWNER's grid only (visitors get defaults); name the filter that emptied a grid; nil server fields mean "not offered"; add FeedEntry CodingKeys cases.
- First-run import: long-lived stores, `workoutDetails` 6-wide, report `preparedCount`; classify via `SyncFailure`, never show `localizedDescription`; retry via `retryFailedSync()`; gate on `isImportingHistory`.
- Put `.ignoresSafeArea(.keyboard, edges: .bottom)` on bottom overlays and `GeometryReader` layouts, never on a ZStack holding the TabView.
- A number beside a name needs `lineLimit(1)`; flame+streak is always `StreakFlameChip`.
- Every new `User` field must be Optional; `restoreFailed` → `hasLostLocalIdentity` signs out; never bake an unvouched name into an image.
- `.lockedToScrollWidth()` goes LAST on full-bleed scroll content, never the ScrollView or narrow leading content.
- Referral catalog changes touch `referralOptions`, `REFERRAL_SOURCES`, `SOURCE_LABELS` (+ `PERSON_REFERRAL_SOURCES`).
- Show a streak range's start year when the end has one or they differ; `StreakStartExplainer` names the gap.
- Lifetime miles = `currentUser.totalMiles` (backend), never `healthManager.totalLifetimeMiles`; a server 0 never overwrites it; refresh stats beside badges.

## Key Patterns
Details: docs/conventions/ios.md § Key Patterns
- Profiles compose from `ProfileHero.swift`; `NextMilestoneChip` gets the loaded badges; friend screen re-fetches `GET /users/:id`; the banner PATCH can only CLEAR `profile_banner_url`.
- Post-card controls sit in `mediaControls` UNDER the media; on-media items go after `.instagramZoomable`; flyover entry is always `FlyoverChipButton(accent:)`; no-photo media is 1:1 (`FeedMediaAspect`).
- Media faces are one `TabView(selection: $mediaPage)`; never gate hypes on `is_self`/`isMine`; wire `HypersListSheet`'s `onSelectUser`; one `DashboardMilestoneBar`; Activity labels go inside `profileCard()`; toolbar back = bare chevron.
- Buddy cards share `PostCardView.crewColors`; `WorkoutSplitsSheet(walkers:)` keeps split-less walkers; pace via `DisplayPace`/`Walker.servedPace`; `hasSplits` = anyone has splits.
- Captions follow the face; name links via `MentionText.nameLink`, never nested Buttons; `PostDetailView` always wires profiles.
- On a buddy card the viewer's own slide leads (`myPhotoFirst`), never ahead of the lock.
- A past buddy walk opens `BuddyWalkDetailView` everywhere; nil `finalDistanceMiles` = "not synced"; spin only while `mayStillSync`; `BuddyWalkPhoto.id` = post+user.
- Tune `StreakFlameClock.flameScale(vigor:)`'s table, never add a curve; start `repeatForever` next turn inside `withAnimation`.
- Flamey's blink is a frame toggle; start loops on the next turn; keep `face`'s `.transaction { $0.animation = nil }`.
- One photo prompt, `PhotoPromptView`, for all three doors, previewing the POST itself and reporting one `Outcome`; actions `useSnap` → `camera` → `library`; composer `.cancelled` returns to it; `recoverLostPhotoPrompt` re-offers.
- `FreshPostWindowManager`: gate posting on `canPostToday`, capture only on `isCameraOpen`; `.camera` `photo_source` only for in-session shots; never re-anchor (`anchoredIds`); `syncPostWindow()` only adopts.
- Type backend `timestamptz` as `String` in DTOs; parse with `.withFractionalSeconds` (`BuddyDate`).
- Goal scoring uses `isGoalCompleted(current:goal:)` (clamp goal > 0), never `>= goal` (in-workout alert and competitions excepted); day miles via `countedMiles(onLocalDay:)`.
- The DAY is done at a mile OR 10k steps (`isDayComplete`, `dailyStepGoal`); steps-done reads `StepGoalDayStore.isTodayMet()`, never `todaysSteps`; walks union `StepGoalDayStore`, behind `#if !os(watchOS)` in Watch-member files; celebration/posting stay miles.
- Never use `HKWorkout.totalDistance` for display/sums: use `madDistanceMiles` (tracked floor, `userOverride` wins); sync uploads it too.
- Dedup via `WorkoutDedup.breakdown(in:)` (consent first); grandfather sources by timestamp.
- The tracker's WALK · OUTDOOR descriptor is the distance caption; never back in the top bar.
- `AvatarWithRing` fits inside `size`; paused/stale roster tiles keep their distance (stale: greyscale, `.outOfRange`, `lastHeardAgo`); never send an age as a timestamp.
- Per-day charts take the owner's `goalMiles`, never 1.0.
- A surface drawing the weekly challenge must load it (`refreshIfStale`); `unavailable` is 404 only, else `loadFailed` with retry.
- Use `@Observable` (iOS 17+ Observation framework) for new view models.
- A buddy caption follows the slide (`currentCaption`); `publish` re-resolves a nil workout id; `createAutoPost` sends session + crew.
- Size a dressed Flamey on share cards via `ShareFlameyEnvelope`; reaching items need a row there.
- Profile stats never divide by the streak (`activeDayStats`); each fact has one owner surface; long lists cap at 3 + "See all".
- Show join policy via `BuddyJoinPolicyControl`; read `joinPolicyRaw`, never a closed enum.
- Two friends starting end in one walk (`twinWalk`); follow `merged_into`; never restore invitees.
- Mid-walk invites use `buddy.invite(userIds:)`, never `updateSession`; route `buddy_join_request` like `buddy_joined`; declare `ClientFeatures.buddyJoinRequestV1`.
- Buddy setup is steps of the shared wizard chrome (`BuddyWalkFlowView`), never a sheet/cover; `WizardPalette.accent` is white; extract children from `WorkoutTrackingView`'s body; errors via `buddy.errorMessage`.
- Store/score/sync miles; convert only at the formatter (`DistanceUnits.current`); no bare `"… mi"` literals (widgets keep miles).
- Icon-only controls get `.accessibilityLabel` on the glyph (`.accessibilityHidden(true)` beside text); guard every loop with `accessibilityReduceMotion`.
- Dynamic Type via `.madFont(...)`/`@MADScaledMetric`, capped with `.madTypeCap` below any `.sheet`, never `.dynamicTypeSize`; never scale baked images.
- Every UI change must look right at EVERY iPhone width, 320pt (SE/mini under Display Zoom) to 440pt (Pro Max): no fixed widths summing past 320; flex + `lineLimit`/`minimumScaleFactor`/`ViewThatFits`; mockups show 320, 375 and 440 frames.
- Sharing is one surface, `ShareStudioView`; preview == render (`ShareCardView.render`); cards ImageRenderer-safe; `ShareTemplate.available` decides; empty `MADFacebookAppID` ⇒ system share sheet; mock new cards as HTML first; carousel geometry never depends on `selection` (options reserve the tallest set); a buddy-post share = the on-screen slide + the sharer's own numbers/route (`crewStoryContent`, `coauthors[].workout_id`).
- Weekly recap: Sunday→Saturday; route `weekly_recap` in all four places via `WeeklyRecapLink`; declare `weeklyRecapV1`; reuse `weeklyRecapEnabled`.
- Feature views live in `Views/<FeatureName>/` subdirectories.
- Shared UI components in `Views/Components/`.
- Watch app is a separate target at `Mile A Day Watch App/`.
- Notification taps resolve in `NotificationDestination.from(type:data:)`, presented by `.notificationDestinationHost()`; never in the three tap switches.
- One post opens as `PostDetailView`/`PostDetailLoaderView` via `PostDeepLink`; from a sheet use `openAfterDismiss`; `FeedDeepLink` is for raw workouts only.
- `SaveFriendStreakView` only OFFERS; accept via root-hosted `StreakAssistOfferSheet`; gate on `donation_budget.remaining`; ask on `my_savable_day`; meter text via `assistCaption`.
- A covered today reads `today_covered` on every today surface (`SavedDayStyle`); explain via `SavedTodayBanner` (keep the refund line); keep the flame and countdown live.
- Show who spends each token via `StreakTokenKind.usage` + `TokenUsageBadge`.
- An `EmptyView` body gets no lifecycle: first load in `init`, `.task(id:)` only for reloads.
- Present pick confirmations FROM the `PHPickerViewController` (`ImagePicker.confirmation`), never `picker.dismiss` on confirm; one `ProfileImageCropper`; crop a `.up` copy.
- FRONT & BACK is opt-in (`allowsDual`); `MidRunPhotoStash` is time-bounded, never half-deletes a pair; draw snaps with `DualPhotoFill`; the inset snaps to corners (`dual_inset_corner`); sequential capture, never `AVCaptureMultiCamSession`; every dual save via `DualPairStore.saveToCameraRoll`, and `WorkoutPhotoImportResult` consumers handle `.acceptedPair`.
- Dual: `pickedImage` large, `dualSecondary` inset; every photo-replacing path calls `clearDual()`; one `DualPhotoLayout`; never bake the swap glyph.
- Post stickers are `PlacedSticker`s drawn ONLY by `PostStickerView` (editor `StickerEditorLayer`, baked `PostCanvas`); one per `PostStickerKind.Slot`; per-view sets via `layer(frontView:)` (`separateViewStickers`, reset in `clearDual()`); the route sticker comes from `RoutePrivacyTrim.shareable` behind `hasRoute`.
- Track a cover's real state (`trackerOnScreen`) and reset dropped ones (`reconcileDroppedTrackerPresentation`).
- Composer covers: `.fullScreenCover(item:)`, one-shot `onAppear` guards, two covers on two nodes.
- Celebration order is `CelebrationManager.priority`, enforced by `setObscured` + `holdForGoalSequence`; photo prompt last; buddy recap after the queue (`presentBuddyRecapWhenCalm`).
- Buddy readiness: guests answer both choices (`setMyChoices`); `choicesConfirmed` gates every hand-off; activity is per person (`BuddyParticipant.activityType`).
- `refreshBadgesFromServer`: ≤3 (`individualBadgePopupLimit`) popups for today, else one batch; backfills are one `.badgeBatch(retroactive: true)`.
- Auto cards are data (`mediaUrl: nil`, `ClientFeatures.liveAutoCardV1`); read `PostItem.photoURL`, never `mediaURL`; never upload generated cards.
- `withAnimation`-driven dressed-Flamey views must be `Animatable` (`ReignitingFlameView`).
- Host celebrations once at root; stamp one-shots at dismissal (`markConsumed`); flip `hasFreshTodaysDistance` in the same main.async as the data; share `dailyMileWorkoutId()`.
- Mid-walk join never starts/stops a workout or resets distance; fetch in `BuddyJoinOfferModifier`; route buddy pushes in all four places via `requestOpenBuddySession`; never open a `cancelled` walk.
- Persist `buddySessionId` on the workout and re-adopt on relaunch; report progress from location callbacks; `isPaused` has no default; own tile uses `myPause`; persist a failed finish (`MAD_BuddyPendingFinishV1`).
- One post per buddy walk is server truth (`recap.post`); handle `APIError.buddyWalkAlreadyPosted`; exclude the author by identity, not `my_photo_added`; `FeedEntry` carries `coauthors`.
- Buddy posts carry a device-resolved `buddyWorkoutId`; `PostedWorkoutRegistry` never gates `autoPostMile`; `resolvePhotoPrompt(forWorkout:)` purges the queue; coauthors = active OR finished.
- Buddy choices live in `BuddyLobbyView`; never hardcode `selectedLocationType = .outdoor` (per participant `buddy.myLocationType`).
- Host celebrations once at root; tracker one-shots persist in `InProgressWorkoutStore`; pre-arm `hasSentGoalAlert` only on create.
- Keep GPS noise gates; `liveDistance` = ratcheted max(GPS, pedometer), saved verbatim; celebrate at the full goal; floor displays (`milesFloor2`), ceil remaining; divide moving time only via `DisplayPace`; on pause never `stopUpdatingLocation()`, subtract `excludedPedometerMiles`; `pauseIntervals.last?.end == nil` is a trap.
- Linked post stats come from that `HKWorkout` (anchor = `dayRollupStats`); never bake `currentUser.streak` (use `UserManager.freshBackendStreak`).
- `setNotificationCategories` replaces the set: pass every category (`FRIEND_ACTIVITY` + `FRIEND_REQUEST`); action handlers never use view-owned services.
- Render in-sheet action feedback inside the sheet; park cold-launch intents on `DeepLinkRouter`, consumed in `.task` AND `.onReceive`.
- Pair `.onChange(of:count)` badges with an explicit set after refresh.
- iOS 26 toolbar pills: `.sharedBackgroundVisibility(.hidden)` on the `ToolbarItem`; `.fixedSize()` toolbar HStacks.
- Overlap via padding, never `.offset`; never `.fixedSize` a data label; fit rows via `ViewThatFits`; gate hype/report/block on `PostCardView.isMine`, not `is_self`.
- `ios.yml` diffs `github.event.before..HEAD` on push (never `HEAD^`); `workflow_dispatch` always type-checks.
- CI only type-checks the app module: run `xcrun swiftc -typecheck -sdk $(xcrun --sdk iphoneos --show-sdk-path) -target arm64-apple-ios17.0` over the WHOLE module in one call; `-parse` is not enough.
- `DashboardView.body`'s modifier chain is at Xcode's type-check time limit: never add another `.onChange`/`.onReceive` closure to it (CI's `swiftc -typecheck` still passes); observe from a helper or a service.
- New Codable field: check for explicit `CodingKeys` first; persisted models' new fields must be Optional.
- Target iOS 17.0: resolve newer SF Symbols at runtime (`UIImage(systemName:) != nil ? new : old`).
- Link third-party apps only by App Store id (`itms-apps://apps.apple.com/app/id<N>`, `openAppStore`); never custom URL schemes.
- History import writes backdated `HKWorkout`s; Strava CSV: later columns, UTC dates; dedupe via `ImportedWorkoutRegistry` + `MAD_import_key`; never `HKMetadataKeyWasUserEntered`.
- Stage finished walks in `PendingWorkoutSaveStore` (`PendingWorkoutSaver.retryIfNeeded()`); keep `MAD_tracked_session` on every save path.
- Periodic tracking work (watchdog, `LivePresenceService.tick()`, `WorkoutLiveActivityKeepAlive.beat`) rides location callbacks, never view timers; in-workout toasts render inside the tracker.
- Throttle `InProgressWorkoutStore` writers; never auto-present the tracker from a background launch; read the store before `markEnded()`.
- Keep all three liveness layers (watchdog, `staleDate`, banners); never cap `Text(timerInterval:)` width (`LiveTimerText`).
- Stealth: the server decides; every path sending the local trace off-phone asks `StealthModeStore`; `StealthModeView` owns the PUT; `saveAndApply` never sends stealth keys.
- `CalorieLedger` counts workout kcal only, estimates missing energy, dedups per local day; Treats are opt-in; copy equivalence-only (1.4.3); declare alcohol references in the age rating.
- `GhostCoach` goes silent on calls read from the audio route (`callIsUp`: `.builtInReceiver`/`.bluetoothHFP`), bailing before `activateSession()`; buzz via `AudioServicesPlaySystemSound`; NEVER `import CallKit` in any target (China, Guideline 5).
- Voices: rank legacy/formant voices DOWN, never filter; `usingBasicVoice` is an offer.
- One `GhostCoach.enabledKey`; muting still publishes `lastLine`; never `AVSpeechSynthesisVoice(language: Locale.current.identifier)`, rank by `.quality`; goal milestones measure the DAY.
- Per-walk opt-ins in `@AppStorage` store the session id they're for, never a Bool (`BuddyGhostArming.armedSessionKey`/`isArmed`); consume at hand-off.
- `PostComposerView.init` resolves buddy context for every door (`buddySessionForWorkout`, `lastFinishedSession` fallback); stashed snaps are `.library`.
- Shoes are private (never on friend profiles/posts/shares); defaults per `ShoeActivity`; pickers pass the activity.

## Mile A Day+
Details: docs/conventions/ios.md § Mile A Day+
- Entitlement is the server's (`PlusStore.status`); never unlock from a local StoreKit check; `finish()` a transaction only after the server's `results[i]` says ok or `retryable: false`.
- Purchases pass `.appAccountToken` (`PlusStore.appAccountToken`); product ids live in `PlusProducts` (mirrors backend `PLUS_PRODUCTS`).
- The paywall sells only shipped perks (`PlusPerk`); prices/periods come from `Product`, never literals; keep Restore + Terms + Privacy + the renewal line beside the button (3.1.2).
- Plus-only Flamey items use `FlameyUnlock.plus` and are granted only by the server's `owned_item_ids`.
- Paywall layout follows `PlusPaywallView.Layout`: onboarding = A/B arm (`PlusPaywallVariant.current`, mirrors server `paywallVariantFor`), tokens/at-risk = `.streak`, Closet = `.closet`, Settings = `.flamey`; log views via `PlusTelemetry`; `PlusStreakCard` hosts its sheet on the always-present VStack.
- Preview a Plus look via `PlusLookShowcase.look(_:)` (fixed non-holiday date, no signup date); founders read `status.source == "founding"` → `FoundingRunnerCard`; token numbers in `PlusTokenComparison` mirror backend targets.
- Monthly Flames are `color` items with `FlameyUnlock.month(n)` (server-granted); their art is palette + `FlameyMonthlyFX` INSIDE his outline (never a new silhouette) plus a bare-tip crown (`FlameyArt.monthCrown`, counted in `crest`); progress comes only from the closet's `monthly_flames` (`FlameyMonthlyStore`).

## Auth / Session
Details: docs/conventions/ios.md § Auth / Session
- "Who am I" = the token's `sub` (`TokenUtils.subject`); `SessionIdentity.enforce()` catches drift; never blanket-sign-out on 403.
- One Apple ID = one MAD account (signin resolves by email); tell users to use separate Apple IDs.
- `isAuthenticated` is not proof; never persist a tokens-missing downgrade; `MADWatchBridge` withholds mismatched creds.
- Background callers of `APIClient.fancyFetch` gate on `TokenStore.hasTokens` first.

## Do NOT
Details: docs/conventions/ios.md § Do NOT
- Hand-edit `.entitlements` without enabling the capability on the App ID (AMFI kills at launch).
- Change the API base URL without coordinating both client and server.
- Modify `project.pbxproj` or create Watch-target files; keep dual-membership files (HealthKitManager.swift, CelebrationManager.swift) dependency-free; check with `xcrun swiftc -typecheck -sdk $(xcrun --sdk watchos --show-sdk-path) -target arm64_32-apple-watchos10.0 <file>`.

## App Store Review Compliance
Details: docs/conventions/ios.md § App Store Review Compliance
Every change must pass App Review. Check BEFORE proposing and AFTER implementing. Flag any borderline item explicitly.

- **Private APIs / SPI**: no underscored selectors, no `dlopen` of system frameworks, no swizzling Apple classes. (2.5.1)
- **Permissions & purpose strings**: every new HealthKit/Location/Notifications/Contacts/Camera/Photos use needs a clear `NSUsageDescription`; don't request unused data. (5.1.1)
- **HealthKit specifics**: no HK data in iCloud or ads; request only types used. (5.1.3)
- **Background modes & BGTask**: declare only modes the feature needs; no keeping the app alive for tracking.
- **Account/data deletion**: account creation requires in-app deletion. (5.1.1(v))
- **Sign in with Apple**: required if any third-party social login is added. (4.8)
- **Payments**: digital goods = StoreKit/IAP only, no external payment links; physical = Apple Pay or other. (3.1.1, 3.1.3)
- **Push notifications**: no ads/marketing without opt-in; friend notifications user-controllable. (4.5.4)
- **UGC / social**: competitions + friend features need reporting, blocking and a moderation/EUA path. (1.2)
- **Health & safety claims**: no unfounded medical claims; "mile a day" framing is fine. (1.4.1)
- **Kids / age**: not in Kids Category; don't target under-13s.
- **Web views & external links**: no linking out to purchase flows; in-app browsers = SFSafariViewController or WKWebView.
- **Entitlements**: add capabilities only with a shipping feature; never remove ones a feature depends on.
- **Copy & metadata**: no beta/test mentions, placeholder text or other-platform references.
- **Assets**: icons/screenshots match shipped UI; no Apple trademarks or hardware mockups.
- **Privacy manifest (`PrivacyInfo.xcprivacy`)**: update it for any new SDK or data collection.

When in doubt: cite the guideline number, propose the compliant path, and ask before shipping.
- Lane crew lines in screen space (`RouteLaneOffset`); legend chips are buttons (`highlightedRouteId`); author route ships on every post read.
- The challenge grid draws today from `todayChallenge` and refetches history once per open.
- Throttle Flyover overlay invalidation by time; odometer base recomputed from the leg index.
- Every dashboard card below the day's cards is switchable, stored per style (`dashboardCardsFunV1`/`ModernV1`); mount `DashboardCustomizeRow` after the style `switch`.
- Flamey: one look via `FlameyLook.resolve(...)` (owning never dresses him); six shared files stay BYTE-IDENTICAL in `Views/Components/` and `MileADayWidgets/` (cp + cmp); no control in the hero's top-left; the Closet edits a draft (`saveDraft`); bubble anchors at `FlameyArt.crest`.
- Build a figure's palette (body, arms, legs, glow) from `FlameyLook.figurePalette`, never `FlameyPalette.palette(for: look.color)`: a whole-body costume (`skeletonSuit`) skins his limbs.
- Workouts rows draw their own map (`WorkoutRoutePreviewCard`); the host list reads `WorkoutRouteCache` and passes traces in.
- Pause gaps are cut at DRAW time by `RouteGaps` (`resume()` still nils the anchor); gaps add zero length; clock via `collapsingGaps`.
- `RouteArtView` is the default route face; routeless ⇒ `IndoorWorkoutCard`, never labelled "indoor" (`RoutelessCardStyle.resolve`); feed motion transform-only, no `TimelineView` in cards.
- Flyover clock is map arc length (`cumulativeMap`), never `stats.distance`; keep `MKHybridMapConfiguration(elevationStyle: .flat)`; frame the FOLLOWED rider; never start the display link in `attach`; `flyablePeople` order = engine order.
- Stored Combine-typed properties need an explicit `import Combine`.
- Mark off-main View statics `nonisolated`; representables never emit state writes during view update (`FlyoverEngine.inViewUpdate`).
- `is_indoor` nil = unknown (routeless is never "indoor"); `ActivityCardView.verb/icon` infers Walk/Run display-only; `backfillMissingRoutes` heals routeless history.
- Snapshots go through `RouteMapSnapshot.generate`, never bare `MKMapSnapshotter`; Reduce Motion renders finished frames; nothing user-facing depends on `TelemetryService`.
- `FlyoverLaunch.forPost` is the one post→launch builder (reads `routeCoordinates` raw, as must `canPlayFlyover`); OG images stay decorative.
- Timed Flyover is all-or-nothing per flight; camera/odometer take the followed rider's ARC; sync times from the same `SimplifiedRoute` as the points.
- Detect timed finishes in `moveRiders` (`finishedFlags`); `backfillRouteClocks` runs after `backfillMissingRoutes`.
- Every "open the tracker" door goes through `DeepLinkRouter.requestOpenTracker` → `TrackerLaunchModifier`; `StartMileIntent` stays dependency-free; `HowFarTodayIntent` never says 0 on a stale day.
- Open competitions via `pendingCompetitionId`, consumed in `.task` AND `.onReceive`.
- A competition reaches a post only via the opt-in sticker; chips need `viewer_in == true`; sheet hosts use `requestOpenCompetitionAfterDismiss(id:)`.
- Route privacy trimming is server-side; `RoutePrivacyTrim` mirrors it only for owner hints and shares; prefs readers call `RoutePrivacySync.adopt`.
- Gate flyover chips on `is_self || flyover_allowed != false`; share chips own content only.
- Constant labels in squeezed rows get `.lineLimit(1).fixedSize(...)`; hosts fit via `ViewThatFits` sharing one `@ViewBuilder` (`mediaControlChips`).
- A crew slide shows its owner's caption or none; edit via `EditCaptionSheet(subject: .myCollabSlide)`; `setCrewCaption` ≠ `onEditCaption`.
- Highlights hold post + face; key `ForEach` on `PostHighlightItem.id`, never `post_id`; `canHighlight` must not reuse `canCurateOnProfile`.
- Never open the lobby over a recording walk (`BuddyWalkRouting.openTarget()`); "am I walking" = `InProgressWorkoutStore.load()?.isActive`; "Start now" is host-only `startNow()`.
- Locks are `OSAllocatedUnfairLock`, never `NSLock`, for anything a main-thread view body can take while background queues also take it (`DayKeyFormatter`, `TrackedWorkoutLedger`, `InProgressWorkoutStore.cacheLock`). `NSLock` is a default pthread mutex with NO priority inheritance: in a backgrounded app a throttled utility thread descheduled while holding it left the main thread parked in `__psynch_mutexwait` under a SwiftUI body, and the background scene-update watchdog killed it (0x8BADF00D "stuck (deadlock)", ~0% app CPU) — the main-app SIGKILL group in builds 573/595. An unfair lock boosts its owner.
- Never nest a Button in a Button's label; overlay controls as ZStack siblings.
- Rank via `Competition.ranked`/`standing(for:)` (score → distance → name → user_id); never a place from an index.
- Compete UI uses `CompeteDesign`; no materials/gradients; arm reveal flags in the shared table.
- Team comps show no per-person score; person rows use `CompeteStandingsMetric.contribution`; branch on `isTeam` when reading `standing(for:)`.
- Mark ties on every tied row; keep the tiebreak identical to server `rankCompetitors`; trust `competition.winner`.
- Keep headers and cards direct children of `LazyVStack`; precompute per-row data in @State, never in `body`; memoise `RelativeTime.date(from:)`.
