/**
 * Validation + moderation for short user-typed NAMES that other people see
 * (Flamey's name, a saved outfit's name). App Review 1.2: anything one user
 * types that another user reads is user-generated content, and the backend
 * had no text filter of its own (usernames/captions are unfiltered; reports +
 * blocks are the moderation path) — so this is a small, deliberately
 * CONSERVATIVE blocklist: strong profanity, slurs and sexual terms only. It
 * is a floor, not a classifier; the report/block path still stands behind it.
 *
 * Character rule: letters (any script, with their combining marks), digits,
 * single spaces, the punctuation - ' . ! and emoji. No control characters,
 * no newlines. Length is counted in GRAPHEME CLUSTERS, so "👨‍👩‍👧" is one
 * character, the way the person typing it sees it.
 */

export type NameRejection = "too_long" | "empty" | "characters" | "not_allowed";

export type NameParse =
  | { ok: true; name: string }
  | { ok: false; reason: NameRejection };

const segmenter = new Intl.Segmenter("en", { granularity: "grapheme" });

export function graphemeCount(s: string): number {
  let n = 0;
  for (const _ of segmenter.segment(s)) n++;
  return n;
}

// One allowed code point. Emoji pieces: pictographs, regional indicators
// (flags), skin-tone modifiers, keycap/ZWJ/variation selectors and tag
// characters (subdivision flags).
const ALLOWED_CHAR =
  /^(?:[\p{L}\p{M}\p{N} \-'.!]|\p{Extended_Pictographic}|\p{Regional_Indicator}|\p{Emoji_Modifier}|[\u200D\uFE0E\uFE0F\u20E3]|[\u{E0020}-\u{E007F}])$/u;

// Control / format / line-separator characters — rejected outright rather
// than silently stripped, so what is stored is what was typed.
const FORBIDDEN = /[\p{Cc}\u2028\u2029]/u;

/**
 * Terms blocked wherever they appear once spacing/punctuation/leetspeak is
 * folded away ("f.u.c.k", "5hit"). Only terms with essentially no innocent
 * containing word belong here.
 */
const BLOCKED_ANYWHERE = [
  "fuck", "fvck", "shit", "cunt", "nigger", "nigga", "faggot", "whore",
  "slut", "bitch", "asshole", "bastard", "pussy", "penis", "vagina", "porn",
  "twat", "jizz", "dildo", "blowjob", "handjob", "motherf", "tranny", "hitler",
  "cocksuck",
];

/** Short terms blocked only as a whole word (so "Cassie", "Dickens"-style names pass). */
const BLOCKED_WORDS = new Set([
  "ass", "arse", "cum", "fag", "fags", "tit", "tits", "dick", "dicks", "cock",
  "cocks", "spic", "chink", "nazi", "nazis", "sex", "sexy", "rape", "hoe",
  "hoes", "kkk", "anal", "nude", "nudes", "coon", "gook", "wetback", "piss",
  // Whole-word only because an innocent word contains them: therapist,
  // (fire) retardant, swanky, Fukuoka.
  "rapist", "retard", "retarded", "retards", "wank", "wanker", "kike", "fuk",
]);

const LEET: Record<string, string> = {
  "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b",
  "@": "a", "$": "s", "!": "i", "|": "i",
};

function fold(s: string): string {
  return s
    .normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/[0134578@$!|]/g, (c) => LEET[c] ?? c);
}

/** True when a name carries a blocked term. Exported for the check script. */
export function containsBlockedTerm(name: string): boolean {
  const folded = fold(name);
  const compact = folded.replace(/[^a-z]/g, "");
  // Collapse runs ("fuuuck") as well as testing the raw compact form.
  const squeezed = compact.replace(/(.)\1+/g, "$1");
  for (const term of BLOCKED_ANYWHERE) {
    if (compact.includes(term) || squeezed.includes(term.replace(/(.)\1+/g, "$1"))) {
      return true;
    }
  }
  for (const word of folded.split(/[^a-z]+/)) {
    if (word && BLOCKED_WORDS.has(word)) return true;
  }
  return false;
}

/**
 * Trim, NFC-normalise, fold typographic apostrophes (iOS types ’ by default),
 * collapse internal runs of spaces, then check characters, length and the
 * blocklist — in that order, so the reason names the first thing to fix.
 */
export function parseDisplayName(input: unknown, maxGraphemes: number): NameParse {
  if (typeof input !== "string") return { ok: false, reason: "empty" };
  if (FORBIDDEN.test(input.trim())) return { ok: false, reason: "characters" };
  const name = input
    .normalize("NFC")
    .replace(/[\u2018\u2019\u02BC]/g, "'")
    .replace(/[ \u00A0\u2000-\u200A\u202F\u205F\u3000]+/g, " ")
    .trim();
  if (!name) return { ok: false, reason: "empty" };
  for (const ch of name) {
    if (!ALLOWED_CHAR.test(ch)) return { ok: false, reason: "characters" };
  }
  if (graphemeCount(name) > maxGraphemes) return { ok: false, reason: "too_long" };
  if (containsBlockedTerm(name)) return { ok: false, reason: "not_allowed" };
  return { ok: true, name };
}
