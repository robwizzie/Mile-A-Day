/**
 * Loads App Store Connect offer codes for the free-year referral reward.
 *
 *   DATABASE_URL=... node scripts/load-offer-codes.mjs codes.txt
 *
 * One code per line. A code already loaded is left alone, so re-running is
 * safe. Prints how many unassigned codes remain, and never prints a code.
 */
import fs from "node:fs";
import pg from "pg";

const file = process.argv[2];
if (!file) {
  console.error("Usage: node scripts/load-offer-codes.mjs <file>");
  process.exit(1);
}
const codes = fs.readFileSync(file, "utf8").split(/\s+/).filter(Boolean);
const client = new pg.Client({ connectionString: process.env.DATABASE_URL });
await client.connect();
await client.query(
  `INSERT INTO referral_offer_codes (code) SELECT unnest($1::text[]) ON CONFLICT (code) DO NOTHING`,
  [codes],
);
const { rows } = await client.query(`SELECT COUNT(*)::int AS n FROM referral_offer_codes WHERE assigned_to IS NULL`);
console.log(`Read ${codes.length} codes. ${rows[0].n} unassigned codes available.`);
await client.end();
