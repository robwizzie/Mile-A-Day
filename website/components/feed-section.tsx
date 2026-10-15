"use client";

import Image from "next/image";
import { useRef, useCallback, useState } from "react";
import {
  Camera,
  Ellipsis,
  Flame,
  Hand,
  Hourglass,
  Map,
  MessageCircle,
  PersonStanding,
  Plus,
  Send,
} from "lucide-react";
import { ProfileAvatar } from "@/components/profile-avatar";

// App palette (MADTheme). Hype is ALWAYS represented by a clap/hand action in
// Mile A Day — the button is solid orange, the tally icon is orange.
const MAD_RED = "#D94059";
const HYPE_ORANGE = "#FF9900";
// MADTheme.Colors.walkBlue — walks are blue everywhere in the app.
const WALK_BLUE = "#4099F2";

const STORY_FRIENDS = [
  { username: "dave", initials: "DS", label: "dave" },
  { username: "MegsMiles", initials: "MM", label: "MegsMiles" },
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

/** The feed card as PostCardView draws it today: distance and walk/run ride
 * the header subtitle, the action row is clap + count · comment · share with
 * the PHOTO | MAP toggle at its end (FeedActionRow), streak and timestamp are
 * ONE quiet meta line (FeedMetaLine), and the caption comes last, led by the
 * author's name. The photo is the real feed example. Double-tap hypes, as in
 * the app (doubleTapHype). */
function FeedPostCard() {
  const [burst, setBurst] = useState(0);
  const hyped = burst > 0;

  const hype = useCallback(() => {
    setBurst((b) => b + 1);
  }, []);

  return (
    <div className="rounded-2xl bg-white/[0.04] p-3">
      <div className="mb-3 flex items-center gap-2.5">
        <ProfileAvatar username="rob" initials="RW" size={40} />
        <div className="min-w-0 flex-1">
          <div className="truncate text-[15px] font-bold text-white">rob</div>
          <div className="flex items-center gap-1 text-xs font-medium text-white/50">
            <PersonStanding className="h-3 w-3" style={{ color: WALK_BLUE }} strokeWidth={2.6} />
            <span>Walk · 1.11 mi · 2h</span>
          </div>
        </div>
        <Ellipsis className="h-5 w-5 text-white/45" />
      </div>

      <div
        className="relative aspect-[4/5] cursor-pointer select-none overflow-hidden rounded-xl bg-black"
        onDoubleClick={hype}
      >
        <Image
          src="/images/feed-example.png"
          alt="Rob's Mile A Day feed photo"
          width={1185}
          height={1928}
          priority={false}
          className="h-full w-full object-cover object-[center_42%]"
          sizes="(min-width: 640px) 420px, 90vw"
        />

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
      </div>

      {/* Action row: clap + count, comment, share … PHOTO | MAP */}
      <div className="mt-3 flex items-center gap-4 px-0.5">
        <button
          type="button"
          onClick={hype}
          aria-label="Hype this post"
          className="flex items-center gap-1.5 text-[15px] font-bold text-white/90"
        >
          <Hand
            className="h-[22px] w-[22px]"
            style={{ color: hyped ? HYPE_ORANGE : "#fff", fill: hyped ? HYPE_ORANGE : "transparent" }}
            strokeWidth={2}
          />
          <span>{2 + Math.min(burst, 1)}</span>
        </button>
        <MessageCircle className="h-[21px] w-[21px] text-white" strokeWidth={2} aria-hidden />
        <Send className="h-[20px] w-[20px] text-white" strokeWidth={2} aria-hidden />
        <div className="ml-auto flex rounded-full border border-white/10 bg-white/[0.06] p-0.5 text-[10px] font-extrabold tracking-wider">
          <span className="rounded-full bg-white px-2.5 py-1 text-black">PHOTO</span>
          <span className="px-2.5 py-1 text-white/70">MAP</span>
        </div>
      </div>

      {/* Meta line: streak · timestamp */}
      <div className="mt-2.5 flex items-center justify-between px-0.5 text-[12px] font-semibold">
        <span className="flex items-center gap-1" style={{ color: HYPE_ORANGE }}>
          <Flame className="h-3.5 w-3.5" /> 423-day streak
        </span>
        <span className="uppercase tracking-wide text-white/45">Jul 9 · 9:42 PM</span>
      </div>

      <p className="mt-2 px-0.5 text-[15px] leading-snug text-white/90">
        <span className="font-bold text-white">rob</span>{" "}
        Bugs tried to get me while I took the trash out, they did not succeed
      </p>
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
              The Feed
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
                  desc: "Your route drawn on the post, with a Flyover to replay it from above. The first and last stretch are trimmed so your front door stays yours — or keep the map off entirely.",
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
