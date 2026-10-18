import type { ReactNode } from "react";
import type { Cut, DesignId } from "@/lib/catalog";

// The drawn collection: one 400×440 box per side, neckline centred at the top
// so the hanger lands where it does on the photographed hoodie. Shared
// gradients and clip paths live once in <SharedDefs/> (a definition inside a
// display:none subtree — the rack that's hidden at phone width — stops
// rendering, so they can't live in each garment).

const RED = "#c72554";
const PINK = "#ff4d7d";
const EMBER = "#ff9a2e";
const COCOA = "#2a1410";

const SHAPE: Record<Cut, string> = {
  tee: "M148 24 C 166 46, 234 46, 252 24 L 322 44 C 344 52, 362 70, 372 96 L 398 152 L 340 178 L 318 140 L 318 420 C 250 432, 150 432, 82 420 L 82 140 L 60 178 L 2 152 L 28 96 C 38 70, 56 52, 78 44 Z",
  longsleeve:
    "M148 24 C 166 46, 234 46, 252 24 L 322 44 C 344 52, 360 72, 366 100 L 394 392 L 352 400 L 318 150 L 318 420 C 250 432, 150 432, 82 420 L 82 150 L 48 400 L 6 392 L 34 100 C 40 72, 56 52, 78 44 Z",
  tank: "M146 24 C 156 98, 244 98, 254 24 L 290 26 C 292 92, 306 126, 330 142 L 334 420 C 260 432, 140 432, 66 420 L 70 142 C 94 126, 108 92, 110 26 Z",
};

const COLLAR: Record<Cut, { front: string; back: string }> = {
  tee: { front: "M150 26 C 168 48, 232 48, 250 26", back: "M150 26 C 172 36, 228 36, 250 26" },
  longsleeve: { front: "M150 26 C 168 48, 232 48, 250 26", back: "M150 26 C 172 36, 228 36, 250 26" },
  tank: { front: "M148 26 C 158 98, 242 98, 252 26", back: "M148 26 C 160 66, 240 66, 252 26" },
};

const STITCH: Record<Cut, string[]> = {
  tee: ["M86 408 C 150 418, 250 418, 314 408", "M10 142 L 62 166", "M390 142 L 338 166"],
  longsleeve: ["M86 408 C 150 418, 250 418, 314 408", "M10 374 L 50 382", "M390 374 L 350 382"],
  tank: ["M70 408 C 140 418, 260 418, 330 408"],
};

const ARMHOLES = ["M110 26 C 108 92, 94 126, 70 142", "M290 26 C 292 92, 306 126, 330 142"];

export function SharedDefs() {
  return (
    <svg width="0" height="0" className="pointer-events-none absolute" aria-hidden="true" focusable="false">
      <DesignDefs />
    </svg>
  );
}

/** The definitions every drawn garment uses; inlined when rendering a
 *  standalone print (scripts/export-prints.tsx). */
export function DesignDefs() {
  return (
      <defs>
        <filter id="fold-blur" x="-20%" y="-20%" width="140%" height="140%">
          <feGaussianBlur stdDeviation="3" />
        </filter>
        <linearGradient id="flamey-body" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#ffe25a" />
          <stop offset="0.45" stopColor="#ff9a2e" />
          <stop offset="1" stopColor="#ff4b24" />
        </linearGradient>
        <linearGradient id="flamey-core" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#fff3a0" />
          <stop offset="1" stopColor="#ffc24a" />
        </linearGradient>
        <linearGradient id="hook-metal" x1="0" x2="1">
          <stop offset="0" stopColor="#5d5d5d" />
          <stop offset="0.5" stopColor="#dcdcdc" />
          <stop offset="1" stopColor="#6a6a6a" />
        </linearGradient>
        {(["light", "dark"] as const).map((tone) => (
          <linearGradient key={tone} id={`shade-${tone}`} x1="0" y1="0" x2="1" y2="0">
            <stop offset="0" stopColor="#000" stopOpacity={tone === "dark" ? 0.32 : 0.12} />
            <stop offset="0.2" stopColor="#000" stopOpacity="0" />
            <stop offset="0.8" stopColor="#000" stopOpacity="0" />
            <stop offset="1" stopColor="#000" stopOpacity={tone === "dark" ? 0.32 : 0.12} />
          </linearGradient>
        ))}
        {(["light", "dark"] as const).map((tone) => (
          <linearGradient key={tone} id={`sheen-${tone}`} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="#fff" stopOpacity={tone === "dark" ? 0.09 : 0.3} />
            <stop offset="0.5" stopColor="#fff" stopOpacity="0" />
            <stop offset="1" stopColor="#000" stopOpacity={tone === "dark" ? 0.2 : 0.06} />
          </linearGradient>
        ))}
        {(Object.keys(SHAPE) as Cut[]).map((cut) => (
          <clipPath key={cut} id={`clip-${cut}`}>
            <path d={SHAPE[cut]} />
          </clipPath>
        ))}
        <path id="arc-chest" d="M112 176 A 100 100 0 0 1 288 176" />
        <path id="arc-flamey" d="M108 166 A 96 96 0 0 1 292 166" />
      </defs>
  );
}

/** The blank garment, then the print on top. */
export function DrawnGarment({
  cut,
  color,
  design,
  side,
  className,
}: {
  cut: Cut;
  color: string;
  design: DesignId;
  side: "front" | "back";
  className?: string;
}) {
  const tone = luminance(color) < 0.35 ? "dark" : "light";
  const seam = tone === "dark" ? "rgba(255,255,255,0.14)" : "rgba(0,0,0,0.13)";
  const fold = tone === "dark" ? 0.38 : 0.07;
  return (
    <svg viewBox="0 0 400 440" className={className} aria-hidden="true" xmlns="http://www.w3.org/2000/svg">
      <path d={SHAPE[cut]} fill={color} />
      <g clipPath={`url(#clip-${cut})`}>
        <rect width="400" height="440" fill={`url(#shade-${tone})`} />
        <rect width="400" height="440" fill={`url(#sheen-${tone})`} />
        <path d="M122 250 C 150 300, 142 360, 130 430" stroke="#000" strokeOpacity={fold} strokeWidth="12" fill="none" filter="url(#fold-blur)" />
        <path d="M272 214 C 262 284, 286 352, 276 430" stroke="#000" strokeOpacity={fold * 0.8} strokeWidth="10" fill="none" filter="url(#fold-blur)" />
        {cut === "tank" && ARMHOLES.map((d) => <path key={d} d={d} stroke={seam} strokeWidth="9" fill="none" />)}
        {STITCH[cut].map((d) => (
          <path key={d} d={d} stroke={seam} strokeWidth="1.6" strokeDasharray="4 4" fill="none" />
        ))}
      </g>
      <path d={COLLAR[cut][side]} stroke={seam} strokeWidth="8" strokeLinecap="round" fill="none" />
      {PRINTS[design][side]}
      {side === "front" && PRINTS[design].sleeve && <g transform={SLEEVE_PLACEMENT}>{PRINTS[design].sleeve}</g>}
    </svg>
  );
}

// ── Prints ────────────────────────────────────────────────────────────────

/** Where a sleeve print sits on the drawn long sleeve (down the right arm). */
const SLEEVE_PLACEMENT = "translate(347 128) rotate(84.5)";

/**
 * One print on its own, for production (scripts/export-prints.tsx): no
 * garment, transparent, in the design's 400×440 box. A sleeve print is drawn
 * reading top-to-bottom, the way it runs down the arm.
 */
export function PrintOnly({ design, part }: { design: DesignId; part: "front" | "back" | "sleeve" }) {
  const art = PRINTS[design][part];
  if (!art) return null;
  return (
    <svg viewBox="0 0 400 440" xmlns="http://www.w3.org/2000/svg">
      <DesignDefs />
      {part === "sleeve" ? <g transform="translate(200 20) rotate(90)">{art}</g> : art}
    </svg>
  );
}

export function hasSleevePrint(design: DesignId) {
  return !!PRINTS[design].sleeve;
}

function T({
  x = 200,
  y,
  size,
  fill,
  children,
  ls = 1,
  anchor = "middle",
  font = "heading",
  weight,
  opacity,
}: {
  x?: number;
  y: number;
  size: number;
  fill: string;
  children: ReactNode;
  ls?: number;
  anchor?: "start" | "middle" | "end";
  font?: "heading" | "sans";
  weight?: number;
  opacity?: number;
}) {
  return (
    <text
      x={x}
      y={y}
      textAnchor={anchor}
      fontFamily={font === "heading" ? "var(--font-bebas-neue), Impact, sans-serif" : "var(--font-dm-sans), sans-serif"}
      fontSize={size}
      fontWeight={weight}
      letterSpacing={ls}
      fill={fill}
      opacity={opacity}
    >
      {children}
    </text>
  );
}

function Flame({ x, y, s = 1, fill }: { x: number; y: number; s?: number; fill: string }) {
  return (
    <path
      transform={`translate(${x} ${y}) scale(${s})`}
      d="M10 0 C 13 6, 20 10, 20 17 C 20 22.5, 15.5 26, 10 26 C 4.5 26, 0 22.5, 0 17 C 0 12.5, 3 10, 5 8 C 5.5 11, 7 12.5, 8.5 13 C 7.5 8, 8 4, 10 0 Z"
      fill={fill}
    />
  );
}

function SpeedLines({ x, y, ink, w = 22 }: { x: number; y: number; ink: string; w?: number }) {
  return (
    <g>
      {[0, 1, 2].map((i) => (
        <rect key={i} x={x + i * 5} y={y + (i - 1) * 9 - 2} width={w - i * 5} height="3.6" rx="1.8" fill={ink} opacity={0.75 - i * 0.18} />
      ))}
    </g>
  );
}

function MadBadge({ x, y, s = 1 }: { x: number; y: number; s?: number }) {
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <rect x="-24" y="-24" width="48" height="48" rx="13" fill={RED} />
      <rect x="-24" y="-24" width="48" height="24" rx="13" fill="#fff" opacity="0.1" />
      <T x={0} y={10} size={25} fill="#fff" ls={0.5}>
        MAD
      </T>
    </g>
  );
}

function Flamey({ x, y, s }: { x: number; y: number; s: number }) {
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <FlameyShape />
    </g>
  );
}

const DAYS = ["M", "T", "W", "T", "F", "S", "S"];

/** A print's parts: the chest, the back, and (some long sleeves) the right
 *  sleeve, drawn upright — the garment lays it along the sleeve. */
type Print = { front: ReactNode; back: ReactNode; sleeve?: ReactNode };

const PRINTS: Record<DesignId, Print> = {
  // White tee: a quiet chest badge, then the whole idea on the back.
  "daily-mile": {
    front: (
      <g>
        <MadBadge x={262} y={124} s={0.9} />
      </g>
    ),
    back: (
      <g>
        <T y={146} size={66} fill="#141210" ls={1.5}>
          ONE MILE.
        </T>
        <T y={204} size={66} fill="#141210" ls={1.5}>
          EVERY
        </T>
        <T y={262} size={66} fill={RED} ls={1.5}>
          DAY.
        </T>
        {DAYS.map((d, i) => {
          const x = 105 + i * 28;
          return (
            <g key={i}>
              <rect x={x} y={282} width="22" height="22" rx="6" fill={RED} />
              <path d={`M${x + 6} ${293} l4 4 l7 -8`} stroke="#fff" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round" fill="none" />
              <T x={x + 11} y={320} size={11} fill="#141210" opacity={0.55}>
                {d}
              </T>
            </g>
          );
        })}
        <T y={352} size={13} fill="#141210" ls={4} opacity={0.5}>
          MILEADAY.RUN
        </T>
      </g>
    ),
  },

  // Black tee: the app's one rule, and the number everyone's chasing.
  streak: {
    front: (
      <g>
        <Flame x={190} y={92} s={1} fill={RED} />
        <T y={160} size={38} fill="#f3efe9" ls={2}>
          {"DON'T BREAK"}
        </T>
        <T y={196} size={38} fill={RED} ls={2}>
          THE STREAK
        </T>
      </g>
    ),
    back: (
      <g>
        <text
          x="200"
          y="250"
          textAnchor="middle"
          fontFamily="var(--font-bebas-neue), Impact, sans-serif"
          fontSize="170"
          letterSpacing="2"
          fill="none"
          stroke={RED}
          strokeWidth="2.5"
          transform="translate(6 6)"
          opacity="0.55"
        >
          365
        </text>
        <T y={250} size={170} fill={RED} ls={2}>
          365
        </T>
        <T y={292} size={34} fill="#f3efe9" ls={8}>
          DAY STREAK
        </T>
        {[0, 1, 2, 3, 4].map((i) => (
          <Flame key={i} x={140 + i * 26} y={310} s={0.6} fill={i === 4 ? RED : "#f3efe9"} />
        ))}
        <T y={362} size={13} fill="#f3efe9" ls={4} opacity={0.45}>
          MILE A DAY
        </T>
      </g>
    ),
  },

  // Burgundy long sleeve: a sleeve print, and a route behind the mile.
  "extra-mile": {
    front: (
      <g>
        <SpeedLines x={226} y={118} ink="#f3efe9" w={20} />
        <T x={276} y={130} size={32} fill="#f3efe9" ls={1}>
          MAD
        </T>
      </g>
    ),
    sleeve: (
      <T x={0} y={0} size={19} fill="#f3efe9" ls={5} anchor="start" opacity={0.92}>
        GO THE EXTRA MILE
      </T>
    ),
    back: (
      <g>
        <path
          d="M104 318 C 132 268, 112 226, 160 206 S 244 232, 262 186 S 300 118, 296 92"
          stroke={PINK}
          strokeWidth="6"
          strokeLinecap="round"
          fill="none"
          opacity="0.9"
        />
        <circle cx="104" cy="318" r="8" fill="#f3efe9" />
        <circle cx="296" cy="92" r="8" fill={PINK} />
        <T y={236} size={124} fill="#f3efe9" ls={1}>
          1.00
        </T>
        <T x={292} y={170} size={22} fill="#f3efe9" anchor="start" opacity={0.8}>
          MI
        </T>
        <T y={290} size={25} fill="#f3efe9" ls={4}>
          EVERY. SINGLE. DAY.
        </T>
        <T y={356} size={13} fill="#f3efe9" ls={4} opacity={0.5}>
          GO THE EXTRA MILE
        </T>
      </g>
    ),
  },

  // Heather tank: collegiate run-club front, small mark on the back.
  "run-club": {
    front: (
      <g>
        <text
          fontFamily="var(--font-bebas-neue), Impact, sans-serif"
          fontSize="40"
          letterSpacing="4"
          fill="#8b1538"
          textAnchor="middle"
        >
          <textPath href="#arc-chest" startOffset="50%">
            MILE A DAY
          </textPath>
        </text>
        <T y={222} size={54} fill="#8b1538" ls={3}>
          RUN CLUB
        </T>
        <rect x="150" y="234" width="100" height="2.5" rx="1.25" fill="#8b1538" opacity="0.6" />
        <T y={258} size={12} fill="#8b1538" ls={5} opacity={0.85}>
          ONE MILE · EVERY DAY
        </T>
      </g>
    ),
    back: (
      <g>
        <T y={146} size={46} fill="#8b1538" ls={3}>
          MAD
        </T>
        <rect x="168" y="156" width="64" height="2.5" rx="1.25" fill="#8b1538" opacity="0.6" />
        <T y={180} size={16} fill="#8b1538" ls={6} opacity={0.85}>
          1 MI / DAY
        </T>
      </g>
    ),
  },

  // Cream tee: Flamey front and centre.
  "flamey-lit": {
    front: (
      <g>
        <text
          fontFamily="var(--font-bebas-neue), Impact, sans-serif"
          fontSize="34"
          letterSpacing="5"
          fill={COCOA}
          textAnchor="middle"
        >
          <textPath href="#arc-flamey" startOffset="50%">
            KEEP IT LIT
          </textPath>
        </text>
        <Flamey x={140} y={118} s={0.6} />
        <T y={292} size={15} fill={COCOA} ls={5} opacity={0.75}>
          MILE A DAY
        </T>
      </g>
    ),
    back: (
      <g>
        <Flamey x={176} y={70} s={0.24} />
        <T y={172} size={56} fill={COCOA} ls={2}>
          STILL LIT.
        </T>
        <T y={198} size={13} fill={COCOA} ls={4} opacity={0.7}>
          DAY AFTER DAY AFTER DAY
        </T>
      </g>
    ),
  },

  // Black long sleeve: Flamey's run crew.
  "flamey-crew": {
    front: (
      <g>
        <Flamey x={248} y={96} s={0.22} />
      </g>
    ),
    sleeve: (
      <T x={0} y={0} size={19} fill={EMBER} ls={5} anchor="start">
        FLAMEY RUN CREW
      </T>
    ),
    back: (
      <g>
        {[0, 1, 2].map((i) => (
          <rect key={i} x={86 + i * 8} y={170 + i * 22} width={56 - i * 12} height="6" rx="3" fill={EMBER} opacity={0.85 - i * 0.22} />
        ))}
        <Flamey x={136} y={104} s={0.64} />
        <T y={326} size={46} fill="#f3efe9" ls={4}>
          RUN CREW
        </T>
        <T y={350} size={12} fill={EMBER} ls={5}>
          ONE MILE · EVERY DAY
        </T>
      </g>
    ),
  },
};

/** Flamey, the app's mascot, in a 200×240 box. Gradients from <SharedDefs/>. */
export function FlameyShape() {
  return (
    <g>
      <rect x="66" y="176" width="26" height="50" rx="13" fill="#ff5a2a" />
      <rect x="108" y="176" width="26" height="50" rx="13" fill="#ff5a2a" />
      <ellipse cx="79" cy="226" rx="20" ry="9" fill="#ff4b24" />
      <ellipse cx="121" cy="226" rx="20" ry="9" fill="#ff4b24" />
      <path d="M44 132 C 30 118, 26 100, 30 88" stroke="#ff7a2a" strokeWidth="18" strokeLinecap="round" fill="none" />
      <path d="M156 132 C 170 118, 174 100, 170 88" stroke="#ff7a2a" strokeWidth="18" strokeLinecap="round" fill="none" />
      <circle cx="30" cy="84" r="13" fill="#ff9a3a" />
      <circle cx="170" cy="84" r="13" fill="#ff9a3a" />
      <path
        d="M100 6 C 128 40, 168 76, 166 136 C 164 176, 136 194, 100 194 C 64 194, 36 176, 34 136 C 32 104, 46 84, 60 70 C 62 88, 68 98, 76 102 C 72 66, 82 36, 100 6 Z"
        fill="url(#flamey-body)"
        stroke="#fff"
        strokeOpacity="0.35"
        strokeWidth="3"
      />
      <path d="M100 66 C 112 86, 124 104, 120 128 C 116 144, 84 144, 80 128 C 76 108, 90 90, 100 66 Z" fill="url(#flamey-core)" />
      <ellipse cx="78" cy="132" rx="11" ry="13" fill={COCOA} />
      <ellipse cx="122" cy="132" rx="11" ry="13" fill={COCOA} />
      <circle cx="74" cy="127" r="3.5" fill="#fff" />
      <circle cx="118" cy="127" r="3.5" fill="#fff" />
      <path d="M78 152 C 86 172, 114 172, 122 152 Z" fill={COCOA} />
      <path d="M90 164 C 96 170, 104 170, 110 164 C 106 160, 94 160, 90 164 Z" fill="#ff6f7d" />
    </g>
  );
}

function luminance(hex: string) {
  const n = parseInt(hex.slice(1), 16);
  return (0.299 * ((n >> 16) & 255) + 0.587 * ((n >> 8) & 255) + 0.114 * (n & 255)) / 255;
}
