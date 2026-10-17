"use client";

import { useRef, useCallback } from "react";
import Image from "next/image";
import { Flame, Bell, Check, ChevronRight } from "lucide-react";
import { ProfileAvatar } from "@/components/profile-avatar";
import { usePublicUser } from "@/lib/public-user";

// App palette (MADTheme): madRed #D94059, success #33B34D, warning #FF9900.
const SUCCESS_GREEN = "#33B34D";
const NUDGE_ORANGE = "#FF9900";

// Real Mile A Day accounts. The profile picture and streak are pulled LIVE from
// the public API (see usePublicUser) so the demo reflects real people. The
// per-day progress/miles are illustrative — that data isn't exposed publicly.
const cheerFriends = [
  {
    name: "Aaron",
    username: "Aaron",
    progress: 0.55,
    milesToday: 0.55,
    avatar: "AA",
  },
  {
    name: "MegsMiles",
    username: "MegsMiles",
    progress: 0.2,
    milesToday: 0.2,
    avatar: "MM",
  },
];

const doneFriends = [
  { name: "dave", username: "dave", milesToday: 1.3, avatar: "DS" },
  { name: "mad", username: "mad", milesToday: 1.0, avatar: "M" },
];

/** Avatar with progress ring — mirrors the app's AvatarWithRing component:
 * orange arc while in progress, solid green ring + check badge when done. */
function AvatarRing({
  initials,
  progress,
  size = 52,
  username,
}: {
  initials: string;
  progress: number;
  size?: number;
  username?: string;
}) {
  const complete = progress >= 1;
  const r = size / 2 - 3;
  const circumference = 2 * Math.PI * r;
  const ringColor = complete ? SUCCESS_GREEN : NUDGE_ORANGE;

  return (
    <div className="relative shrink-0" style={{ width: size, height: size }}>
      <svg
        viewBox={`0 0 ${size} ${size}`}
        width={size}
        height={size}
        className="-rotate-90"
      >
        <circle
          cx={size / 2}
          cy={size / 2}
          r={r}
          fill="none"
          stroke="rgba(255,255,255,0.08)"
          strokeWidth="3"
        />
        <circle
          cx={size / 2}
          cy={size / 2}
          r={r}
          fill="none"
          stroke={ringColor}
          strokeWidth="3"
          strokeLinecap="round"
          strokeDasharray={circumference}
          strokeDashoffset={circumference * (1 - Math.min(progress, 1))}
        />
      </svg>
      <ProfileAvatar
        username={username}
        initials={initials}
        size={size - 12}
        style={{ position: "absolute", top: 6, left: 6 }}
      />
      {complete && (
        <div
          className="absolute -bottom-0.5 -right-0.5 flex h-4 w-4 items-center justify-center rounded-full border border-black/40"
          style={{ background: SUCCESS_GREEN }}
        >
          <Check className="h-2.5 w-2.5 text-white" strokeWidth={3.5} />
        </div>
      )}
    </div>
  );
}

/** Streak flame + count, orange like the app's friend rows. Renders nothing
 * until the real streak loads so we never flash a placeholder number. */
function StreakFlame({ streak }: { streak: number | null }) {
  if (streak === null) return null;
  return (
    <span className="flex items-center gap-0.5">
      <Flame className="h-3 w-3" style={{ color: NUDGE_ORANGE }} />
      <span
        className="text-[11px] font-extrabold"
        style={{ color: NUDGE_ORANGE }}
      >
        {streak}
      </span>
    </span>
  );
}

type Friend = {
  name: string;
  username: string;
  progress?: number;
  milesToday: number;
  avatar: string;
};

/** Friend who hasn't finished their mile yet — real photo + live streak,
 * with a "Nudge" button mirroring the app's Cheer Them On row. */
function CheerRow({ friend }: { friend: Friend }) {
  const user = usePublicUser(friend.username);
  const progress = friend.progress ?? 0;
  return (
    <div className="flex items-center gap-3 rounded-[12px] px-2 py-2">
      <AvatarRing
        initials={friend.avatar}
        progress={progress}
        username={friend.username}
      />
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-1.5">
          <span className="text-sm font-bold text-white">{friend.name}</span>
          <StreakFlame streak={user?.currentStreak ?? null} />
        </div>
        <div className="text-[11px] text-white/50">
          {friend.milesToday.toFixed(2)} / 1 mi · {Math.round(progress * 100)}%
        </div>
      </div>
      {/* Nudge button — orange tinted pill like the app */}
      <button
        className="flex items-center gap-1.5 rounded-full px-3 py-1.5 cursor-default"
        style={{
          color: NUDGE_ORANGE,
          background: "rgba(255,153,0,0.12)",
          border: "1px solid rgba(255,153,0,0.2)",
        }}
      >
        <Bell className="h-3 w-3" />
        <span className="text-[11px] font-semibold">Nudge</span>
      </button>
    </div>
  );
}

/** Friend who hit their goal today — real photo + live streak, green ring. */
function DoneRow({ friend }: { friend: Friend }) {
  const user = usePublicUser(friend.username);
  return (
    <div className="flex items-center gap-3 rounded-[12px] px-2 py-2">
      <AvatarRing
        initials={friend.avatar}
        progress={1}
        username={friend.username}
      />
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-1.5">
          <span className="text-sm font-bold text-white">{friend.name}</span>
          <StreakFlame streak={user?.currentStreak ?? null} />
        </div>
        <div className="text-[11px] text-white/50">
          Goal complete · {friend.milesToday.toFixed(2)} mi today
        </div>
      </div>
      <ChevronRight className="h-3.5 w-3.5 text-white/30" />
    </div>
  );
}

function SectionHeader({
  title,
  trailing,
}: {
  title: string;
  trailing?: string;
}) {
  return (
    <div className="flex items-center justify-between px-1">
      <span className="text-[11px] font-extrabold uppercase tracking-[1.4px] text-white/40">
        {title}
      </span>
      {trailing && (
        <span className="text-[11px] font-semibold text-white/40">
          {trailing}
        </span>
      )}
    </div>
  );
}

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

export function SocialSection() {
  return (
    <section className="section-lazy relative px-6 py-24 overflow-hidden">
      <div className="relative mx-auto max-w-6xl">
        <div className="mx-auto mb-16 max-w-2xl text-center">
          <span className="reveal mb-4 inline-block text-sm font-semibold uppercase tracking-widest text-[#c72554]">
            Social
          </span>
          <h2 className="reveal reveal-delay-1 font-heading text-[clamp(40px,6vw,72px)] leading-none tracking-[-1px] text-[#f5f5f5]">
            FLEX ON YOUR FRIENDS
          </h2>
          <p className="reveal reveal-delay-2 mt-4 text-base leading-relaxed text-[#a0a0a0]">
            See who&apos;s slacking. Nudge them. Hype the ones who showed up on the feed. Or
            share your streak straight to Instagram Stories and let them know who
            does this every single day.
          </p>
        </div>

        <div className="grid gap-10 lg:grid-cols-2 lg:items-start">
          {/* Left: the app's real share studio on the Streak card (capture,
              Oct 2026). It used to be a drawn card with a week calendar,
              pace and calories that no screen in the app has ever shown. */}
          <div className="reveal-left flex justify-center">
            <TiltCard>
              <div className="iphone-frame relative w-[260px] sm:w-[290px]">
                <Image
                  src="/images/share-streak.png"
                  alt="Mile A Day share studio showing a 511 day streak card ready for Instagram Stories"
                  width={776}
                  height={1680}
                  sizes="290px"
                  className="block h-auto w-full"
                />
              </div>
            </TiltCard>
          </div>

          {/* Right: Friends list — mirrors the app's Friends tab sections */}
          <div className="reveal-right space-y-3">
            {/* CHEER THEM ON — friends who haven't finished their mile yet */}
            <SectionHeader title="Cheer Them On" />
            <div className="space-y-1.5 rounded-[16px] border border-white/[0.05] bg-white/[0.03] p-2">
              {cheerFriends.map((friend) => (
                <CheerRow key={friend.username} friend={friend} />
              ))}
            </div>

            {/* DONE TODAY — friends who hit their goal */}
            <SectionHeader
              title="Done Today"
              trailing={`${doneFriends.length} of ${doneFriends.length + cheerFriends.length}`}
            />
            <div className="space-y-1.5 rounded-[16px] border border-white/[0.05] bg-white/[0.03] p-2">
              {doneFriends.map((friend) => (
                <DoneRow key={friend.username} friend={friend} />
              ))}
            </div>

          </div>
        </div>
      </div>
    </section>
  );
}
