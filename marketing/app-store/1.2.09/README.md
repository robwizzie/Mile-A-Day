# App Store assets for 1.2.09

iPhone screenshots plus the product page header and search results creative assets. The iPhone Duo set is a separate deliverable on its own branch (`docs/duo-screenshots/app-store`) and uses the same order, copy and colour per slide.

## iPhone 6.9" screenshots (`iphone-6.9/`, 1320×2868, PNG, RGB)

Upload in this order. Only the first three show in search results.

| # | File | Label | Headline | Line |
|---|---|---|---|---|
| 01 | `01-streak-1320x2868.png` | Daily streaks | Walk or run a mile. Every day. | Build a streak that keeps you moving. |
| 02 | `02-unlock-1320x2868.png` | Run to unlock | Earn your feed. | Friends' stories and photos unlock once you walk or run your mile. |
| 03 | `03-flyover-1320x2868.png` | Route flyover | Relive every route. | Replay your walk or run from above, step by step. |
| 04 | `04-friends-1320x2868.png` | Friends | Keep each other going. | See who's out now, nudge friends, and donate a mile to save a streak. |
| 05 | `05-closet-1320x2868.png` | Flamey's closet | Dress up your Flamey. | Name him, dress him up, and unlock new looks with every medal. |
| 06 | `06-buddy-1320x2868.png` | Buddy walks | Never walk alone. | Walk with friends, and see each other's routes when you both share. |
| 07 | `07-milestone-1320x2868.png` | Milestones | Celebrate every milestone. | Day 100, 365, 500. Each one gets its moment. |
| 08 | `08-comp-1320x2868.png` | Competitions | Compete with your crew. | Team comps, clashes and leaderboards. |
| 09 | `09-tokens-1320x2868.png` | Streak tokens | Miss a day? Stay on track. | Tokens protect your streak when life happens. |

Slide 06's line describes the opt-in route sharing on buddy walks that ships in 1.2.09. If that feature is pulled from the release, change the line back to "Walk or run with friends, together from anywhere." before uploading.

## Product page header (`header/`)

- `MAD-header-3840x1646.mp4`: 21:9, 3840×1646, 30 fps, H.264 + AAC, 29.4 s seamless loop with an original music bed (no licensing). Pages: streaks → run to unlock → route flyover → friends → dress up Flamey.
- `MAD-header-3840x1646.png`: the still version (first page), for use if the video is rejected.

## Search results (`search-results/`)

- `MAD-search-2880x1920.mp4`: 3:2, 2880×1920, 30 fps, H.264, 17 s seamless loop, silent track (search results are always muted). Pages: streaks → run to unlock → route flyover → dress up Flamey.
- `MAD-search-2880x1920.png`: the still version (first page).

Upload this as its own Search Results asset. Don't tick "Use header asset in search results": the search cut has bigger type and fewer pages for the small tile.

## Notes

- All app screens are real captures with the status bar redrawn as 9:41, full signal and full battery. Friends shown have agreed to appear.
- Headline font is Inter Display (a stand-in for SF Pro Rounded, which couldn't be downloaded in the build environment).
- Before publishing, use Preview in App Store Connect to check that the app name and Get button don't cover the header's headline.
