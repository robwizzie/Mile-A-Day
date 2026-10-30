Long-form reference for `.claude/rules/website.md` — not auto-loaded. Read the section you need before changing that area.

# Website Conventions

## SEO / link previews

### Link-preview videos (og.mp4)

Every page with an `opengraph-image` card also publishes an animated version
as `og:video`: `/og.mp4` (home, and the root layout's default), and
`<segment>/og.mp4` for `/updates`, `/desk`, `/privacy`, `/terms`,
`/u/<username>` and `/p/<postId>`. Platforms that play `og:video` (iMessage,
Discord, Telegram…) show the clip; everyone else (X, LinkedIn, WhatsApp, Slack)
shows the PNG, which also serves as the poster, so the PNG cards stay exactly as
they were.

How it works (`app/_og/video/`):

- `render.ts` draws a scene frame by frame on a Skia canvas (`@napi-rs/canvas`,
  a native module with prebuilt Linux binaries) and encodes 6 s at 30 fps with
  `h264-mp4-encoder` (WebAssembly, H.264 baseline/yuv420p). No ffmpeg binary,
  so it runs in an ordinary Vercel function. Both packages are
  `serverExternalPackages`, and `outputFileTracingIncludes` in
  `next.config.mjs` ships the fonts/images (and `public/desk/**` for `/desk`).
- `kit.ts` is the shared look (ground and glows, lockup, App Store pill,
  flame, streak chip, avatar ring, confetti, sparkles, easing). `scenes/*`
  hold one scene per page type. `person.ts` serves both profile and post.
- `serve.ts` caches the bytes in Next's data cache plus a small in-memory map,
  and answers HTTP Range requests itself.
- `meta.ts` is the `openGraph.videos` helper. It's kept apart so page metadata
  never imports the canvas or encoder.

Why it's built this way:

- **Range requests are mandatory.** AVFoundation (which iMessage uses to fetch
  and play link previews) only plays video from a server that honours `Range`.
  It's unverified whether Vercel's CDN would serve 206s correctly from a cached
  200, so the route sets `CDN-Cache-Control: no-store` and answers ranges from
  the cached bytes. The data cache is the cache.
- **Cache keys are the facts drawn.** The profile and post routes look up the
  public data first and key the video by `factsKey(...)` of exactly what the
  scene shows. A new streak, avatar or banner therefore gets a new video
  straight away, and every unknown username or post shares one
  `u/unknown`/`p/unknown` video. Keying by the raw URL would let anyone force
  a fresh multi-second render per request. Keys also include the deployment
  id, so new scene code never serves old videos.
- **The encoder's MP4 needs fixing before it ships** (`mp4.ts`). It writes no
  `stss` box, and per the spec that means every frame is a keyframe. Seeking
  then lands on P-frames: `ffmpeg -ss` decoded nothing past the first GOP. It
  also writes `moov` after `mdat`. `finishMp4` adds `stss` from the IDR NALs
  it finds and moves `moov` to the front.
- **The Emscripten build installs process-wide hooks.** It adds
  `uncaughtException`/`unhandledRejection` handlers that rethrow, which would
  crash a long-lived server on any stray rejection. `createEncoder()` removes
  them again. The encoders also share one in-memory filesystem, so each
  render writes its own file.
- **No `react-dom/server` in routes.** Next refuses to build it. Release-note
  icons are built from the lucide component's own `iconNode` (via
  `Component.render`) and loaded as SVG.
- **Clean, fun, not overwhelming: one payoff, then stillness.** Each clip
  has ONE moment, and everything has landed by about 3.5 s and holds still
  so the preview can be read. The moments are: on home, the app's real
  "Still lit." share card popping out of the phone after a tap on Start
  Mile, the release cards' single
  highlight pass, the desk changing style, the legal stamp, and a profile's
  streak landing. The first pass also had twinkling sparkles, shine sweeps
  over headlines, a pill glint, embers, bobbing cards, an endless card
  scroll and two counters running at once. Together they read as noise, so
  they're gone. Pops overshoot only slightly (`ease.outBack`, c = 1.25).
  Confetti is a small burst in brand colours from BEHIND the thing it
  celebrates, gone in ~1.4 s. A counter never shows 0: `streakChip` counts
  from half the streak.
- **Show the real app, not a mock of it.** The home video is built from
  real captures, pre-cropped into `app/_og/`: `dashboard-full.jpg` (the
  hero's `public/images/hero` shot) in a drawn iPhone frame, and
  `still-lit.jpg` (the share card cropped from the 1.2.07 What's New
  capture). An earlier version drew its own "mile done" card over a
  cropped screenshot, and it read as a mock-up. `next.config.mjs` traces
  `app/_og/*.jpg|png`, so a new asset ships without a config change, but
  a replaced capture needs the scene's coordinates re-checked (`START` in
  `home.ts` is the Start Mile button in 776-wide capture pixels).
- **Bitrate is about moving pixels.** H.264 baseline has no weighted
  prediction, so fades and moving photos cost the most. A bobbing phone
  screenshot took home to 2.3 MB, and a Ken Burns banner took a profile to
  4 MB. Hence: photos, banners and the desk box hold still once they land;
  the loop seam fades only the FOREGROUND (`foreground()`) back to the still
  stage the intro starts from; QP 24 with keyframes every 3 s. Clips land
  around 0.4–0.9 MB.
- **Skia is slow at thousands of small paths.** `lib/desk-engine`'s
  `drawLeds` (about 2,000 arcs a frame) took a desk render to 43 s. The video
  draws the same look with three image draws: a blocky upscale, a cached
  board mask with round holes, and a smoothed "light" pass.
- **The desk clip is real.** `/desk` runs the box's own MicroPython code
  (`public/desk/py`) against the live `/public/desk` feed, so it shows
  whatever look the box has today (including seasonal ones). With no feed it
  answers 503 and the PNG stands in. It never shows invented numbers.
- **Posts stay friends-only.** As with the PNG card, `/p/<id>` draws only the
  author. The tile beside them is decoration with a route invented from a
  seed, never the post's.

Checking a change: `next build`, then `next start` and curl each `og.mp4`
(status, `Content-Type`, a `Range: bytes=0-1` → 206). LOOK at frames across
the clip, not just one. `ffmpeg -i x.mp4 -f null -` should report no errors,
and `ffmpeg -ss 5.5 -i x.mp4 -frames:v 1 out.png` should produce a frame.
