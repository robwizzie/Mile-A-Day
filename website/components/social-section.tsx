"use client";

import { useRef, useCallback } from "react";
import { Flame, Bell, Share2, Check, ChevronRight } from "lucide-react";
import { ProfileAvatar } from "@/components/profile-avatar";
import { usePublicUser } from "@/lib/public-user";

// App palette (MADTheme): madRed #D94059, success #33B34D, warning #FF9900.
const MAD_RED = "#D94059";
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
    name: "Megs",
    username: "MegsMiles",
    progress: 0.2,
    milesToday: 0.2,
    avatar: "MM",
  },
];

const doneFriends = [
  { name: "David", username: "dave", milesToday: 1.3, avatar: "DS" },
  { name: "MAD", username: "mad", milesToday: 1.0, avatar: "M" },
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
            See who&apos;s slacking. Nudge them. Hype the ones who showed up. Or
            flex your streak and let them know who does this every single day.
          </p>
        </div>

        <div className="grid gap-10 lg:grid-cols-2 lg:items-start">
          {/* Left: Streak share card — matches app's goal-completed celebration */}
          <div className="reveal-left">
            <TiltCard>
              <div
                className="rounded-[20px] overflow-hidden border border-white/[0.08]"
                style={{
                  background:
                    "linear-gradient(180deg, rgba(217,64,89,0.15) 0%, rgba(10,10,10,0.95) 50%)",
                }}
              >
                {/* Celebration header */}
                <div className="relative px-6 pt-8 pb-4 text-center overflow-hidden">
                  {/* Glow */}
                  <div className="absolute inset-0 flex items-start justify-center">
                    <div
                      className="h-32 w-32 rounded-full opacity-20 blur-3xl"
                      style={{ background: MAD_RED }}
                    />
                  </div>
                  {/* Flame */}
                  <div className="relative mb-3 inline-flex h-16 w-16 items-center justify-center">
                    <Flame
                      className="h-12 w-12 drop-shadow-[0_0_15px_rgba(217,64,89,0.6)]"
                      style={{ color: MAD_RED }}
                    />
                  </div>
                  <div className="relative font-heading text-[64px] leading-none text-white">
                    288
                  </div>
                  <div className="relative font-heading text-[22px] tracking-[1px] text-white/80">
                    day streak!
                  </div>
                </div>

                {/* Week calendar — every past day completed (the streak is alive) */}
                <div className="flex justify-center gap-2.5 px-6 py-4">
                  {["S", "M", "T", "W", "T", "F", "S"].map((day, i) => {
                    const isToday = i === 4;
                    const isPast = i < 4;
                    return (
                      <div
                        key={`${day}-${i}`}
                        className="flex flex-col items-center gap-1"
                      >
                        <span className="text-[10px] font-bold text-white/40">
                          {day}
                        </span>
                        <div
                          className="flex h-9 w-9 items-center justify-center rounded-full"
                          style={
                            isToday
                              ? {
                                  background: MAD_RED,
                                  boxShadow: "0 0 12px rgba(217,64,89,0.5)",
                                }
                              : isPast
                                ? {
                                    border: `1px solid ${SUCCESS_GREEN}66`,
                                    background: `${SUCCESS_GREEN}1A`,
                                  }
                                : { border: "1px solid rgba(255,255,255,0.1)" }
                          }
                        >
                          {isToday ? (
                            <Flame className="h-4 w-4 text-white" />
                          ) : isPast ? (
                            <Check
                              className="h-4 w-4"
                              style={{ color: SUCCESS_GREEN }}
                            />
                          ) : null}
                        </div>
                      </div>
                    );
                  })}
                </div>

                {/* Stats row */}
                <div className="flex justify-center gap-4 px-6 pb-4">
                  {[
                    { label: "Distance", value: "1.12 mi" },
                    { label: "Pace", value: "7:42/mi" },
                    { label: "Calories", value: "142" },
                  ].map((stat) => (
                    <div
                      key={stat.label}
                      className="rounded-xl bg-white/[0.04] border border-white/[0.06] px-3 py-2 text-center"
                    >
                      <div className="text-xs font-semibold text-white">
                        {stat.value}
                      </div>
                      <div className="text-[9px] text-white/40 uppercase tracking-wider">
                        {stat.label}
                      </div>
                    </div>
                  ))}
                </div>

                {/* Share button */}
                <div className="px-6 pb-6">
                  <div
                    className="flex items-center justify-center gap-2 rounded-2xl py-3 cursor-default"
                    style={{ background: MAD_RED }}
                  >
                    <Share2 className="h-4 w-4 text-white" />
                    <span className="text-sm font-semibold text-white">
                      Share Your Streak
                    </span>
                  </div>
                </div>
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

            {/* Flex hint */}
            <div
              className="flex items-center gap-2 rounded-[16px] px-4 py-3"
              style={{
                border: `1px solid ${MAD_RED}33`,
                background: `${MAD_RED}0F`,
              }}
            >
              <Flame className="h-4 w-4" style={{ color: MAD_RED }} />
              <span className="flex-1 text-sm text-white/50">
                Tap a friend to{" "}
                <span className="font-semibold" style={{ color: MAD_RED }}>
                  flex your streak
                </span>{" "}
                on them
              </span>
              <ChevronRight
                className="h-4 w-4"
                style={{ color: `${MAD_RED}80` }}
              />
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
