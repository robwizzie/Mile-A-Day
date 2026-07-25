/**
 * Buddy Walks end-to-end lifecycle test.
 *
 * The "multi-user testing without multiple devices" harness: every participant
 * is driven entirely over HTTP, exactly as a real client would be. This is how
 * you exercise a buddy session without owning N iPhones — and it stays useful
 * during iOS work, where one real device can play one participant while this
 * script plays the rest.
 *
 * NOT wired into CI (it needs a running server, not just a database). Run it
 * against a THROWAWAY database only — it seeds users and friendships.
 *
 *   # 1. migrate a throwaway DB
 *   DATABASE_URL=postgres://... node dist/db/migrateCli.js
 *   # 2. boot the server against it with the feature flag on
 *   DATABASE_URL=... APP_JWT_SECRET=dev PORT=4599 BUDDY_SESSIONS=true \
 *     node dist/server.js &
 *   # 3. run this
 *   DATABASE_URL=... APP_JWT_SECRET=dev BASE_URL=http://127.0.0.1:4599 \
 *     node scripts/buddy-e2e.mjs
 */
import { SignJWT } from "jose";
import pg from "pg";
import fs from "node:fs";
import path from "node:path";

const BASE = process.env.BASE_URL || "http://127.0.0.1:4599";
const SECRET = new TextEncoder().encode(process.env.APP_JWT_SECRET);
const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });

let failures = 0;
function check(label, cond, extra = "") {
  if (cond) console.log(`  ✓ ${label}`);
  else {
    failures++;
    console.log(`  ✗ ${label} ${extra}`);
  }
}

async function token(userId) {
  return new SignJWT({ sub: userId })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(SECRET);
}

async function api(tok, method, path, body) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${tok}`,
      "Content-Type": "application/json",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    /* non-JSON (e.g. 304 empty body) */
  }
  return { status: res.status, body: json, raw: text };
}

async function seed() {
  const users = [
    ["u_host", "hostie", "Host"],
    ["u_pal", "pally", "Pal"],
    ["u_third", "thirdy", "Third"],
    ["u_stranger", "strange", "Stranger"],
    ["u_legacy", "legacy", "Legacy"],
  ];
  for (const [id, uname, first] of users) {
    await pool.query(
      `INSERT INTO users (user_id, username, first_name, apple_sub, goal_miles, current_streak)
       VALUES ($1,$2,$3,$4,'1.0',0) ON CONFLICT (user_id) DO NOTHING`,
      [id, uname, first, id],
    );
  }
  // Accepted friendships store BOTH directions.
  const friends = [
    ["u_host", "u_pal"],
    ["u_host", "u_third"],
    ["u_host", "u_legacy"],
  ];
  for (const [a, b] of friends) {
    for (const [x, y] of [
      [a, b],
      [b, a],
    ]) {
      await pool.query(
        `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1,$2,'accepted')
         ON CONFLICT (user_id, friend_id) DO UPDATE SET status='accepted'`,
        [x, y],
      );
    }
  }
  // Everyone except u_legacy is on a buddy-capable build.
  await pool.query(
    `UPDATE users SET buddy_enrolled_at = NOW()
      WHERE user_id IN ('u_host','u_pal','u_third','u_stranger')`,
  );
  // Posting requires UGC-terms acceptance (App Review 1.2) — the real client
  // gates on it too, so accept for everyone rather than bypassing the check.
  await pool.query(`UPDATE users SET terms_accepted_at = NOW()`);
}

async function main() {
  await seed();
  const host = await token("u_host");
  const pal = await token("u_pal");
  const third = await token("u_third");
  const stranger = await token("u_stranger");

  console.log("\n── enrollment + candidates ──");
  check(
    "enroll is idempotent",
    (await api(host, "POST", "/buddy/enroll")).status === 200,
  );
  const cands = await api(host, "GET", "/buddy/candidates");
  const ids = (cands.body?.candidates ?? []).map((c) => c.user_id);
  check(
    "candidates include enrolled friends",
    ids.includes("u_pal") && ids.includes("u_third"),
  );
  check(
    "candidates EXCLUDE unenrolled friend (legacy build)",
    !ids.includes("u_legacy"),
  );
  check("candidates exclude non-friends", !ids.includes("u_stranger"));

  console.log("\n── create + invite ──");
  const created = await api(host, "POST", "/buddy/sessions", {
    mode: "coop_goal",
    goalValue: 3,
    activityType: "walking",
    inviteUserIds: ["u_pal", "u_third", "u_legacy"],
  });
  check(
    "create returns 201",
    created.status === 201,
    JSON.stringify(created.body),
  );
  const sid = created.body?.id;
  const code = created.body?.join_code;
  check("join code issued", typeof code === "string" && code.length === 6);
  const invitedIds = created.body.participants.map((p) => p.user_id);
  check("unenrolled friend was NOT invited", !invitedIds.includes("u_legacy"));
  check("host is a participant", invitedIds.includes("u_host"));

  console.log("\n── validation ──");
  check(
    "invalid mode rejected",
    (
      await api(host, "POST", "/buddy/sessions", {
        mode: "nope",
        activityType: "walking",
      })
    ).status === 400,
  );
  check(
    "goal required for non-together mode",
    (
      await api(host, "POST", "/buddy/sessions", {
        mode: "race_goal",
        activityType: "walking",
      })
    ).status === 400,
  );
  const together = await api(host, "POST", "/buddy/sessions", {
    mode: "together",
    activityType: "any",
  });
  check("together mode needs no goal", together.status === 201);

  console.log("\n── authorization ──");
  check(
    "non-participant cannot read state",
    (await api(stranger, "GET", `/buddy/sessions/${sid}/state`)).status === 400,
  );
  check(
    "non-friend cannot join by code",
    (await api(stranger, "POST", "/buddy/sessions/join", { code })).status ===
      400,
  );

  console.log("\n── join + polling cursor ──");
  const joined = await api(pal, "POST", `/buddy/sessions/${sid}/join`);
  check("invitee joins", joined.status === 200);
  const v1 = joined.body.state_version;
  const unchanged = await api(
    pal,
    "GET",
    `/buddy/sessions/${sid}/state?since=${v1}`,
  );
  check("unchanged version returns 304", unchanged.status === 304);
  await api(third, "POST", `/buddy/sessions/${sid}/join`);
  const changed = await api(
    pal,
    "GET",
    `/buddy/sessions/${sid}/state?since=${v1}`,
  );
  check(
    "version bump returns fresh state",
    changed.status === 200 && changed.body.state_version > v1,
  );

  console.log("\n── start ──");
  check(
    "non-host cannot start",
    (await api(pal, "POST", `/buddy/sessions/${sid}/start`)).status === 400,
  );
  const started = await api(host, "POST", `/buddy/sessions/${sid}/start`);
  check(
    "host starts session",
    started.status === 200 && started.body.status === "active",
  );
  const startAt = new Date(started.body.started_at).getTime();
  check(
    "started_at is in the FUTURE (synced countdown)",
    startAt > Date.now(),
    `(${started.body.started_at})`,
  );
  const active = started.body.participants.filter((p) => p.status === "active");
  check("all joined participants became active", active.length === 3);

  console.log("\n── progress: monotonic + clamped ──");
  const p1 = await api(host, "POST", `/buddy/sessions/${sid}/progress`, {
    distanceMiles: 0.2,
    durationSeconds: 120,
  });
  check(
    "progress returns full roster (not an ack)",
    Array.isArray(p1.body?.participants),
  );
  const hostAfter1 = p1.body.participants.find((p) => p.user_id === "u_host");
  check("progress recorded", hostAfter1.distance_miles > 0);

  const p2 = await api(host, "POST", `/buddy/sessions/${sid}/progress`, {
    distanceMiles: 0.05,
    durationSeconds: 130,
  });
  const hostAfter2 = p2.body.participants.find((p) => p.user_id === "u_host");
  check(
    "backwards progress is ignored (monotonic)",
    hostAfter2.distance_miles >= hostAfter1.distance_miles,
    `${hostAfter1.distance_miles} -> ${hostAfter2.distance_miles}`,
  );

  const p3 = await api(host, "POST", `/buddy/sessions/${sid}/progress`, {
    distanceMiles: 500,
    durationSeconds: 140,
  });
  const hostAfter3 = p3.body.participants.find((p) => p.user_id === "u_host");
  check(
    "teleport clamped, not rejected",
    hostAfter3.distance_miles < 1 &&
      hostAfter3.distance_miles >= hostAfter2.distance_miles,
    `got ${hostAfter3.distance_miles}`,
  );

  check(
    "negative distance rejected",
    (
      await api(host, "POST", `/buddy/sessions/${sid}/progress`, {
        distanceMiles: -5,
        durationSeconds: 10,
      })
    ).status === 400,
  );

  console.log("\n── co-op pooling ──");
  await api(pal, "POST", `/buddy/sessions/${sid}/progress`, {
    distanceMiles: 0.4,
    durationSeconds: 200,
  });
  const pooled = await api(third, "POST", `/buddy/sessions/${sid}/progress`, {
    distanceMiles: 0.3,
    durationSeconds: 200,
  });
  const sum = pooled.body.participants
    .filter((p) => p.status === "active" || p.status === "finished")
    .reduce((s, p) => s + p.distance_miles, 0);
  check(
    "group_distance_miles pools participants",
    Math.abs(pooled.body.group_distance_miles - sum) < 0.01,
    `${pooled.body.group_distance_miles} vs ${sum}`,
  );

  console.log("\n── finish + finalize ──");
  await api(host, "POST", `/buddy/sessions/${sid}/finish`);
  await api(pal, "POST", `/buddy/sessions/${sid}/finish`);
  const last = await api(third, "POST", `/buddy/sessions/${sid}/finish`);
  check(
    "session completes when everyone finishes",
    last.body.status === "completed",
  );
  check("co-op mode declares NO winner", last.body.winner_user_id === null);
  check(
    "placements stamped",
    last.body.participants.every((p) => p.place !== null),
  );

  console.log("\n── race mode winner ──");
  const race = await api(host, "POST", "/buddy/sessions", {
    mode: "race_goal",
    goalValue: 1,
    activityType: "running",
    inviteUserIds: ["u_pal"],
  });
  const rid = race.body.id;
  await api(pal, "POST", `/buddy/sessions/${rid}/join`);
  await api(host, "POST", `/buddy/sessions/${rid}/start`);
  // Backdate the start so the physical-ceiling clamp permits a realistic
  // distance — a real race has minutes of elapsed time behind every report.
  await pool.query(
    `UPDATE buddy_sessions SET started_at = NOW() - INTERVAL '20 minutes' WHERE id = $1`,
    [rid],
  );
  await api(pal, "POST", `/buddy/sessions/${rid}/progress`, {
    distanceMiles: 0.5,
    durationSeconds: 300,
  });
  await api(host, "POST", `/buddy/sessions/${rid}/progress`, {
    distanceMiles: 0.2,
    durationSeconds: 300,
  });
  await api(host, "POST", `/buddy/sessions/${rid}/finish`);
  const raceEnd = await api(pal, "POST", `/buddy/sessions/${rid}/finish`);
  check(
    "race declares the furthest participant winner",
    raceEnd.body.winner_user_id === "u_pal",
    JSON.stringify(raceEnd.body.winner_user_id),
  );

  console.log("\n── recap + mine ──");
  const recap = await api(host, "GET", `/buddy/sessions/${sid}/recap`);
  check(
    "recap returns event timeline",
    Array.isArray(recap.body?.events) && recap.body.events.length > 0,
  );
  const kinds = recap.body.events.map((e) => e.kind);
  check(
    "timeline records created/joined/started/finished/completed",
    ["created", "joined", "started", "finished", "completed"].every((k) =>
      kinds.includes(k),
    ),
    kinds.join(","),
  );
  const mine = await api(host, "GET", "/buddy/sessions/mine");
  check(
    "mine excludes completed sessions",
    (mine.body.active?.id ?? null) !== sid,
  );

  console.log("\n── participant cap ──");
  await pool.query(
    `INSERT INTO users (user_id, username, first_name, apple_sub, goal_miles, current_streak)
     SELECT 'u_fill'||g, 'fill'||g, 'Fill', 'u_fill'||g, '1.0', 0 FROM generate_series(1,9) g
     ON CONFLICT (user_id) DO NOTHING`,
  );
  await pool.query(
    `UPDATE users SET buddy_enrolled_at = NOW() WHERE user_id LIKE 'u_fill%'`,
  );
  for (let g = 1; g <= 9; g++) {
    for (const [x, y] of [
      ["u_host", `u_fill${g}`],
      [`u_fill${g}`, "u_host"],
    ]) {
      await pool.query(
        `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1,$2,'accepted')
         ON CONFLICT (user_id, friend_id) DO UPDATE SET status='accepted'`,
        [x, y],
      );
    }
  }
  const over = await api(host, "POST", "/buddy/sessions", {
    mode: "together",
    activityType: "any",
    inviteUserIds: Array.from({ length: 9 }, (_, i) => `u_fill${i + 1}`),
  });
  check(
    "oversized invite list rejected",
    over.status === 400,
    JSON.stringify(over.body),
  );

  const capped = await api(host, "POST", "/buddy/sessions", {
    mode: "together",
    activityType: "any",
    inviteUserIds: Array.from({ length: 7 }, (_, i) => `u_fill${i + 1}`),
  });
  const cid = capped.body.id;
  for (let g = 1; g <= 7; g++) {
    await api(await token(`u_fill${g}`), "POST", `/buddy/sessions/${cid}/join`);
  }
  const nineth = await api(
    await token("u_fill8"),
    "POST",
    "/buddy/sessions/join",
    {
      code: capped.body.join_code,
    },
  );
  check(
    "9th joiner blocked by participant cap",
    nineth.status === 400,
    JSON.stringify(nineth.body),
  );

  console.log("\n── buddy medals ──");
  // Medals are aggregate-driven and evaluated when a session closes; the co-op
  // and race sessions above already completed for u_host and u_pal.
  const hostBadges = await pool.query(
    `SELECT badge_id FROM user_badges WHERE user_id = 'u_host' AND badge_id LIKE 'buddy_%'`,
  );
  const hostBadgeIds = hostBadges.rows.map((r) => r.badge_id);
  check(
    "buddy_done_1 awarded after finishing a session",
    hostBadgeIds.includes("buddy_done_1"),
    hostBadgeIds.join(","),
  );
  // u_host has walked with u_pal and u_third only — 2 distinct PEOPLE across
  // two completed sessions. crew_3 must not fire yet: the aggregate counts
  // people, not sessions, so repeat walks with the same friend can't unlock it.
  check(
    "buddy_crew_3 NOT awarded at 2 distinct partners",
    !hostBadgeIds.includes("buddy_crew_3"),
    hostBadgeIds.join(","),
  );

  // Complete one more session with a THIRD distinct person and it should land.
  const crew = await api(host, "POST", "/buddy/sessions", {
    mode: "together",
    activityType: "walking",
    inviteUserIds: ["u_fill1"],
  });
  const fill1Token = await token("u_fill1");
  await api(fill1Token, "POST", `/buddy/sessions/${crew.body.id}/join`);
  await api(host, "POST", `/buddy/sessions/${crew.body.id}/start`);
  await api(host, "POST", `/buddy/sessions/${crew.body.id}/finish`);
  await api(fill1Token, "POST", `/buddy/sessions/${crew.body.id}/finish`);
  // Badge evaluation is fire-and-forget off the session close.
  await new Promise((r) => setTimeout(r, 1500));

  const hostBadges2 = await pool.query(
    `SELECT badge_id FROM user_badges WHERE user_id = 'u_host' AND badge_id LIKE 'buddy_crew_%'`,
  );
  check(
    "buddy_crew_3 awarded once a 3rd distinct partner is reached",
    hostBadges2.rows.some((r) => r.badge_id === "buddy_crew_3"),
    hostBadges2.rows.map((r) => r.badge_id).join(","),
  );
  const palBadges = await pool.query(
    `SELECT badge_id FROM user_badges WHERE user_id = 'u_pal' AND badge_id LIKE 'buddy_won_%'`,
  );
  check(
    "buddy_won_1 awarded to the race winner",
    palBadges.rows.some((r) => r.badge_id === "buddy_won_1"),
    palBadges.rows.map((r) => r.badge_id).join(","),
  );
  const hostWon = await pool.query(
    `SELECT 1 FROM user_badges WHERE user_id = 'u_host' AND badge_id = 'buddy_won_1'`,
  );
  check("buddy_won_1 NOT awarded to the loser", hostWon.rows.length === 0);

  console.log("\n── multi-person collab posts ──");
  // A post needs media_url, so seed the row directly and then exercise the
  // authorization surface — the part that actually carries risk.
  const legacyPost = await pool.query(
    `INSERT INTO posts (user_id, media_url, local_date, share_to_feed, share_to_story,
                        is_auto, coauthor_user_id, coauthor_status)
     VALUES ('u_host', '/uploads/posts/legacy.jpg', CURRENT_DATE, true, false, false,
             'u_pal', 'accepted')
     RETURNING post_id`,
  );
  const legacyPostId = legacyPost.rows[0].post_id;

  const multiPost = await pool.query(
    `INSERT INTO posts (user_id, media_url, local_date, share_to_feed, share_to_story,
                        is_auto, coauthor_user_id, coauthor_status)
     VALUES ('u_host', '/uploads/posts/buddy.jpg', CURRENT_DATE, true, false, false,
             'u_pal', 'accepted')
     RETURNING post_id`,
  );
  const multiPostId = multiPost.rows[0].post_id;
  for (const [uid, st] of [
    ["u_pal", "accepted"],
    ["u_third", "accepted"],
    ["u_fill1", "pending"],
  ]) {
    await pool.query(
      `INSERT INTO post_coauthors (post_id, user_id, status) VALUES ($1,$2,$3)`,
      [multiPostId, uid, st],
    );
  }

  // visiblePostAuthor is exercised through the comments endpoint, which 404s
  // when the viewer may not see the post.
  const canSee = async (tok, postId) =>
    (await api(tok, "GET", `/posts/${postId}/comments`)).status === 200;

  check("author sees own legacy post", await canSee(host, legacyPostId));
  check("legacy coauthor sees legacy post", await canSee(pal, legacyPostId));
  check("friend-of-author sees legacy post", await canSee(third, legacyPostId));
  check(
    "stranger CANNOT see legacy post (unchanged)",
    !(await canSee(stranger, legacyPostId)),
  );

  check("author sees multi-collab post", await canSee(host, multiPostId));
  check(
    "accepted multi-coauthor sees the post",
    await canSee(third, multiPostId),
  );
  const fill1 = await token("u_fill1");
  check(
    "PENDING multi-coauthor still sees their own invite",
    await canSee(fill1, multiPostId),
  );
  check(
    "stranger CANNOT see multi-collab post",
    !(await canSee(stranger, multiPostId)),
  );

  // A block against ANY accepted participant must deny the whole post, the
  // same way it does for a legacy coauthor.
  await pool.query(
    `INSERT INTO user_blocks (blocker_id, blocked_id) VALUES ('u_fill2','u_third')
     ON CONFLICT DO NOTHING`,
  );
  for (const [x, y] of [
    ["u_host", "u_fill2"],
    ["u_fill2", "u_host"],
  ]) {
    await pool.query(
      `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1,$2,'accepted')
       ON CONFLICT (user_id, friend_id) DO UPDATE SET status='accepted'`,
      [x, y],
    );
  }
  const fill2 = await token("u_fill2");
  check(
    "block vs an accepted multi-coauthor denies the post",
    !(await canSee(fill2, multiPostId)),
  );
  check(
    "same viewer CAN still see the legacy post (block is scoped)",
    await canSee(fill2, legacyPostId),
  );

  console.log("\n── creating a collab post via the API ──");
  // POST /posts requires media_url to point at a real uploaded file, so place
  // one where the controller looks rather than bypassing the endpoint — the
  // point of this block is to exercise the REAL client path.
  // Upload filenames are `<userId>-<ts>-<rand>.jpg` and the controller enforces
  // that prefix so nobody can republish a friend's photo as their own.
  const mediaRel = "uploads/posts/u_host-1-e2ecollab.jpg";
  fs.mkdirSync(path.join(process.cwd(), "uploads/posts"), { recursive: true });
  fs.writeFileSync(path.join(process.cwd(), mediaRel), "not-a-real-jpeg");
  // Posting is gated on having finished today's mile — a real product rule, so
  // satisfy it with a real workout rather than working around the check.
  await pool.query(
    `INSERT INTO workouts (workout_id, user_id, distance, local_date, date,
                           timezone_offset, workout_type, device_end_date,
                           calories, total_duration)
     VALUES ('w_host_collab', 'u_host', 1.4, CURRENT_DATE, CURRENT_DATE, 0,
             'walking', NOW(), 90, 1500)
     ON CONFLICT (workout_id) DO NOTHING`,
  );
  // The real client path: POST /posts with coauthor_user_ids, exactly what the
  // buddy recap's "Share this walk" sends.
  const collabPost = await api(host, "POST", "/posts", {
    media_url: `/${mediaRel}`,
    caption: "great walk",
    share_to_feed: true,
    share_to_story: false,
    is_auto: false,
    coauthor_user_ids: ["u_pal", "u_third", "u_stranger"],
  });
  check(
    "collab post created",
    collabPost.status === 200 || collabPost.status === 201,
    `${collabPost.status} ${JSON.stringify(collabPost.body)}`,
  );
  const createdId = collabPost.body?.post_id;

  const rowsCreated = await pool.query(
    `SELECT user_id, status FROM post_coauthors WHERE post_id = $1 ORDER BY user_id`,
    [createdId],
  );
  const createdIds = rowsCreated.rows.map((r) => r.user_id);
  check(
    "friends were credited as coauthors",
    createdIds.includes("u_pal") && createdIds.includes("u_third"),
    createdIds.join(","),
  );
  check(
    "non-friend was DROPPED, not fatal",
    !createdIds.includes("u_stranger"),
    createdIds.join(","),
  );
  const legacyMirror = await pool.query(
    `SELECT coauthor_user_id, coauthor_status FROM posts WHERE post_id = $1`,
    [createdId],
  );
  const mirrorRow = legacyMirror.rows[0] ?? {};
  check(
    "legacy scalar columns mirror the first coauthor (old-client view)",
    mirrorRow.coauthor_user_id != null && mirrorRow.coauthor_status === "pending",
    JSON.stringify(mirrorRow),
  );

  // Accept from a NON-mirrored participant — the path that only exists because
  // of post_coauthors.
  const mirrored = mirrorRow.coauthor_user_id;
  const nonMirrored = createdIds.find((id) => id !== mirrored);
  const nonMirroredTok = await token(nonMirrored);
  const acceptRes = await api(
    nonMirroredTok,
    "POST",
    `/posts/${createdId}/coauthor`,
    { accept: true },
  );
  check(
    "non-mirrored coauthor can accept",
    acceptRes.status === 200,
    JSON.stringify(acceptRes.body),
  );
  const afterAccept = await pool.query(
    `SELECT status FROM post_coauthors WHERE post_id = $1 AND user_id = $2`,
    [createdId, nonMirrored],
  );
  check("their row is accepted", afterAccept.rows[0]?.status === "accepted");

  // The create response itself carries the array the feed header renders from
  // (createPost re-reads the post after attaching the coauthors).
  check(
    "create response carries the coauthors array",
    Array.isArray(collabPost.body?.coauthors) &&
      collabPost.body.coauthors.length === 2,
    JSON.stringify(collabPost.body?.coauthors),
  );
  // Pre-existing posts must keep the OLD payload shape exactly: null, not [].
  const legacyShape = await pool.query(
    `SELECT 1 FROM post_coauthors WHERE post_id = $1`,
    [legacyPostId],
  );
  check(
    "a legacy post has no post_coauthors rows (payload shape unchanged)",
    legacyShape.rows.length === 0,
  );

  console.log("\n── friends walking now (pull-only) ──");
  const live = await api(host, "POST", "/buddy/sessions", {
    mode: "together",
    activityType: "walking",
    inviteUserIds: [],
  });
  const joinable = await api(third, "GET", "/buddy/joinable");
  const offered = (joinable.body?.sessions ?? []).map((s) => s.session_id);
  check("friend's live session is offered", offered.includes(live.body.id));
  const selfView = await api(host, "GET", "/buddy/joinable");
  check(
    "host is NOT offered their own session",
    !(selfView.body?.sessions ?? []).some((s) => s.session_id === live.body.id),
  );
  const strangerView = await api(stranger, "GET", "/buddy/joinable");
  check(
    "non-friend is not offered the session",
    !(strangerView.body?.sessions ?? []).some(
      (s) => s.session_id === live.body.id,
    ),
  );
  await api(third, "POST", `/buddy/sessions/${live.body.id}/join`);
  const afterJoin = await api(third, "GET", "/buddy/joinable");
  check(
    "session disappears from the offer once joined",
    !(afterJoin.body?.sessions ?? []).some(
      (s) => s.session_id === live.body.id,
    ),
  );

  console.log(
    `\n${failures === 0 ? "✅ ALL BUDDY E2E ASSERTIONS PASSED" : `❌ ${failures} FAILURE(S)`}`,
  );
  await pool.end();
  process.exit(failures === 0 ? 0 : 1);
}

main().catch(async (e) => {
  console.error(e);
  await pool.end();
  process.exit(1);
});
