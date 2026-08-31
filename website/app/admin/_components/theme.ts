/**
 * The iOS app's design language, ported for the admin dashboard.
 *
 * These are not new colours — every value here is read off
 * `app/Mile A Day/Core/Theme/MADTheme.swift`, converted from SwiftUI's 0–1
 * components to hex. The dashboard used the marketing site's burgundy
 * (#c72554) on a flat near-black, which is a different brand from the one the
 * app ships; anyone switching between the two saw two products. If MADTheme
 * changes, change these to match — they are a copy, not a second opinion.
 */

/** MADTheme.Colors.madRed — Color(red: 0.85, green: 0.25, blue: 0.35). */
export const MAD_RED = "#d94059";
/** The redGradient stops: Color(0.9,0.3,0.4) → Color(0.7,0.2,0.3). */
export const MAD_RED_BRIGHT = "#e64d66";
export const MAD_RED_DEEP = "#b3334d";
/** MADTheme.Colors.walkBlue — walks are blue everywhere in the app. */
export const WALK_BLUE = "#4099f2";
export const MAD_SUCCESS = "#33b34d";
export const MAD_WARNING = "#ff9900";
export const MAD_ERROR = "#e63333";

/**
 * MADTheme.Colors.appBackgroundGradient — near-black with a red tint, top to
 * bottom. The tint is the whole reason the app doesn't read as a generic dark
 * theme, so the dashboard takes it rather than a flat #0a0a0a.
 */
export const APP_BACKGROUND =
  "linear-gradient(180deg, #26141a 0%, #1f0f14 35%, #140a0f 70%, #0d050a 100%)";

/**
 * THE workout-type colour language, app-wide: runs are red, walks are blue,
 * hikes green, cycling orange (`MADTheme.workoutColor`). Every surface in the
 * app routes through it, so a chart that colours "walking" amber is telling
 * the reader something the app never told them.
 *
 * Deliberately NOT the chart series palette below: these are identity
 * colours carried over from the app, used one-per-row where nothing has to be
 * told apart from an adjacent slice.
 */
export function workoutColor(type: string | null | undefined): string {
  switch ((type ?? "").toLowerCase()) {
    case "running":
      return MAD_RED;
    case "walking":
      return WALK_BLUE;
    case "hiking":
      return MAD_SUCCESS;
    case "cycling":
      return MAD_WARNING;
    default:
      return MAD_RED;
  }
}

/**
 * The categorical set for charts drawing SEVERAL series at once, validated
 * against this dashboard's card surface (#2a1c20 — the app gradient under the
 * card's 5% white fill): every adjacent pair clears the colour-vision
 * separation floor, the normal-vision floor and 3:1 contrast, and all three
 * sit in one lightness band so no series shouts louder than the others.
 *
 * Assign IN ORDER, never cycle. A fourth concurrent series does not get an
 * invented hue — the app's own walkBlue and warning are too light to join
 * this band, and inventing one that isn't in MADTheme would be a new brand
 * colour. Split the chart instead.
 */
export const SERIES = [MAD_RED, "#0284c7", "#d97706"] as const;

/** The single hue every heat grid ramps through, as "r, g, b" for rgba(). */
export const HEAT_HUE = "217, 64, 89";

/**
 * A wider palette for one-series-per-card breakdowns, where nothing has to be
 * told apart from a neighbour at a glance. Not for stacked or grouped charts.
 */
export const PALETTE = [
  MAD_RED,
  WALK_BLUE,
  MAD_WARNING,
  MAD_SUCCESS,
  "#a78bfa",
  "#f472b6",
  "#fb923c",
  "#60a5fa",
  "#9ca3af",
];

/**
 * The app's card: `RoundedRectangle(cornerRadius: 16, style: .continuous)`
 * filled `Color.white.opacity(0.05)` with a 1px `Color.white.opacity(0.08)`
 * border (see ProfileStatsRow and every card that followed it). The dashboard
 * was at 3%/10% on a 12px radius, which is close enough to look like a
 * near-miss and far enough to look like a different app.
 */
export const CARD = "rounded-2xl border border-white/[0.08] bg-white/[0.05]";

/** Same card, but it responds to a pointer because it opens something. */
export const CARD_INTERACTIVE =
  "rounded-2xl border border-white/[0.08] bg-white/[0.05] transition hover:border-white/20 hover:bg-white/[0.08]";

/**
 * SF Rounded is what every label in the app is set in
 * (`design: .rounded`). `ui-rounded` resolves to the real thing on Apple
 * platforms — where this dashboard is actually read — and Nunito is the
 * closest geometric-rounded stand-in everywhere else.
 */
export const ROUNDED_STACK =
  'ui-rounded, var(--font-nunito), "SF Pro Rounded", system-ui, -apple-system, sans-serif';
