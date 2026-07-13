"use client";

import { useRef, useCallback, useState } from "react";
import {
  Camera,
  Clock3,
  Heart,
  Map,
  Flame,
  Plus,
  MessageCircle,
} from "lucide-react";
import { ProfileAvatar } from "@/components/profile-avatar";
import { usePublicUser } from "@/lib/public-user";

// App palette (MADTheme)
const MAD_RED = "#D94059";
const NUDGE_ORANGE = "#FF9900";

const STORY_FACES = [
  { username: "rob", initials: "RW" },
  { username: "dave", initials: "DS" },
  { username: "MegsMiles", initials: "MM" },
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

/** Story bubble with the app's red story ring. Real profile photos. */
function StoryBubble({
  username,
  initials,
  label,
}: {
  username: string;
  initials: string;
  label: string;
}) {
  return (
    <div className="flex flex-col items-center gap-1.5">
      <div
        className="rounded-full p-[2.5px]"
        style={{ background: `linear-gradient(135deg, ${MAD_RED}, #ff4d7d)` }}
      >
        <div className="rounded-full border-2 border-[#101010] bg-[#101010]">
          <ProfileAvatar username={username} initials={initials} size={46} />
        </div>
      </div>
      <span className="text-[10px] font-medium text-white/50">{label}</span>
    </div>
  );
}

/** The feed post mock — a run card with route map, stats overlay, and a
 * double-tap hype you can actually try. */
function FeedPostCard() {
  const rob = usePublicUser("rob");
  const [hyped, setHyped] = useState(false);
  const [burst, setBurst] = useState(0);

  const hype = useCallback(() => {
    setHyped(true);
    setBurst((b) => b + 1);
  }, []);

  return (
    <div className="overflow-hidden rounded-[20px] border border-white/[0.08] bg-[#101010]">
      {/* Header */}
      <div className="flex items-center gap-3 px-4 py-3">
        <ProfileAvatar username="rob" initials="RW" size={36} />
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-1.5">
            <span className="text-sm font-bold text-white">Rob</span>
            {rob?.currentStreak != null && (
              <span className="flex items-center gap-0.5">
                <Flame className="h-3 w-3" style={{ color: NUDGE_ORANGE }} />
                <span
                  className="text-[11px] font-extrabold"
                  style={{ color: NUDGE_ORANGE }}
                >
                  {rob.currentStreak}
                </span>
              </span>
            )}
          </div>
          <span className="text-[11px] text-white/40">
            Morning mile · 7:04 AM
          </span>
        </div>
        <span
          className="rounded-full px-2.5 py-1 text-[10px] font-bold uppercase tracking-wider"
          style={{
            color: MAD_RED,
            background: `${MAD_RED}1A`,
            border: `1px solid ${MAD_RED}33`,
          }}
        >
          Mile done
        </span>
      </div>

      {/* Media area: photo stand-in + route + stats overlay. Double-tap (or
          double-click) to hype, just like the app. */}
      <div
        className="relative aspect-[4/3] cursor-pointer select-none overflow-hidden"
        onDoubleClick={hype}
        style={{
          background:
            "linear-gradient(160deg, #2a1520 0%, #1a0f14 40%, #0d1a12 100%)",
        }}
      >
        {/* Sunrise glow */}
        <div
          className="absolute -top-8 right-6 h-28 w-28 rounded-full opacity-30 blur-2xl"
          style={{ background: "linear-gradient(180deg, #ff9900, #c72554)" }}
        />
        {/* Route polyline */}
        <svg viewBox="0 0 320 240" className="absolute inset-0 h-full w-full">
          <path
            d="M 40 200 C 80 150, 70 110, 120 100 S 200 130, 230 90 S 280 40, 285 60"
            fill="none"
            stroke={MAD_RED}
            strokeWidth="3.5"
            strokeLinecap="round"
            strokeDasharray="1 0"
            style={{ filter: `drop-shadow(0 0 6px ${MAD_RED}AA)` }}
          />
          <circle cx="40" cy="200" r="5" fill="#33B34D" />
          <circle cx="285" cy="60" r="5" fill={MAD_RED} />
        </svg>
        {/* Stats overlay chips — the app's customizable run-stats overlay */}
        <div className="absolute bottom-3 left-3 flex gap-2">
          {[
            { label: "Distance", value: "1.24 mi" },
            { label: "Pace", value: "8:41 /mi" },
            { label: "Time", value: "10:46" },
          ].map((stat) => (
            <div
              key={stat.label}
              className="rounded-lg border border-white/10 bg-black/50 px-2.5 py-1.5 backdrop-blur-md"
            >
              <div className="text-[11px] font-bold leading-none text-white">
                {stat.value}
              </div>
              <div className="mt-0.5 text-[8px] uppercase tracking-wider text-white/50">
                {stat.label}
              </div>
            </div>
          ))}
        </div>
        {/* Double-tap heart burst */}
        {burst > 0 && (
          <div
            key={burst}
            className="pointer-events-none absolute inset-0 flex items-center justify-center"
          >
            <Heart
              className="h-20 w-20 animate-ping"
              style={{
                color: MAD_RED,
                fill: MAD_RED,
                animationIterationCount: 1,
                animationDuration: "0.7s",
              }}
            />
          </div>
        )}
      </div>

      {/* Action row */}
      <div className="flex items-center gap-4 px-4 py-3">
        <button
          onClick={hype}
          className="flex items-center gap-1.5 transition-transform active:scale-90"
          aria-label="Hype this run"
        >
          <Heart
            className="h-5 w-5 transition-colors"
            style={
              hyped
                ? { color: MAD_RED, fill: MAD_RED }
                : { color: "rgba(255,255,255,0.6)" }
            }
          />
          <span
            className="text-xs font-semibold"
            style={{ color: hyped ? MAD_RED : "rgba(255,255,255,0.6)" }}
          >
            {hyped ? 13 : 12}
          </span>
        </button>
        <span className="flex items-center gap-1.5 text-white/40">
          <MessageCircle
            className="h-4.5 w-4.5"
            style={{ width: 18, height: 18 }}
          />
          <span className="text-xs font-semibold">3</span>
        </span>
        <span className="ml-auto text-[10px] text-white/30">
          Double-tap the photo — go on, try it
        </span>
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
              the photo, the route, the stats — and watch your friends show up
              in the comments and the hypes.
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
                  icon: Clock3,
                  color: NUDGE_ORANGE,
                  title: "Stories for the moment, feed for the record",
                  desc: "Stories vanish after 24 hours. Your feed keeps every mile you've shared.",
                },
                {
                  icon: Heart,
                  color: "#ff4d7d",
                  title: "Double-tap to hype",
                  desc: "Cheer every mile. Hypes land as notifications your friends actually want.",
                },
                {
                  icon: Map,
                  color: "#33B34D",
                  title: "Your route, your call",
                  desc: "Show off the loop with a route map on your post — or keep it private with one toggle.",
                },
              ].map((item) => (
                <div key={item.title} className="flex items-start gap-4">
                  <div
                    className="mt-0.5 flex h-10 w-10 shrink-0 items-center justify-center rounded-xl"
                    style={{
                      background: `${item.color}1A`,
                      border: `1px solid ${item.color}33`,
                    }}
                  >
                    <item.icon
                      className="h-4.5 w-4.5"
                      style={{ width: 18, height: 18, color: item.color }}
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
              ))}
            </div>
          </div>

          {/* Right: interactive feed mock */}
          <div className="reveal-right mx-auto w-full max-w-md">
            <TiltCard>
              <div className="rounded-[24px] border border-white/[0.08] bg-[#0d0d0d] p-4 shadow-[0_30px_80px_rgba(0,0,0,0.5)]">
                {/* Stories rail */}
                <div className="mb-4 flex items-center gap-4 px-1">
                  <div className="flex flex-col items-center gap-1.5">
                    <div className="flex h-[51px] w-[51px] items-center justify-center rounded-full border-2 border-dashed border-white/20">
                      <Plus className="h-5 w-5 text-white/40" />
                    </div>
                    <span className="text-[10px] font-medium text-white/50">
                      Your story
                    </span>
                  </div>
                  {STORY_FACES.map((face) => (
                    <StoryBubble
                      key={face.username}
                      username={face.username}
                      initials={face.initials}
                      label={
                        face.username === "MegsMiles"
                          ? "Megs"
                          : face.username === "dave"
                            ? "David"
                            : "Rob"
                      }
                    />
                  ))}
                </div>

                <FeedPostCard />
              </div>
            </TiltCard>
          </div>
        </div>
      </div>
    </section>
  );
}
