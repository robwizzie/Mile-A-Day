"use client";

import { useId } from "react";
import { Check, Hand, Lock, MessageCircle, Pencil, Play } from "lucide-react";
import { ProfileAvatar } from "@/components/profile-avatar";

// Drawn mockups of what shipped in the current release. They follow the
// app's own look (MADTheme colours, Route Art's dark canvas, the Closet's
// 4-up item tiles) so the site shows the real feature, not a generic icon.

const MAD_RED = "#D94059";
const WALK_BLUE = "#4A9FF5";
const HYPE_ORANGE = "#FF9900";
const SUCCESS = "#34C759";

// ── Flamey ─────────────────────────────────────────────────────────────

type Outfit = { crown?: boolean; shades?: boolean; running?: boolean };

/** The Fun dashboard's mascot: a flame with a face, stubby arms and legs. */
export function Flamey({
  size = 120,
  outfit = {},
  className,
}: {
  size?: number;
  outfit?: Outfit;
  className?: string;
}) {
  const id = useId().replace(/:/g, "");
  const outer = `fo${id}`;
  const inner = `fi${id}`;
  const glow = `fg${id}`;
  return (
    <svg
      viewBox="0 0 120 150"
      width={size}
      height={size * 1.25}
      className={className}
      aria-hidden
    >
      <defs>
        <linearGradient id={outer} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#FFC24A" />
          <stop offset="55%" stopColor="#FF7A2F" />
          <stop offset="100%" stopColor="#E8433A" />
        </linearGradient>
        <linearGradient id={inner} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#FFF3B0" />
          <stop offset="100%" stopColor="#FFC94A" />
        </linearGradient>
        <radialGradient id={glow}>
          <stop offset="0%" stopColor="#FF8A3D" stopOpacity="0.45" />
          <stop offset="100%" stopColor="#FF8A3D" stopOpacity="0" />
        </radialGradient>
      </defs>

      <ellipse cx="60" cy="88" rx="58" ry="58" fill={`url(#${glow})`} />
      <ellipse cx="60" cy="143" rx="26" ry="4" fill="#000" opacity="0.35" />

      {/* legs */}
      {outfit.running ? (
        <>
          <path
            d="M50 124 L42 136"
            stroke="#E8433A"
            strokeWidth="7"
            strokeLinecap="round"
          />
          <path
            d="M70 124 L80 134"
            stroke="#E8433A"
            strokeWidth="7"
            strokeLinecap="round"
          />
          <ellipse cx="40" cy="138" rx="7" ry="4" fill="#2b2b2b" />
          <ellipse cx="83" cy="136" rx="7" ry="4" fill="#2b2b2b" />
        </>
      ) : (
        <>
          <path
            d="M50 124 L49 136"
            stroke="#E8433A"
            strokeWidth="7"
            strokeLinecap="round"
          />
          <path
            d="M70 124 L71 136"
            stroke="#E8433A"
            strokeWidth="7"
            strokeLinecap="round"
          />
          <ellipse cx="47" cy="139" rx="8" ry="4.2" fill="#2b2b2b" />
          <ellipse cx="73" cy="139" rx="8" ry="4.2" fill="#2b2b2b" />
        </>
      )}

      {/* arms */}
      <path
        d={outfit.running ? "M28 92 Q18 84 16 74" : "M27 94 Q14 90 10 78"}
        stroke="#FF7A2F"
        strokeWidth="7"
        strokeLinecap="round"
        fill="none"
      />
      <path
        d={outfit.running ? "M92 92 Q104 98 108 108" : "M93 94 Q106 90 110 78"}
        stroke="#FF7A2F"
        strokeWidth="7"
        strokeLinecap="round"
        fill="none"
      />

      {/* body */}
      <path
        d="M60 10 C72 32 98 46 98 86 C98 112 81 128 60 128 C39 128 22 112 22 86 C22 64 34 54 40 40 C44 54 50 58 54 60 C52 42 54 24 60 10 Z"
        fill={`url(#${outer})`}
      />
      <path
        d="M60 54 C68 68 84 78 84 96 C84 112 73 121 60 121 C47 121 36 112 36 98 C36 84 48 78 51 68 C55 74 57 76 60 78 C58 70 58 62 60 54 Z"
        fill={`url(#${inner})`}
      />

      {/* face */}
      {outfit.shades ? (
        <g>
          <rect x="39" y="81" width="18" height="11" rx="5" fill="#141414" />
          <rect x="63" y="81" width="18" height="11" rx="5" fill="#141414" />
          <path d="M57 85 L63 85" stroke="#141414" strokeWidth="3" />
          <path
            d="M42 84 L48 84"
            stroke="#fff"
            strokeOpacity="0.5"
            strokeWidth="2"
            strokeLinecap="round"
          />
          <path
            d="M66 84 L72 84"
            stroke="#fff"
            strokeOpacity="0.5"
            strokeWidth="2"
            strokeLinecap="round"
          />
        </g>
      ) : (
        <g>
          <ellipse cx="50" cy="87" rx="4" ry="5.5" fill="#1a1a1a" />
          <ellipse cx="70" cy="87" rx="4" ry="5.5" fill="#1a1a1a" />
          <circle cx="51.4" cy="85" r="1.5" fill="#fff" />
          <circle cx="71.4" cy="85" r="1.5" fill="#fff" />
        </g>
      )}
      <path
        d="M51 101 Q60 109 69 101"
        stroke="#1a1a1a"
        strokeWidth="3"
        strokeLinecap="round"
        fill="none"
      />
      <ellipse cx="42" cy="99" rx="4" ry="2.4" fill="#FF5E5E" opacity="0.45" />
      <ellipse cx="78" cy="99" rx="4" ry="2.4" fill="#FF5E5E" opacity="0.45" />

      {outfit.crown && (
        <g transform="translate(60 32)">
          <path
            d="M-17 8 L-19 -10 L-9 -2 L0 -14 L9 -2 L19 -10 L17 8 Z"
            fill="#FFD659"
            stroke="#D98C26"
            strokeWidth="2"
            strokeLinejoin="round"
          />
          <circle cx="0" cy="-1" r="3" fill={MAD_RED} />
          <circle cx="-11" cy="3" r="2" fill={WALK_BLUE} />
          <circle cx="11" cy="3" r="2" fill={WALK_BLUE} />
        </g>
      )}
    </svg>
  );
}

// ── Closet item art (the 4-up tiles) ───────────────────────────────────

function ItemArt({ kind }: { kind: string }) {
  switch (kind) {
    case "crown":
      return (
        <svg viewBox="0 0 40 40" className="h-9 w-9">
          <path
            d="M6 30 L4 12 L14 20 L20 8 L26 20 L36 12 L34 30 Z"
            fill="#FFD659"
            stroke="#D98C26"
            strokeWidth="2"
            strokeLinejoin="round"
          />
          <circle cx="20" cy="22" r="2.6" fill={MAD_RED} />
        </svg>
      );
    case "shades":
      return (
        <svg viewBox="0 0 40 40" className="h-9 w-9">
          <rect
            x="4"
            y="15"
            width="14"
            height="10"
            rx="4.5"
            fill="#1d1d1d"
            stroke="#555"
          />
          <rect
            x="22"
            y="15"
            width="14"
            height="10"
            rx="4.5"
            fill="#1d1d1d"
            stroke="#555"
          />
          <path d="M18 19 L22 19" stroke="#555" strokeWidth="2" />
        </svg>
      );
    case "beanie":
      return (
        <svg viewBox="0 0 40 40" className="h-9 w-9">
          <path d="M8 26 C8 14 32 14 32 26 Z" fill={WALK_BLUE} />
          <rect x="6" y="25" width="28" height="6" rx="3" fill="#2F78C4" />
          <circle cx="20" cy="11" r="4" fill="#fff" />
        </svg>
      );
    case "party":
      return (
        <svg viewBox="0 0 40 40" className="h-9 w-9">
          <path d="M20 5 L31 33 L9 33 Z" fill="#BF5AF2" />
          <path
            d="M14 21 L26 21 M12 27 L28 27"
            stroke="#FFD659"
            strokeWidth="2.5"
          />
          <circle cx="20" cy="5" r="3" fill="#FFD659" />
        </svg>
      );
    case "cape":
      return (
        <svg viewBox="0 0 40 40" className="h-9 w-9">
          <path d="M12 8 L28 8 L34 33 Q20 29 6 33 Z" fill={MAD_RED} />
          <path d="M28 8 L34 33 Q31 32 28 31 Z" fill="#8b1538" />
        </svg>
      );
    case "shoes":
      return (
        <svg viewBox="0 0 40 40" className="h-9 w-9">
          <path
            d="M5 26 C5 20 12 17 16 18 C20 22 26 22 31 23 C35 24 36 27 35 30 L6 30 Z"
            fill="#63E6BE"
          />
          <rect x="5" y="29" width="31" height="3" rx="1.5" fill="#f5f5f5" />
        </svg>
      );
    case "pumpkin":
      return (
        <svg viewBox="0 0 40 40" className="h-9 w-9">
          <ellipse cx="20" cy="23" rx="14" ry="11" fill="#FF8A1F" />
          <path
            d="M20 12 L21 7"
            stroke="#3a7a2a"
            strokeWidth="3"
            strokeLinecap="round"
          />
          <path
            d="M14 13 Q12 23 14 33 M26 13 Q28 23 26 33"
            stroke="#D96B10"
            strokeWidth="1.6"
            fill="none"
          />
        </svg>
      );
    default:
      return (
        <svg viewBox="0 0 40 40" className="h-9 w-9">
          <path
            d="M20 6 L23 16 L34 16 L25 22 L28 33 L20 26 L12 33 L15 22 L6 16 L17 16 Z"
            fill="#FFD659"
          />
        </svg>
      );
  }
}

const CLOSET_TILES = [
  { kind: "crown", worn: true, medal: "#FFD659" },
  { kind: "shades", worn: true, medal: "#BF5AF2" },
  { kind: "beanie", medal: "#0A84FF" },
  { kind: "party", medal: "#BF5AF2" },
  { kind: "cape", medal: "#FF9F0A" },
  { kind: "shoes", medal: "#0A84FF" },
  { kind: "pumpkin", locked: true, medal: "#555" },
  { kind: "star", locked: true, medal: "#555" },
];

/** Flamey's Closet: the pinned stage over the item grid. */
export function ClosetMockup() {
  return (
    <div className="flex h-full flex-col rounded-[22px] bg-[#120c0d] p-4">
      <div className="flex items-center justify-between">
        <span className="text-[15px] font-bold text-white">
          Sparky&apos;s Closet
        </span>
        <span className="rounded-full bg-white/10 px-3 py-1 text-[11px] font-semibold text-white/80">
          Done
        </span>
      </div>

      <div
        className="relative mt-3 flex flex-col items-center rounded-2xl pb-3 pt-9"
        style={{
          background:
            "radial-gradient(circle at 50% 60%, rgba(255,138,61,0.16), transparent 70%)",
        }}
      >
        <div className="absolute left-1/2 top-2 -translate-x-1/2 whitespace-nowrap rounded-full bg-white px-3 py-1 text-[11px] font-bold text-[#1a1a1a] shadow-lg">
          Lookin&apos; sharp!
          <span className="absolute -bottom-1 left-1/2 h-2 w-2 -translate-x-1/2 rotate-45 bg-white" />
        </div>
        <Flamey size={104} outfit={{ crown: true, shades: true }} />
        <span className="mt-1 inline-flex items-center gap-1 text-[12px] font-semibold text-white/80">
          Sparky <Pencil className="h-3 w-3 text-white/45" />
        </span>
      </div>

      <div className="mt-3 flex gap-1.5 text-[10px] font-semibold">
        {["Flame", "Head & face", "Outfit", "Pals"].map((t) => (
          <span
            key={t}
            className={`rounded-full px-2.5 py-1 ${t === "Head & face" ? "bg-white text-[#1a1a1a]" : "bg-white/[0.06] text-white/55"}`}
          >
            {t}
          </span>
        ))}
      </div>

      <div className="mt-3 grid grid-cols-4 gap-2">
        {CLOSET_TILES.map((tile) => (
          <div
            key={tile.kind}
            className={`relative flex aspect-square items-center justify-center rounded-xl border ${
              tile.worn
                ? "border-[#34C759]/60 bg-[#34C759]/10"
                : "border-white/[0.06] bg-white/[0.04]"
            }`}
          >
            <div className={tile.locked ? "opacity-25 grayscale" : ""}>
              <ItemArt kind={tile.kind} />
            </div>
            {tile.locked && (
              <Lock className="absolute h-3.5 w-3.5 text-white/60" />
            )}
            {tile.worn && (
              <span
                className="absolute -right-1 -top-1 flex h-4 w-4 items-center justify-center rounded-full"
                style={{ background: SUCCESS }}
              >
                <Check className="h-2.5 w-2.5 text-white" strokeWidth={4} />
              </span>
            )}
            <span
              className="absolute bottom-1 right-1 h-2.5 w-2.5 rounded-full border border-black/40"
              style={{ background: tile.medal }}
            />
          </div>
        ))}
      </div>
      <p className="mt-3 text-center text-[10px] text-white/45">
        Crown · from your 100-Day Streak medal
      </p>
    </div>
  );
}

// ── Route Art feed card ────────────────────────────────────────────────

// A loop around a park, in a 300×300 canvas. The first and last stretch are
// drawn fading out: friends see the route with its ends trimmed.
const ROUTE_D =
  "M70 238 C62 200 58 170 74 140 C90 110 84 82 108 64 C134 44 170 50 196 62 C224 76 244 98 240 130 C236 160 214 172 216 198 C218 222 238 236 222 252 C204 268 170 258 146 252 C120 246 96 256 82 250";

/** A friend's walk on the feed: Route Art, Flamey running beside them, and
 * the Flyover chip under the media. */
export function RouteCardMockup() {
  const id = useId().replace(/:/g, "");
  return (
    <div className="flex h-full flex-col rounded-[22px] bg-[#0d0d0d] p-3">
      <div className="mb-2.5 flex items-center gap-2.5">
        <ProfileAvatar username="MegsMiles" initials="MM" size={34} />
        <div className="min-w-0 flex-1">
          <div className="truncate text-[13px] font-bold text-white">Megs</div>
          <div className="text-[11px] font-medium text-white/50">
            Walk · 1.42 mi · 2h
          </div>
        </div>
      </div>

      <div className="relative aspect-square overflow-hidden rounded-xl bg-[#0f1116]">
        {/* Fun-style dot grid */}
        <div
          className="absolute inset-0 opacity-60"
          style={{
            backgroundImage:
              "radial-gradient(rgba(255,255,255,0.09) 1px, transparent 1px)",
            backgroundSize: "14px 14px",
          }}
        />
        <svg viewBox="0 0 300 300" className="absolute inset-0 h-full w-full">
          <defs>
            <mask id={`m${id}`}>
              <rect width="300" height="300" fill="white" />
              <circle cx="72" cy="244" r="34" fill={`url(#rg${id})`} />
            </mask>
            <radialGradient id={`rg${id}`}>
              <stop offset="0.35" stopColor="black" />
              <stop offset="1" stopColor="white" />
            </radialGradient>
          </defs>
          <g mask={`url(#m${id})`}>
            <path
              d={ROUTE_D}
              fill="none"
              stroke={WALK_BLUE}
              strokeOpacity="0.25"
              strokeWidth="14"
              strokeLinecap="round"
            />
            <path
              d={ROUTE_D}
              fill="none"
              stroke={WALK_BLUE}
              strokeWidth="5"
              strokeLinecap="round"
            />
          </g>
          {/* mile ticks */}
          {[
            [196, 62],
            [216, 198],
          ].map(([x, y]) => (
            <g key={`${x}`}>
              <circle
                cx={x}
                cy={y}
                r="10"
                fill="#0f1116"
                stroke="#fff"
                strokeWidth="2"
              />
              <text
                x={x}
                y={y + 3}
                textAnchor="middle"
                fontSize="7.5"
                fontWeight="700"
                fill="#fff"
              >
                {x === 196 ? 0.5 : 1}
              </text>
            </g>
          ))}
          {/* rider */}
          <circle cx="240" cy="130" r="13" fill={WALK_BLUE} />
          <circle cx="240" cy="130" r="10.5" fill="#1d2a3a" />
          <text
            x="240"
            y="134"
            textAnchor="middle"
            fontSize="9"
            fontWeight="700"
            fill="#fff"
          >
            MM
          </text>
        </svg>
        <div className="absolute" style={{ left: "84%", top: "44%" }}>
          <Flamey size={30} outfit={{ running: true }} />
        </div>

        <div className="absolute inset-x-0 bottom-0 flex justify-between bg-gradient-to-t from-black/85 to-transparent px-3 pb-2.5 pt-8 text-white">
          {[
            ["1.42", "MI"],
            ["26:18", "TIME"],
            ["18:31", "/MI"],
          ].map(([v, l]) => (
            <div key={l} className="text-center">
              <div className="font-heading text-[20px] leading-none">{v}</div>
              <div className="text-[8px] font-semibold tracking-widest text-white/55">
                {l}
              </div>
            </div>
          ))}
        </div>
      </div>

      <div className="mt-2.5 flex items-center gap-2">
        <span
          className="flex h-8 items-center gap-1.5 rounded-full px-3 text-[12px] font-bold text-white"
          style={{ background: HYPE_ORANGE }}
        >
          <Hand className="h-3.5 w-3.5" /> 12
        </span>
        <MessageCircle className="h-4 w-4 text-white/55" />
        <span
          className="ml-auto inline-flex h-7 items-center gap-1.5 rounded-full pl-1 pr-2.5 text-[10px] font-bold tracking-wide text-white"
          style={{ background: WALK_BLUE }}
        >
          <span className="flex h-5 w-5 items-center justify-center rounded-full bg-white">
            <Play
              className="h-2.5 w-2.5 fill-current"
              style={{ color: WALK_BLUE }}
            />
          </span>
          FLYOVER
        </span>
      </div>
      <p className="mt-2 text-[11px] text-white/45">
        🔥 87-day streak · start &amp; end hidden from friends
      </p>
    </div>
  );
}

// ── Weekly Recap ───────────────────────────────────────────────────────

const WEEK = [
  { d: "S", mi: 1.1 },
  { d: "M", mi: 1.3 },
  { d: "T", mi: 1.0 },
  { d: "W", mi: 1.6 },
  { d: "T", mi: 2.1, best: true },
  { d: "F", mi: 1.2 },
  { d: "S", mi: 1.4 },
];

/** Saturday evening's Weekly Recap (Sunday → Saturday). */
export function WeeklyRecapMockup() {
  const total = WEEK.reduce((s, d) => s + d.mi, 0);
  const max = Math.max(...WEEK.map((d) => d.mi));
  return (
    <div className="flex h-full flex-col rounded-[22px] bg-[#0f0d14] p-4">
      <span className="text-[10px] font-bold uppercase tracking-[0.18em] text-[#8f8dff]">
        Your week
      </span>
      <span className="text-[13px] font-semibold text-white/70">
        Sep 27 – Oct 3
      </span>
      <div className="mt-3 flex items-end gap-2">
        <span className="font-heading text-[54px] leading-[0.85] text-white">
          {total.toFixed(1)}
        </span>
        <span className="mb-1 text-[13px] font-semibold text-white/55">
          miles
        </span>
      </div>
      <span className="mt-1 inline-flex w-fit items-center gap-1 rounded-full bg-[#34C759]/15 px-2.5 py-1 text-[11px] font-bold text-[#34C759]">
        <Check className="h-3 w-3" strokeWidth={3} /> 7 of 7 days
      </span>

      <div className="mt-5 flex h-[104px] items-end justify-between gap-2">
        {WEEK.map((day, i) => (
          <div key={i} className="flex flex-1 flex-col items-center gap-1.5">
            <div
              className="w-full rounded-md"
              style={{
                height: `${(day.mi / max) * 84}px`,
                background: day.best
                  ? "linear-gradient(180deg,#a5a3ff,#5E5CE6)"
                  : "rgba(255,255,255,0.12)",
              }}
            />
            <span
              className={`text-[10px] font-bold ${day.best ? "text-white" : "text-white/40"}`}
            >
              {day.d}
            </span>
          </div>
        ))}
      </div>
      <p className="mt-3 text-[12px] text-white/60">
        Best day:{" "}
        <span className="font-semibold text-white">Thursday · 2.1 mi</span>
      </p>

      <div className="mt-4 space-y-2 border-t border-white/[0.06] pt-3">
        {[
          { name: "You", username: "rob", initials: "RW", mi: total },
          { name: "Megs", username: "MegsMiles", initials: "MM", mi: 8.2 },
          { name: "David", username: "dave", initials: "DS", mi: 7.4 },
        ].map((f, i) => (
          <div key={f.name} className="flex items-center gap-2.5">
            <span className="w-3 text-[11px] font-bold text-white/40">
              {i + 1}
            </span>
            <ProfileAvatar
              username={f.username}
              initials={f.initials}
              size={22}
            />
            <span className="flex-1 text-[12px] font-semibold text-white/85">
              {f.name}
            </span>
            <span className="text-[12px] font-bold tabular-nums text-white">
              {f.mi.toFixed(1)} mi
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
