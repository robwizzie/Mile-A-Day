/**
 * Stickers a comment can be. Mirrors iOS `FlameyPackSticker` (raw value →
 * title); the art ships in the app, the server only knows the ids. A new
 * sticker is a row here AND a case there; an id the app doesn't know yet
 * draws as its `content` text, so adding one never breaks an older build.
 */
export const COMMENT_STICKERS: Readonly<Record<string, string>> = {
  hiii: "hiii",
  lol: "LMAOOO",
  bet: "bet",
  "love-this": "love this",
  "thank-youuu": "thank youuu",
  omw: "omw",
  gn: "gn",
  gm: "gm",
  nooo: "nooo",
  "lets-gooo": "LET'S GOOO",
  nah: "nah",
  hmm: "hmm",
  hypnotize: "you WILL get your mile in",
  "absolute-cinema": "absolute cinema",
  "this-is-fine": "this is fine",
  "side-eye": "side eye",
  "1158pm": "11:58 PM",
  what: "WHAT",
  "im-dead": "i'm dead",
  "deal-with-it": "deal with it",
  bruh: "bruh",
  "mile-done": "mile done",
};

export function isCommentSticker(id: unknown): id is string {
  return typeof id === "string" && Object.hasOwn(COMMENT_STICKERS, id);
}

/**
 * The text a sticker comment stores in `content`: what older apps, the push
 * body and admin tools show in its place.
 */
export function stickerFallbackText(id: string): string {
  return `🔥 ${COMMENT_STICKERS[id]}`;
}
