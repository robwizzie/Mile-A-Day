import {
  Bell,
  Calendar,
  Camera,
  Crown,
  Flag,
  Flame,
  Footprints,
  Gift,
  Globe,
  Heart,
  Medal as MedalIcon,
  Moon,
  Mountain,
  Navigation,
  Rabbit,
  Snowflake,
  Sparkles,
  Star,
  Sun,
  Target,
  Timer,
  Trophy,
  Turtle,
  Users,
  Zap,
  type LucideIcon,
} from "lucide-react";

/**
 * The app's medal (Views/Components/MedalView.swift: `HangingMedal` =
 * `MedalRibbon` + loop + `MedalView`), drawn for the web from the same
 * geometry and the same `MedalPalette` colours. A badge's `icon` is the SF
 * Symbol the app stamps on it; SYMBOLS maps it to the closest lucide glyph.
 */
type Palette = {
  rimHi: string;
  rimLo: string;
  faceHi: string;
  faceLo: string;
  ink: string;
  inkShadow: string;
  glow: string;
  ribbonA: string;
  ribbonB: string;
  stripe: string;
};

// MedalPalette.forRarity, converted from the Swift RGB values.
const PALETTES: Record<string, Palette> = {
  legendary: {
    rimHi: "#FFED9E",
    rimLo: "#B37514",
    faceHi: "#FCD166",
    faceLo: "#CC8C1F",
    ink: "#FFFAE6",
    inkShadow: "rgba(115,66,0,0.55)",
    glow: "#FFBD33",
    ribbonA: "#C72938",
    ribbonB: "#8C1424",
    stripe: "#FFD666",
  },
  rare: {
    rimHi: "#E6D6FF",
    rimLo: "#6638AD",
    faceHi: "#B88FFA",
    faceLo: "#7342C7",
    ink: "#FFFFFF",
    inkShadow: "rgba(51,15,102,0.55)",
    glow: "#9E66F5",
    ribbonA: "#38338C",
    ribbonB: "#211C61",
    stripe: "#CCA8FF",
  },
  common: {
    rimHi: "#D6EBFF",
    rimLo: "#3366B8",
    faceHi: "#8CBDFC",
    faceLo: "#427AD6",
    ink: "#FFFFFF",
    inkShadow: "rgba(15,46,107,0.55)",
    glow: "#5294FA",
    ribbonA: "#294D9E",
    ribbonB: "#172E6B",
    stripe: "#B3DBFF",
  },
};

/** Rarity names and the colour the app writes them in. */
export const RARITY_LABEL: Record<string, { label: string; color: string }> = {
  legendary: { label: "Legendary", color: "#FFBD33" },
  rare: { label: "Rare", color: "#B88FFA" },
  common: { label: "Common", color: "#8CBDFC" },
};

const SYMBOLS: Record<string, LucideIcon> = {
  flame: Flame,
  bolt: Zap,
  location: Navigation,
  "figure.2": Users,
  "person.2": Users,
  "figure.walk": Footprints,
  "figure.run": Footprints,
  shoeprints: Footprints,
  star: Star,
  trophy: Trophy,
  crown: Crown,
  calendar: Calendar,
  medal: MedalIcon,
  heart: Heart,
  camera: Camera,
  moon: Moon,
  sun: Sun,
  "sun.max": Sun,
  sunrise: Sun,
  snowflake: Snowflake,
  timer: Timer,
  stopwatch: Timer,
  mountain: Mountain,
  "figure.hiking": Mountain,
  hare: Rabbit,
  tortoise: Turtle,
  sparkles: Sparkles,
  target: Target,
  flag: Flag,
  gift: Gift,
  globe: Globe,
  bell: Bell,
};

const CATEGORY_ICON: Record<string, LucideIcon> = {
  streak: Flame,
  miles: Footprints,
  pace: Zap,
  daily_distance: Navigation,
  buddy: Users,
  challenge: Trophy,
  weekly_challenge: Trophy,
  competition: Trophy,
};

function iconFor(symbol: string, category: string): LucideIcon {
  // "flame.fill" → "flame", "figure.2.circle.fill" → "figure.2"
  const base = symbol
    .replace(/\.(fill|circle|square)(\.fill)?$/g, "")
    .replace(/\.fill$/, "");
  return (
    SYMBOLS[base] ??
    SYMBOLS[base.split(".")[0]] ??
    CATEGORY_ICON[category] ??
    MedalIcon
  );
}

export function HangingMedal({
  icon,
  category,
  rarity,
  size = 72,
  id,
}: {
  icon: string;
  category: string;
  rarity: string;
  size?: number;
  /** Unique per medal on the page, for the SVG gradient ids. */
  id: string;
}) {
  const p = PALETTES[rarity] ?? PALETTES.common;
  const Icon = iconFor(icon, category);
  const g = (name: string) => `${id}-${name}`;
  // Geometry in a 100-wide box where the disc is 100 across (MedalRibbon /
  // HangingMedal ratios): ribbon spread 62, drop 62, strap 24; loop 16.
  const discTop = 62 - 16 * 0.45;
  const h = discTop + 100;

  return (
    <div
      className="relative shrink-0"
      style={{ width: size, height: (size * h) / 100 }}
    >
      <svg
        viewBox={`0 0 100 ${h}`}
        width={size}
        height={(size * h) / 100}
        aria-hidden="true"
        className="overflow-visible"
        style={{
          filter: `drop-shadow(0 ${size * 0.04}px ${size * 0.08}px ${p.glow}59)`,
        }}
      >
        <defs>
          <linearGradient id={g("rim")} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor={p.rimHi} />
            <stop offset="1" stopColor={p.rimLo} />
          </linearGradient>
          <linearGradient id={g("face")} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor={p.faceLo} />
            <stop offset="1" stopColor={p.faceHi} />
          </linearGradient>
          <linearGradient id={g("ring")} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor={p.rimHi} stopOpacity="0.9" />
            <stop offset="1" stopColor={p.rimLo} stopOpacity="0.6" />
          </linearGradient>
          <linearGradient id={g("strapL")} x1="0" y1="0" x2="1" y2="0">
            <stop offset="0" stopColor={p.ribbonA} />
            <stop offset="1" stopColor={p.ribbonB} />
          </linearGradient>
          <linearGradient id={g("strapR")} x1="0" y1="0" x2="1" y2="0">
            <stop offset="0" stopColor={p.ribbonB} />
            <stop offset="1" stopColor={p.ribbonA} />
          </linearGradient>
          <linearGradient id={g("shade")} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="#000" stopOpacity="0" />
            <stop offset="1" stopColor="#000" stopOpacity="0.3" />
          </linearGradient>
        </defs>

        {/* Neck ribbon: two straps meeting behind the loop, each with a stripe */}
        <g transform="translate(7 0)">
          {[
            { top: 0, fill: g("strapL") },
            { top: 62, fill: g("strapR") },
          ].map(({ top, fill }) => (
            <g key={top}>
              <polygon
                points={`${top},0 ${top + 24},0 ${31 + 24},62 31,62`}
                fill={`url(#${fill})`}
              />
              <polygon
                points={`${top + 9.6},0 ${top + 14.4},0 ${31 + 14.4},62 ${31 + 9.6},62`}
                fill={p.stripe}
                opacity="0.9"
              />
              <polygon
                points={`${top},0 ${top + 24},0 ${31 + 24},62 31,62`}
                fill={`url(#${g("shade")})`}
              />
            </g>
          ))}
        </g>
        {/* The loop the ribbon runs through */}
        <rect
          x={50 - 9.6}
          y={62 - 16 + 5.6}
          width={19.2}
          height={16}
          rx={8}
          fill="none"
          stroke={`url(#${g("rim")})`}
          strokeWidth={3.2}
        />

        {/* The disc: rim lit from the top, recessed face, fine inner ring, sheen */}
        <g transform={`translate(50 ${discTop + 50})`}>
          <circle r="50" fill={`url(#${g("rim")})`} />
          <circle
            r="49.6"
            fill="none"
            stroke="#fff"
            strokeOpacity="0.45"
            strokeWidth="0.8"
          />
          <circle
            r="42.5"
            fill={`url(#${g("face")})`}
            stroke="#000"
            strokeOpacity="0.22"
            strokeWidth="1.2"
          />
          <circle
            r="36.5"
            fill="none"
            stroke={`url(#${g("ring")})`}
            strokeWidth="1.4"
          />
          <path
            d={describeArc(40.5, 0.58, 0.92)}
            fill="none"
            stroke="#fff"
            strokeOpacity="0.22"
            strokeWidth="1.8"
            strokeLinecap="round"
          />
        </g>
      </svg>
      {/* The stamped icon, with the hard one-step shadow under it */}
      <Icon
        aria-hidden
        strokeWidth={2.6}
        className="absolute left-1/2 -translate-x-1/2 -translate-y-1/2"
        style={{
          top: `${((discTop + 50) / h) * 100}%`,
          width: size * 0.32,
          height: size * 0.32,
          color: p.ink,
          filter: `drop-shadow(0 ${Math.max(1, size * 0.012)}px 0 ${p.inkShadow})`,
        }}
      />
    </div>
  );
}

/** SwiftUI's Circle().trim(from:to:): fractions clockwise from 3 o'clock. */
function describeArc(r: number, from: number, to: number) {
  const pt = (f: number) => {
    const a = f * 2 * Math.PI;
    return `${(r * Math.cos(a)).toFixed(2)} ${(r * Math.sin(a)).toFixed(2)}`;
  };
  const large = to - from > 0.5 ? 1 : 0;
  return `M ${pt(from)} A ${r} ${r} 0 ${large} 1 ${pt(to)}`;
}
