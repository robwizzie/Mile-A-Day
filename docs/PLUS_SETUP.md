# Mile A Day+ — launch checklist

Everything outside the code that has to be set up before Mile A Day+ can sell.
The code (backend ledger + iOS StoreKit 2) is in place; none of it charges
anyone until the products below exist in App Store Connect.

## 1. App Store Connect — products

Agreements, Tax, and Banking must be active (Paid Apps agreement) first.

Create these with **exactly** these product ids (they are hard-coded in
`backend/src/services/plusCatalog.ts` and `app/Mile A Day/Services/PlusStore.swift`):

| Product id | Type | Suggested price | Notes |
|---|---|---|---|
| `mad.plus.yearly` | Auto-renewable subscription | $29.99 / year | Introductory offer: **Free trial, 1 week**, new subscribers |
| `mad.plus.monthly` | Auto-renewable subscription | $4.99 / month | No trial |
| `mad.plus.lifetime` | Non-consumable | $79.99 | "Pay once, Plus forever" |
| `mad.plus.gift.year` | Consumable | $29.99 | "A year of Mile A Day+ for someone else" |

- Put both subscriptions in **one subscription group** ("Mile A Day+"), yearly
  ranked above monthly, so switching plans is an upgrade/downgrade rather than
  a second subscription.
- **Family Sharing**: turn it ON for `mad.plus.yearly`, `mad.plus.monthly` and
  `mad.plus.lifetime` (the paywall promises it). Leave it off for the gift.
  This can't be turned off again once on.
- Each product needs a display name, description and a review screenshot of
  the paywall (Settings › Mile A Day+ › See plans).
- Enroll in the **App Store Small Business Program** (15% instead of 30%).

## 2. App Store Connect — app settings

- **App Store Server Notifications (Version 2)** — Production AND Sandbox URL:
  `https://mad.mindgoblin.tech/store/apple/notifications`
- **App Privacy**: add "Purchases → Purchase History", linked to the user,
  used for App Functionality (matches `PrivacyInfo.xcprivacy`).
- **License agreement / Terms of Use**: the app links `https://mileaday.run/terms`
  from the paywall. Make sure that page covers subscriptions (auto-renewal,
  cancellation, refunds via Apple) — or add Apple's standard EULA link to the
  app description. App Review checks for a Terms of Use link in BOTH the app
  and the metadata (Guideline 3.1.2).
- The first in-app purchases must be submitted **together with a new app
  version** (select them on the version page before submitting).

## 3. Backend environment (Coolify)

| Var | Value |
|---|---|
| `APPLE_APP_ID` | The numeric Apple ID of the app (App Store Connect › App Information), e.g. `6746970905` |
| `APPLE_BUNDLE_ID` | Optional — defaults to `APNS_BUNDLE_ID` |
| `APPLE_ROOT_CERTS_DIR` | Optional — a folder of Apple root `.cer` files; unset = fetched from apple.com on first use |

Without `APPLE_APP_ID`, production purchases answer 503 `store_not_configured`;
the app keeps them unfinished and re-posts on the next launch, so nothing is
lost — but nobody gets Plus until it's set. **Deploy the backend before the
app version that sells Plus.**

## 4. Founding Runners

Every account created before `FOUNDING_CUTOFF` (`2026-10-15T00:00:00Z`) is
Plus free through `FOUNDING_ENDS` (end of 2027) — no data is written, it's
derived from `users.created_at`. Accounts created after the cutoff (the ad
traffic) see the trial offer once at the end of onboarding.

## 5. Testing

- **Xcode**: File › New › File › StoreKit Configuration File, "Sync with App
  Store Connect" (or add the four products by hand), then Edit Scheme › Run ›
  Options › StoreKit Configuration. Local StoreKit transactions are only
  accepted by a backend running with `NODE_ENV=development`.
- **TestFlight / sandbox**: real Apple signatures, accepted by production
  (App Review uses sandbox too). Sandbox subscriptions renew every few
  minutes, which exercises the renewal + notification path.
- **Backend**: `cd backend && node scripts/plus-check.mjs` (part of CI).
