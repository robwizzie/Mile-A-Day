# Mile A Day: marketing screenshot brief

Handoff for the marketing chat. Everything here was checked against the app's code (read-only; no code was changed). The screenshots in this folder were captured from the live app via iPhone Mirroring on Oct 12, 2026, from the account `@rob`: 512-day streak, 79/104 medals, Fun dashboard style.

## Read first

- **Resolution.** The captures are 804×1766 and include the rounded mirroring frame. That is fine for ad mockups, the website and reference. **App Store screenshots need native captures** (side button + volume up on the phone, 1320×2868 on a 6.9" iPhone). Use these files as the visual target and recapture natively.
- **Scrolling.** iPhone Mirroring would not accept automated scrolling, so every capture below shows the top of its screen. Section C lists the shots that need a scroll or a real-world situation; they take a human about 10 minutes.
- **Light Mode does not exist.** The app forces dark mode everywhere (`Mile_A_DayApp.swift:31`, `.preferredColorScheme(.dark)`), so switching iOS to Light changes nothing. Only the splash and sign-in screens were ever designed for light. Don't plan light-mode assets.
- **Privacy.**
  - `profile.png` shows Rob's real avatar (a photo of a child) and his bio. Use a test persona or blur the avatar before publishing.
  - Feed, Friends, Compete leaderboards, Buddy Walk and the weekly recap's friends card all show real friends' names and photos. Use consenting test accounts.
  - The Streak, Flamey, medal and celebration screens show no names or photos.

---

## A. What's in this folder

| File | What it shows | Use for |
|---|---|---|
| `dashboard-fun.png` | Fun dashboard: Flamey in nightcap and shades with a dragon companion, **512 DAY STREAK · BEST EVER · 3 SAVERS**, 1.86 mi today, START MILE, Medals 79/104 | Hero / App Store #1 |
| `celebration-daily-a-flame.png` | The daily goal celebration starting: Flamey igniting on black | Ad frame, "the moment" |
| `celebration-daily-b-final.png` | Celebration final frame: **BLAZING · 512 Day Streak · "Your flame is absolutely roaring."**, stats, next milestone (88 days to Day 600), 3 Streak Tokens ready | Ad / App Store "finish" shot |
| `share-studio-flamey-mile-done.png` | Share Studio, card **"Mile done."** (Flamey · Mile done) | Share-feature shot |
| `share-studio-streak.png` | Share Studio, **Streak** card (512 DAY STREAK) | Social post |
| `share-studio-bold-streak.png` | Share Studio, **Bold streak**: "A MILE A DAY FOR 512 days straight." | Social post / website |
| `share-studio-flamey-still-lit.png` | Share Studio, **"512 days. Still lit."** | Social post |
| `medals.png` | Medals screen: 75% ring, 79 of 104, 4 Legendary / 35 Rare / 40 Common | Medals shot |
| `medal-detail-500.png` | **Elite Runner**, Legendary gold medal, "500 day streak!", how earned (Sep 24, 2026), unlocks Prism for Flamey | Medal shot |
| `profile-badges-showcase.png` | Profile → Badges showcase (Elite Runner, Quick Runner, Half Marathon). **Avatar privacy**, see above | Profile shot (blur avatar) |
| `profile.png` | Profile: banner, GOAL DONE ring, Streak 512 · Miles 879 · Friends 49, Streak Tokens, Last 7 Days chart | Profile shot (blur avatar) |
| `widget-streak-flame-medium.png` | Streak Flame widget, medium (sleeping Flamey, 512, Done · STREAK SAFE) | Widget asset |
| `widget-streak-count-small.png` | Streak Count widget, small (green ring, 512, Streak safe) | Widget asset |
| `homescreen-with-widgets.png` | The whole Home Screen. It includes other apps' icons, so crop or rebuild it | Reference only |
| `celebration-365-a-calendar-day365.png` | 365 replay: calendar card landing on **DAY 365 of 365** (slightly faded, it's the instant before it flips) | Day 365 ad, frame 1 |
| `celebration-365-a2-calendar-counting.png` | 365 replay: calendar mid-count (digits in motion) | Day 365 ad, alternate |
| `celebration-365-b-legendary.png` | **STREAK COMPLETE · 1 YEAR · "365 days. A full year. Legendary."** with confetti and fireworks | Day 365 ad hero |
| `celebration-365-c-final.png` | Final screen: 879 MILES · 365 DAY STREAK · BEGAN 5/13/25, **Share This Win** / Keep Going | Day 365 ad, end frame |
| `medal-detail-365.png` | **Year Warrior**, Legendary, "You reached a 365-day streak · May 12, 2026", unlocks Gold for Flamey, Share / Replay | Medal shot |
| `share-365-milestone-in-studio.png` | Share Studio on the **Milestone** card: "STREAK MILESTONE · DAY 365 · One full year." A clean 1080×1920 PNG of this card is also saved in the phone's Photos | Social / website |

---

## B. Prompt-by-prompt answers

### 1. The Day 365 celebration (medal replay)

**Taps:** Dashboard → **Medals** tile (beside Steps, under START MILE) → **Streaks** filter chip → scroll to **Year Warrior** (`streak_365`, Legendary) → scroll the detail screen down to the two capsule buttons **Share** and **Replay** → tap **Replay**.

Shortcut: pin Year Warrior to the Profile → Badges **Showcase**. Then Profile → Badges → tap it. Elite Runner (500) is pinned there today.

**What it plays** (YearlyMilestoneCelebrationView, gold palette, plays automatically, no taps needed):

| Time | On screen | Shoot? |
|---|---|---|
| 0–1.4 s | Golden rays fade in on dark brown/gold | |
| 1.4 s | **Calendar flip card**: "DAY [n] of 365", racing 1 → 365 with 3D page tilts | **Shot A at about 2.5–3.4 s** |
| ~3.45 s | Lands on **DAY 365 of 365** | |
| ~3.85 s | Flips to **STREAK COMPLETE** pill, giant gold **1 YEAR**, and **"365 days. A full year. Legendary."** | |
| 4.5 s | Confetti, fireworks and a shimmer across "1 YEAR" | **Shot B at about 4.5–5.5 s** |
| 6.0 s | Stats card slides up: **[lifetime miles] MILES · 365 DAY STREAK · [date] BEGAN** | |
| 6.5 s onward | Buttons **Share This Win** (gold) and **Keep Going**. Stays until tapped | **Shot C, the final screen** |

A small "Skip" pill sits top-right from about 1.7 s. A screen recording, with frames pulled from it, beats timing three screenshot presses.

**Privacy:** no name, photo, friends or map. It shows only lifetime miles (today's total, not the total on the day of the milestone), "365" and the start date. There is no "REPLAY" label on the 365 view, so it looks like the live moment.

**100 and 500 days** also have Replay (StreakMilestoneCelebrationView):

| | 100 days, "Century Club" (Rare) | 500 days, "Elite Runner" (Legendary) |
|---|---|---|
| Palette | Platinum | Gold |
| Subtitle | "Triple digits! You're in the elite!" | "Half a thousand! Absolutely incredible!" |

- **Eyebrow:** reads **"REPLAY · SEP 24, 2026"**, not "STREAK MILESTONE".
- **Timeline:**
  - 1.0 s: the counter "DAY n of 100/500" starts. Best flip shot at **2.0–3.0 s**.
  - ~3.55 s: giant number, "DAY STREAK" and the subtitle.
  - **4.1–5.0 s:** confetti and fireworks. Best hero shot.
  - ~5.3 s: "MEDAL EARNED · Elite Runner" chip and stats (DAYS · BEGAN · REACHED).
  - From ~6.3 s: buttons **Share your streak / Done**.
- **Reduce Motion:** with it ON in iOS Settings, the 100/500 view jumps straight to a clean final frame. Turn it OFF to get the animation. The 365 view always animates.
- Other streak medals without a Replay: 45, 60, 90, 120, 180.

### 2. Core feature screens, ranked by how well they show what's different

1. **Dashboard, Fun style** ✅ captured (`dashboard-fun.png`).
   - Path: Launch → Dashboard.
   - Style switch: Dashboard → bottom → **Customize dashboard** → Look: Fun / Modern. Or the gear → **Dashboard Style**.
   - Best state: long streak (BEST EVER crown), savers held. Before the mile, Flamey waits and START MILE is the call to action; after it, he wears shades.
   - Avoid: friend-request or invite rows, and the "A friend is out — join" pill (both show names).
2. **Buddy Walk.**
   - Path: START MILE → **"Choose Activity Type"** → **With a Buddy** → Who's Coming? → Walk/Run → mode (**Just Together / Shared Goal / Race to Goal / Furthest in Time**) → How Far? → **Lobby** ("Who's here", "Tap to invite", host button "Start together") → "Starting together" countdown.
   - In progress: the roster strip of friends' avatars and miles sits above your ring.
   - Recap: finish → Continue → the **Buddy Walk** recap sheet (standings, "Add your photo"). Re-open later from Profile → Activity → Buddy Walks → a walk → "Recap & post this walk".
   - Needs 2–3 consenting test friends walking at the same time. **Names and avatars are everywhere.**
3. **Friends list, someone "out now".**
   - Path: Friends tab → **Friends** pill → section **CHEER THEM ON**.
   - The row button reads **Join** (friend is in a buddy walk hosted by your friend), **Ask to join** (host isn't your friend) or **Ask to walk** (friend is out solo).
   - Setup: a friend starts tracking and answers the tracker's "Share that you're out?" prompt with **Share when I'm out**.
   - Shows names, avatars and live miles.
4. **Streak Tokens detail.**
   - Path: tap the **3 SAVERS** line on the dashboard hero, or Profile → the **Streak Tokens** row.
   - Sections: Days your tokens saved, Available, How it's used, How to earn, How tokens work, About Pure Flame.
   - Best state: all 3 tokens ready (true today) and a few blue saved days.
   - No other people, except in the Assist sheets.
5. **Mile in progress and finish.**
   - Path: START MILE → Run/Walk → Outdoor/Indoor → **Just Track It** or **Ghost Race** → countdown → tracker (distance, ring, TIME, Stop Workout) → **End Workout?** → End Workout → **WorkoutRecapView** ("MILES THIS RUN", Daily Goal, ghost splits, **Share your walk**, Back to Dashboard) → dashboard goal celebration (see `celebration-daily-*.png`).
   - Best shot: outdoor at about 0.8 mi with the ring nearly full. Ghost Race makes the recap richer.
6. **Flamey's Closet** (Fun style only).
   - Path: dashboard → **Closet** pill under Flamey, or gear → Flamey's Closet.
   - The first open shows a walkthrough; finish it once before shooting.
   - Best state: many items unlocked and an outfit on. No other people.
7. **Route flyover and heatmap.**
   - Flyover: the red **FLYOVER** pill on any route — workout detail (Insights → Recent Workouts → See All → a walk), feed post cards, or a buddy walk detail.
   - Heatmap: Profile → **Stats** tab → **Route Heatmap** (Nearby / All Routes, **Fly my week**).
   - Needs many outdoor GPS routes in one area. Your own routes show no other people.
8. **Feed and Stories.**
   - Path: Feed tab. Stories rail at the top, then Memories, a Weekly recap teaser (Sat/Sun), then posts.
   - Stories unlock only after today's mile.
   - Heavy on friends' names and photos.
9. **Competition leaderboard and Trophy Case.**
   - Leaderboard: Compete tab → **Compete** → Active → a competition (tabs Today / Standings / Flex).
   - Trophy Case: Compete → **History** → Medals shelf → **Trophy case**.
   - Best state: about 5 people with you in first; several finished competitions with gold, silver and bronze.
   - Shows names.
10. **Medals and medal detail** ✅ captured (`medals.png`, `medal-detail-500.png`).
11. **Weekly and monthly recap.**
    - Weekly: Dashboard → **Insights** → This Week chart → **Recap**. Also the Feed teaser on Sat/Sun, or the Saturday 7 PM push. The friends card shows names.
    - Monthly: **there is no manual entry**. It auto-opens once a month on the Dashboard for the previous month. Watch for it on Nov 1, or reinstall the app.
12. **Insights, Profile, Hall of Streaks.**
    - Insights: Dashboard → Insights row near the bottom ("THE ROAD TO n", This Week chart, stats grid).
    - Profile ✅ captured.
    - Hall of Streaks: Profile → Activity, below the fold.

### 3. Share cards

All 19 templates **Save** as clean PNGs with no phone UI:

- **Full story:** 1080×1920, opaque.
- **Sticker:** 960×1200, transparent.
- **How to save:** Share Studio → the round **Save** button (bottom row: Instagram · Messages · Save · More).
- Tapping the side card pages the carousel. The family chips at the top jump between families.

| Family | Cards | Reached from |
|---|---|---|
| Picture | Framed photo, Polaroid, Big number | Only your own **feed post's** Share (needs a photo) |
| Route | Route art, On the map, Route & stats | Workout detail, post-walk recap "Share your walk", feed cards |
| Streak | **Milestone** (milestone days only), Streak, Bold streak | Dashboard hero tap, the celebration's "Share your mile", Profile → Share → "Share my streak" |
| Flamey (Fun style only) | Flamey · Mile done, Flamey · Still lit | Same as Streak |
| Sticker | Stats sticker | Always |
| Week | Your week, Flamey · Your week | Weekly recap → "Share your week" |
| Month | Your month, Day ring, Flamey · Your month | Monthly recap → "Share {Month}" |
| Medal | Medal | Medal detail → **Share** |
| Record | Personal record | Profile → race PRs → share icon |

**Best card for each:**

- **365-day streak:** **Milestone** — "STREAK MILESTONE", a flame ring, "DAY 365", "One full year." It opens automatically from the 365 replay's **Share This Win**. Runner-up: **Bold streak**.
- **Medal:** **Medal** (the hanging medal in its rarity colours). Use the Sticker shape to drop it over a photo.
- **Month:** **Your month** (calendar of lit days; a perfect month turns gold). Use **Day ring** if days are the brag ("30 FOR 30").
- **Buddy Walk:** there is no crew card, because share cards carry only your own route line. Use **On the map**, or a Picture card made from the walk's group photo post.

### 4. Widgets, Lock Screen and Live Activities

**Widgets** (add from the Home Screen: long-press → Edit → Add Widget → search "Mile A Day"):

| Widget | Sizes |
|---|---|
| **Streak Flame** | Small, Medium (Flamey on Fun style, a plain flame on Modern) |
| **Today's Progress** | Medium + Lock Screen circular / rectangular / inline |
| **Streak Count** | Small, Medium + Lock Screen circular / rectangular / inline |
| **Competition** | Medium |
| **Daily Leaderboard** | Medium (shows friends' names) |
| **Start My Mile** | Control (iOS 18+): Control Center, a Lock Screen control slot, or the Action Button |

**States and when they show:**

| When | Widgets show |
|---|---|
| Before 10:00, nothing done | Flamey **asleep** (nightcap, ZZZ) |
| 10:00–17:59 | **ready** |
| Partway through the mile | **halfway**, then **almost** (sparkles from 80%) |
| **18:00 sharp**, mile not done | **AT RISK**: red, Flamey **nervous** with hands on cheeks and a sweat drop, red countdowns, "STREAK AT RISK" |
| Mile done | **done**: shades, green "Streak safe" |
| After 22:00 and done | **bedtime** |
| Milestone day (7, 30, 100, 365, 500…) | **party** hat and confetti |
| Streak 0 | a sleeping **coal** |

The captured widgets show "done" late in the evening.

**Live Activities:**

- **Workout Live Activity**
  - Starts when you START MILE on the iPhone; the Watch app doesn't start one.
  - Lock Screen: distance, Flamey, a ticking clock, pace and a progress ring.
  - Dynamic Island: compact (icon + progress ring), and expanded on long-press of the pill.
  - At the goal, the **"Mile complete! 🔥 / Your streak is safe for today."** alert pops.
  - Best captures: about 0.75 mi (sparkles) and just after 1.00 (green).
- **Streak Risk Live Activity**
  - Appears after **18:00** with the mile not done and a streak above 0, when you **leave the app**.
  - Shows a worried Flamey, "Day N on the line", "0.58 mi keeps it alive", a big red countdown to midnight and a **Start Mile** button. The Island shows a red flame and "5h".
- **How to capture:** lock the phone for the Lock Screen version; go to the Home Screen for the compact pill; long-press the pill for expanded.

**Home Screen hero layout:**

- Top: Streak Flame **medium**.
- Middle row: Streak Flame **small** next to four icons, or Streak Count small.
- Below: Streak Count **medium** (week dots) or Today's Progress medium (with the red Start Mile button).
- Dark wallpaper; Mile A Day in the dock.
- **Lock Screen:** Streak Count circular + Today's Progress rectangular + inline "N day streak".
- **Timing:** about 2 PM half-done for orange; just after finishing for all-green; 6–9 PM undone for the red "at risk" look plus the Lock Screen countdown.

### 5. Apple Watch

| Screen | What it shows |
|---|---|
| **Home** | "Good morning/afternoon/evening, [name]", a pulsing ring "0.42 / 1.0 mi", a streak pill, **Start Run** / **Start Walk**, an Outdoor/Indoor toggle |
| **Countdown** | 3 · 2 · 1, "Get ready" |
| **Tracking** (swipe or Digital Crown between pages) | 1. Ring with big miles and "0.58 mi to goal"; green **"✓ Goal complete!"** once the *day's* total passes the goal. 2. **Stats**: Time, Pace, Heart bpm, Cal. 3. **Controls**: pause, stop |
| **Recap** | **"Goal Complete!"** or "Great Walk!", distance, Duration, Avg Pace, Avg HR, Calories, Done |

**Best moments:** Home before starting; mid-mile page 1 at about 0.5 mi; Stats page once heart rate shows; page 1 just after crossing the goal; the Recap card.

**How to take a Watch screenshot:**

1. iPhone Watch app → General → turn on **Enable Screenshots**.
2. On the watch, press the **side button and Digital Crown together**.
3. The image lands in the iPhone's Photos.

### 6. Notifications (Lock Screen ads)

**Exact copy of the best ones:**

| Notification | Title | Body | When / gating |
|---|---|---|---|
| Mile complete | **Mile complete! 🔥** | "1.00 mi · 9:58 — your streak is safe for today." | Instant |
| Friend's mile | **[username] got their mile in!** (no emoji) | "2.10 mi · 19:42 · best pace 8:51/mi", or "📸 [caption]" if they post a photo | ~10 min after their sync |
| Head-to-Head | **[name] just passed you 👀** | "2.10 mi to your 1.00 — 1.10 mi to make up before the day's out." | Only on days your daily challenge is Head-to-Head |
| Head-to-Head (reminder version) | **@[rival] is ahead of you 👀** | | The 6 PM daily reminder on duel days |
| Competition | **Lead change!** / **You lost 1st!** | "[name] passed you in [comp]. They're 1.10 mi ahead — go take it back!" | |
| Medal | **🏅 Medal Unlocked** | "[Medal] — [description]" | |
| Streak Save | **❄️ Streak Save used** | "Life happened — we covered the miss and your N-day streak lives on." | 6–11 AM the morning after a missed day |
| Buddy Walk invite | **Buddy Walk** | "[Name] is out now and wants you on the walk — join in" | Has Join / Not now buttons |
| Buddy Walk started | **Buddy Walk started** | "Your buddy walk is underway — get moving!" | |
| Hype | **🔥 You got hyped!** | "[name] hyped your daily mile 🔥" | |
| Last call | **Last call: N-day streak on the line** | | 10 PM |

**Stacking 6 on one Lock Screen** with a screenshot account (S) and a friend (F):

1. **Set up S:**
   - Settings → Notifications → Mile A Day: **Notification Grouping: Off**. The app sends no thread-id, so they would otherwise collapse into one stack.
   - Previews: Always. No Focus mode.
   - In the app, quiet hours off.
2. **Set up F:** mile sharing audience set to Friends.
3. **Pick the day:** one where S's daily challenge is Head-to-Head against F.
4. **Order:** trigger oldest first, since newest sits on top.
   1. **❄️ Streak Save used.** S skips a day while holding a Save, and it arrives 6–11 AM the next morning. S must not be holding a Double Down, or the sweep waits instead of spending the Save.
   2. **🏅 Medal Unlocked** plus **Mile complete! 🔥.** S logs about 1.0 mi that earns a medal.
   3. **"F just passed you 👀"** and **"You lost 1st!"** F syncs a 2+ mi run. S and F must be in an active competition.
   4. **"F got their mile in!"** Arrives ~10 min later. Better if F posts a photo with a caption.
   5. **Top slot:** F hypes S's medal (**🔥 You got hyped!**), or F invites S to a **Buddy Walk** (high priority, with action buttons).

### 7. Onboarding

Order: Splash → 9-page Welcome tour → Sign in with Apple → Username → Personalization ("A little about you") → Health access → Privacy sheet ("Your privacy") → Dashboard style chooser (Fun / Modern).

**Welcome tour pages:**

1. Mile A Day
2. Hit Your Daily Mile
3. Log It Your Way
4. Keep the Fire Going
5. Challenges & Rivals
6. Race Your Friends
7. Better Together
8. Share Your Miles
9. You're All Set!

**Best 3 for "How it works":**

1. **"Hit Your Daily Mile"** — "Track a run or walk right in the app, or let Apple Watch and Fitness count it for you. One mile is all it takes."
2. **"Log It Your Way"** — In-app GPS, Apple Watch, Apple Fitness, any Health app, plus widgets.
3. **"Keep the Fire Going"** — the streak loop with the flame and week dots.

Alternate: "Race Your Friends" for the social angle.

**Seeing it again without touching the main account:**

- Use a **different Apple ID** on a spare phone or the Simulator. Sign-in matches accounts by email, so the same Apple ID logs back into the main account.
- Deleting and reinstalling with the same account shows the tour, sign-in and privacy screens, but skips Username and Personalization.
- In-app, only the *live* guided tour replays: Settings → Help → **App Tour**.

---

## C. Still to capture (needs a person with the phone)

| # | Shot | How | File name |
|---|---|---|---|
| 1 | ~~365 replay ×3~~ DONE (for an animated ad, a screen recording still beats stills) | Medals → Streaks → **Year Warrior** → scroll → **Replay**. Screen-record, then grab ~3.0 s / ~5.0 s / ~7 s. Then tap **Share This Win** → **Save** the Milestone card | `celebration-365-a/b/c.png`, `share-365.png` |
| 2 | 500 and 100 replays | Same route via Elite Runner (already pinned on Profile → Badges) and Century Club | `celebration-500-*.png`, `celebration-100-*.png` |
| 3 | Medal share card | Elite Runner → scroll → **Share** → **Save** (try Full story and Sticker) | `share-medal.png` |
| 4 | Streak Tokens detail | Tap **3 SAVERS** on the hero | `streak-tokens.png` |
| 5 | Flamey's Closet | **Closet** pill | `flamey-closet.png` |
| 6 | Insights + Hall of Streaks + Route Heatmap | Dashboard scroll → Insights; Profile → Activity scroll; Profile → Stats → Route Heatmap | `insights.png`, `hall-of-streaks.png`, `route-heatmap.png` |
| 7 | Flyover | Workout detail → **FLYOVER**; screen-record it | `flyover.png` |
| 8 | Mile in progress, recap, Live Activity, Dynamic Island | Next real walk | `workout-tracking.png`, `workout-recap.png`, `live-activity-lock.png`, `dynamic-island.png` |
| 9 | Streak-at-risk widget + Lock Screen countdown | After 6 PM on a day before walking | `widget-at-risk.png`, `live-activity-streak-risk.png` |
| 10 | Buddy Walk lobby / roster / recap, Friends "out now", Feed, Competition, Trophy Case | Needs test friends, because of real names | `buddy-lobby.png` etc. |
| 11 | Monthly recap | Auto-shows Nov 1 on the Dashboard | `monthly-recap.png` |
| 12 | Apple Watch | See §5 | `watch-*.png` |
| 13 | Notification stack | See §6 | `notifications-stack.png` |
