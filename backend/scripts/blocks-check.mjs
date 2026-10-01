/**
 * Blocked accounts check — the list behind Settings ▸ Privacy ▸ Blocked
 * accounts: you see who YOU blocked (newest first) and can undo it; who
 * blocked you is never revealed.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/blocks-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import {
  blockUser,
  listBlockedUsers,
  unblockUser,
} from "../dist/services/moderationService.js";

const db = PostgresService.getInstance();
const A = "blocks-check-a";
const B = "blocks-check-b";
const C = "blocks-check-c";
const ALL = [A, B, C];

let failures = 0;
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  console.log(`${ok ? "ok  " : "FAIL"}  ${label} → ${JSON.stringify(actual)} (expected ${JSON.stringify(expected)})`);
}

async function cleanup() {
  await db.query(`DELETE FROM user_blocks WHERE blocker_id = ANY($1::text[]) OR blocked_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM friendships WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1::text[])`, [ALL]);
}

async function main() {
  await cleanup();
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, apple_sub, email, username, first_name)
       VALUES ($1, $2, $3, $4, $4)`,
      [id, `sub-${id}`, `${id}@example.com`, id],
    );
  }
  await blockUser(A, B);
  await new Promise((r) => setTimeout(r, 20));
  await blockUser(A, C);
  check("my blocks, newest first", (await listBlockedUsers(A)).map((u) => u.user_id), [C, B]);
  check("...with a whole-second ISO date", /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test((await listBlockedUsers(A))[0].blocked_at), true);
  check("who blocked ME is never listed", (await listBlockedUsers(B)).length, 0);
  await unblockUser(A, B);
  check("unblocking removes them", (await listBlockedUsers(A)).map((u) => u.user_id), [C]);
  await cleanup();
  console.log(failures === 0 ? "blocks-check: all assertions passed" : `blocks-check: ${failures} FAILED`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch(async (err) => {
  console.error(err);
  await cleanup().catch(() => {});
  process.exit(1);
});
