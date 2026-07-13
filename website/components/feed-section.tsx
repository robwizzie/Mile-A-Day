"use client";

import { useRef, useCallback, useState } from "react";
import {
  Camera,
  Flame,
  Gauge,
  Footprints,
  Hand,
  Hourglass,
  Map,
  MoreHorizontal,
  Plus,
} from "lucide-react";
import { ProfileAvatar } from "@/components/profile-avatar";
import { usePublicUser } from "@/lib/public-user";

// App palette (MADTheme). Hype is ALWAYS represented by a clap/hand action in
// Mile A Day — the button is solid orange, the tally icon is orange.
const MAD_RED = "#D94059";
const HYPE_ORANGE = "#FF9900";

const STORY_FRIENDS = [
  { username: "dave", initials: "DS", label: "David" },
  { username: "MegsMiles", initials: "MM", label: "Megs" },
];

function TiltCard({
  children,
  className,
}: {
  children: React.ReactNode;
  className?: string;
}) {
  const cardRef = useRef<HTMLDivElement>(null);

  const handleMouseMove = useCallback((e: React.MouseEvent<HTMLDivElement>) => {
    const card = cardRef.current;
    if (!card) return;
    const rect = card.getBoundingClientRect();
    const x = (e.clientX - rect.left) / rect.width - 0.5;
    const y = (e.clientY - rect.top) / rect.height - 0.5;
    card.style.transform = `perspective(600px) rotateY(${x * 8}deg) rotateX(${y * -8}deg) scale(1.01)`;
  }, []);

  const handleMouseLeave = useCallback(() => {
    const card = cardRef.current;
    if (!card) return;
    card.style.transform =
      "perspective(600px) rotateY(0deg) rotateX(0deg) scale(1)";
  }, []);

  return (
    <div
      ref={cardRef}
      className={`transition-transform duration-200 ease-out ${className ?? ""}`}
      onMouseMove={handleMouseMove}
      onMouseLeave={handleMouseLeave}
      style={{ transformStyle: "preserve-3d" }}
    >
      {children}
    </div>
  );
}

/** Story ring, exactly like StoriesRailView: unviewed = red→orange gradient
 * ring, dashed white ring for "Your story" with nothing posted yet. */
function StoryRing({
  children,
  unviewed,
  dashed,
}: {
  children: React.ReactNode;
  unviewed?: boolean;
  dashed?: boolean;
}) {
  if (unviewed) {
    return (
      <div
        className="rounded-full p-[2.5px]"
        style={{
          background: `linear-gradient(135deg, ${MAD_RED}, ${HYPE_ORANGE})`,
        }}
      >
        <div className="rounded-full border-[3px] border-[#0d0d0d]">
          {children}
        </div>
      </div>
    );
  }
  return (
    <div
      className="rounded-full p-[2.5px]"
      style={{
        border: `2.5px ${dashed ? "dashed" : "solid"} rgba(255,255,255,0.25)`,
      }}
    >
      {children}
    </div>
  );
}

/** "Your story" cell — the viewer's own avatar in a dashed ring with the red
 * add badge bottom-right, exactly like the app's addCell. */
function YourStoryCell() {
  return (
    <div className="flex w-[62px] flex-col items-center gap-1.5">
      <div className="relative">
        <StoryRing dashed>
          <ProfileAvatar username="rob" initials="RW" size={46} />
        </StoryRing>
        <div
          className="absolute -bottom-0.5 -right-0.5 flex h-[18px] w-[18px] items-center justify-center rounded-full border-2 border-[#0d0d0d]"
          style={{ background: MAD_RED }}
        >
          <Plus className="h-3 w-3 text-white" strokeWidth={3} />
        </div>
      </div>
      <span className="text-[10px] font-semibold text-white/70">
        Your story
      </span>
    </div>
  );
}

function FriendStoryCell({
  username,
  initials,
  label,
}: {
  username: string;
  initials: string;
  label: string;
}) {
  return (
    <div className="flex w-[62px] flex-col items-center gap-1.5">
      <StoryRing unviewed>
        <ProfileAvatar username={username} initials={initials} size={46} />
      </StoryRing>
      <span className="max-w-full truncate text-[10px] font-semibold text-white/70">
        {label}
      </span>
    </div>
  );
}

/** Radiating mini claps for the burst — precomputed offsets so the render is
 * deterministic. */
const MINI_CLAPS = Array.from({ length: 6 }, (_, i) => {
  const angle = (i / 6) * Math.PI * 2 - Math.PI / 2;
  return {
    dx: Math.round(Math.cos(angle) * 74),
    dy: Math.round(Math.sin(angle) * 74),
  };
});

/** One post, faithful to PostCardView: author header (avatar, name, relative
 * time, activity chip, ellipsis menu) → 4:5 media with page dots → stat strip
 * chips → caption → footer with the hype tally left and the solid-orange
 * clap Hype button right. No comments — hypes ARE the social currency. */
function FeedPostCard() {
  const rob = usePublicUser("rob");
  const streak = rob?.currentStreak ?? 427;
  const [hyped, setHyped] = useState(false);
  const [burst, setBurst] = useState(0);

  // Mirrors doubleTapHype(): the burst replays on every double-tap, but the
  // hype itself only counts once.
  const hype = useCallback(() => {
    setBurst((b) => b + 1);
    setHyped(true);
  }, []);

  return (
    <div className="rounded-2xl bg-white/[0.04] p-2.5">
      {/* Header */}
      <div className="flex items-center gap-2.5 px-1 pb-2 pt-0.5">
        <ProfileAvatar username="rob" initials="RW" size={40} />
        <div className="min-w-0 flex-1">
          <div className="truncate text-[15px] font-bold leading-tight text-white">
            Rob
          </div>
          <div className="text-xs font-medium text-white/50">2h ago</div>
        </div>
        <div
          className="flex h-[30px] w-[30px] items-center justify-center rounded-full"
          style={{ background: `${MAD_RED}26` }}
        >
          <Footprints className="h-4 w-4" style={{ color: MAD_RED }} />
        </div>
        <MoreHorizontal className="h-4 w-4 text-white/60" />
      </div>

      {/* Media — 4:5 like the app, double-tap (or double-click) to hype */}
      <div
        className="relative aspect-[4/5] cursor-pointer select-none overflow-hidden rounded-xl"
        onDoubleClick={hype}
        style={{
          background:
            "linear-gradient(165deg, #3a1c28 0%, #1c1016 45%, #0e1812 100%)",
        }}
      >
        {/* Run photo mock: visible enough to read as content on a dark page. */}
        <div
          className="absolute inset-0"
          style={{
            background:
              "linear-gradient(180deg, rgba(217,64,89,0.34) 0%, rgba(255,153,0,0.2) 38%, rgba(9,22,15,0.92) 100%)",
          }}
        />
        <div
          className="absolute left-[18%] top-[18%] h-20 w-20 rounded-full blur-sm"
          style={{
            background: `radial-gradient(circle, ${HYPE_ORANGE} 0%, rgba(255,153,0,0.42) 42%, transparent 70%)`,
          }}
        />
        <div className="absolute bottom-0 left-0 right-0 h-[48%] bg-gradient-to-t from-[#07120d] via-[#102016] to-transparent" />
        <div className="absolute bottom-0 left-1/2 h-[54%] w-[42%] -translate-x-1/2 skew-x-[-8deg] bg-black/25" />
        <div className="absolute bottom-0 left-[48%] h-[52%] w-[2px] rotate-[8deg] bg-white/20" />
        <div
          className="absolute bottom-[18%] left-[18%] right-[16%] h-[36%] rounded-full border-2 border-dashed opacity-80"
          style={{
            borderColor: `${HYPE_ORANGE}CC`,
            transform: "rotate(-18deg)",
          }}
        />
        <div className="absolute left-4 top-4 rounded-full bg-black/30 px-2.5 py-1 text-[11px] font-extrabold text-white/90 backdrop-blur">
          Morning mile
        </div>
        <div className="absolute bottom-8 right-4 rounded-xl bg-black/35 px-3 py-2 text-right backdrop-blur">
          <div className="text-[10px] font-bold uppercase tracking-wide text-white/45">
            Route shared
          </div>
          <div className="mt-0.5 text-[18px] font-black tabular-nums text-white">
            1.24 mi
          </div>
        </div>

        {/* Clap burst — hero clap + radiating mini claps (HypeBurstView) */}
        {burst > 0 && (
          <div
            key={burst}
            className="pointer-events-none absolute inset-0 flex items-center justify-center"
          >
            <Hand
              className="clap-pop absolute h-16 w-16 drop-shadow-[0_4px_16px_rgba(0,0,0,0.6)]"
              style={{ color: HYPE_ORANGE, fill: `${HYPE_ORANGE}22` }}
              strokeWidth={2.4}
            />
            {MINI_CLAPS.map((c, i) => (
              <Hand
                key={i}
                className="clap-fly absolute h-6 w-6"
                style={
                  {
                    "--dx": `${c.dx}px`,
                    "--dy": `${c.dy}px`,
                    color: HYPE_ORANGE,
                    fill: `${HYPE_ORANGE}22`,
                  } as React.CSSProperties
                }
                strokeWidth={2.3}
              />
            ))}
          </div>
        )}

        {/* Page dots — photo → stats card → route map slides */}
        <div className="absolute bottom-2.5 left-0 right-0 flex justify-center gap-1.5">
          <span className="h-1.5 w-1.5 rounded-full bg-white" />
          <span className="h-1.5 w-1.5 rounded-full bg-white/40" />
          <span className="h-1.5 w-1.5 rounded-full bg-white/40" />
        </div>
      </div>

      {/* Stat strip — flame streak, distance, pace chips (PostStatStrip) */}
      <div className="flex flex-wrap gap-2 px-0.5 pt-2.5">
        <span className="flex items-center gap-1 rounded-full bg-white/[0.06] px-2 py-1">
          <Flame className="h-3 w-3" style={{ color: HYPE_ORANGE }} />
          <span
            className="text-[11px] font-extrabold tabular-nums"
            style={{ color: HYPE_ORANGE }}
          >
            {streak} day streak
          </span>
        </span>
        <span className="flex items-center gap-1 rounded-full bg-white/[0.06] px-2 py-1 text-white/85">
          <Footprints className="h-3 w-3" />
          <span className="text-[11px] font-extrabold tabular-nums">
            1.24 mi
          </span>
        </span>
        <span className="flex items-center gap-1 rounded-full bg-white/[0.06] px-2 py-1 text-white/85">
          <Gauge className="h-3 w-3" />
          <span className="text-[11px] font-extrabold tabular-nums">
            8:41 /mi
          </span>
        </span>
      </div>

      {/* Caption */}
      <p className="px-0.5 pt-2 text-sm font-medium text-white/90">
        Morning mile. Another one in the books.
      </p>

      {/* Footer — hype tally left, Hype button right (HypeControls) */}
      <div className="flex items-center justify-between px-0.5 pb-1 pt-2.5">
        <span className="flex items-center gap-1.5">
          <Hand className="h-3.5 w-3.5" style={{ color: HYPE_ORANGE }} />
          <span className="text-[13px] font-extrabold tabular-nums text-white/90">
            {hyped ? 13 : 12} hypes
          </span>
        </span>
        <button
          onClick={hype}
          aria-label="Hype this run"
          className="flex items-center gap-1 rounded-full px-3 py-1.5 transition-all active:scale-90"
          style={
            hyped
              ? {
                  background: "rgba(255,255,255,0.06)",
                  color: "rgba(255,255,255,0.35)",
                }
              : {
                  background: HYPE_ORANGE,
                  color: "#fff",
                  boxShadow: `0 2px 10px ${HYPE_ORANGE}59`,
                }
          }
        >
          <Hand className="h-3.5 w-3.5" style={{ opacity: hyped ? 0.55 : 1 }} />
          <span className="text-xs font-extrabold">
            {hyped ? "Hyped" : "Hype"}
          </span>
        </button>
      </div>
    </div>
  );
}

export function FeedSection() {
  return (
    <section className="section-lazy relative overflow-hidden px-6 py-24">
      <div
        className="pointer-events-none absolute inset-0"
        style={{
          background:
            "radial-gradient(ellipse 700px 500px at 85% 30%, rgba(217,64,89,0.07) 0%, transparent 70%)",
        }}
      />
      <div className="relative mx-auto max-w-6xl">
        <div className="grid gap-12 lg:grid-cols-2 lg:items-center">
          {/* Left: copy */}
          <div>
            <span className="reveal mb-4 inline-block rounded-full border border-[#c72554]/30 bg-[#c72554]/10 px-3 py-1 text-sm font-semibold uppercase tracking-widest text-[#c72554]">
              New — The Feed
            </span>
            <h2 className="reveal reveal-delay-1 font-heading text-[clamp(40px,6vw,72px)] leading-[0.95] tracking-[-1px] text-[#f5f5f5]">
              EVERY MILE
              <br />
              TELLS A <span className="text-[#c72554]">STORY</span>
            </h2>
            <p className="reveal reveal-delay-2 mt-5 max-w-lg text-[17px] leading-relaxed text-[#a0a0a0]">
              Your daily mile deserves more than a checkmark. Share the run —
              the photo, the route, the stats — and let the hypes roll in.
            </p>

            <div className="reveal reveal-delay-3 mt-8 space-y-4">
              {[
                {
                  icon: Camera,
                  color: MAD_RED,
                  title: "Snap it in the moment",
                  desc: "A photo prompt after every run — or grab the shot mid-mile and decide later.",
                },
                {
                  icon: Hourglass,
                  color: HYPE_ORANGE,
                  title: "Stories for the moment, feed for the record",
                  desc: "Stories vanish after 24 hours. Your feed keeps every mile you've shared.",
                },
                {
                  icon: Hand,
                  color: HYPE_ORANGE,
                  title: "Double-tap to hype",
                  desc: "No likes here — hypes. A clap burst for every friend who got their mile in.",
                },
                {
                  icon: Map,
                  color: "#33B34D",
                  title: "Your route, your call",
                  desc: "Show off the loop with a route map on your post — or keep it private with one toggle.",
                },
              ].map((item) => {
                const Icon = item.icon;
                return (
                  <div key={item.title} className="flex items-start gap-4">
                    <div
                      className="mt-0.5 flex h-10 w-10 shrink-0 items-center justify-center rounded-xl"
                      style={{
                        background: `${item.color}1A`,
                        border: `1px solid ${item.color}33`,
                      }}
                    >
                      <Icon
                        className="h-5 w-5"
                        style={{ color: item.color }}
                      />
                    </div>
                    <div>
                      <div className="text-[15px] font-bold text-[#f5f5f5]">
                        {item.title}
                      </div>
                      <div className="mt-0.5 text-sm leading-relaxed text-[#a0a0a0]">
                        {item.desc}
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>

          {/* Right: the feed, as it actually looks in the app */}
          <div className="reveal-right mx-auto w-full max-w-md">
            <TiltCard>
              <div className="rounded-[24px] border border-white/[0.08] bg-[#0d0d0d] p-3.5 shadow-[0_30px_80px_rgba(0,0,0,0.5)]">
                {/* Stories rail */}
                <div className="mb-3 flex items-start gap-3 px-1 pt-1">
                  <YourStoryCell />
                  {STORY_FRIENDS.map((f) => (
                    <FriendStoryCell key={f.username} {...f} />
                  ))}
                </div>

                <FeedPostCard />
              </div>
            </TiltCard>
            <p className="mt-4 text-center text-xs text-white/35">
              Go on — double-tap the photo.
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}
