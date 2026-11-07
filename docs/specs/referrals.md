# Referrals

Status: built, not released. Lifetime Plus is switched off until App Review confirms how it can be delivered.

## How it works

1. A new user chooses "Friend or family" at sign-up and picks a real account from search. Free typing can't create a referral. Anyone who skips it can add it from Invite friends during their first 14 days.
2. The link stays pending until the friend walks at least `STREAK_QUALIFYING_MILES` on 7 different days within 30 days, on device-measured workouts.
3. An hourly job marks it qualified, pays out rewards and tells the referrer.

A referrer sees only a friend's first name, photo and days toward qualifying. The friend is told this when they pick them.

## Existing users

Friends named before this feature, and on old app versions, are linked hourly by `linkTypedReferrals`. A typed name must match one real account or an admin alias. The referrer must have joined first, blocked pairs stay apart, and "Someone from the team" doesn't count. Those friends follow the same rule from their sign-up date: 7 days in their first 30. They all appear on the Referrals screen, including ones who didn't reach 7 days, and backfilled credit arrives without a push.

## Rewards

| Referrals | Reward | How it's delivered |
|---|---|---|
| 1 | Trail Buddy medal, for both people | Automatic |
| 3 | Streak Assist | Automatic |
| 5 | Trail Guide Hat, a referral-only Flamey item | Automatic, through a medal |
| 10 | A year of Mile A Day+ | Apple offer code, claimed in the app |
| 15 | Streak Assist | Automatic |
| 25 | Lifetime Mile A Day+ | Hidden until `REFERRAL_LIFETIME_ENABLED=true` |
| 50 | Pathfinder Flamey, the rarest form | Automatic, through a medal |

Someone who already has Plus keeps the free year unclaimed for later.

## Apple

Guideline 3.1.1 says apps may not use their own mechanisms to unlock paid features. Apple's subscription page lists offer codes for a member referral program, so the free year uses them.

Before launch:

- Create an offer for a free year of `mad.plus.yearly` in App Store Connect, confirm a year is allowed, and download one-time codes.
- Load them with `node scripts/load-offer-codes.mjs codes.txt`. Claims fail with a contact-us message when none are left.
- Ask App Review in writing how a lifetime reward can be delivered. Lifetime is a non-subscription purchase, and Apple's text gives no route for it.

An offer code renews at the regular price after the free year unless cancelled, and the app says so beside the button.

## Support

Invite friends and Help & support both open an email to support@mileaday.run, prefilled with the user's account. There's no admin screen yet: linking a referral by hand means inserting a `referrals` row.

## Checks

`backend/scripts/referral-check.mjs`, in CI.
