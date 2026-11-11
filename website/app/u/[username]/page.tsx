import Image from "next/image";
import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { Apple, Lock, Pin } from "lucide-react";
import { Navbar } from "@/components/navbar";
import { Footer } from "@/components/footer";
import { HangingMedal, RARITY_LABEL } from "@/components/medal";
import { APP_STORE_URL } from "@/lib/site";
import {
  bannerGradient,
  displayName,
  formatMiles,
  getPublicProfile,
  profileAvatarURL,
  profileBannerURL,
  profileInitials,
  type PublicMedal,
} from "./publicProfile";
import { ogVideos } from "../../_og/video/meta";

const getProfile = getPublicProfile;

export async function generateMetadata({
  params,
}: {
  params: Promise<{ username: string }>;
}): Promise<Metadata> {
  const { username } = await params;
  const profile = await getProfile(username);

  if (!profile) {
    return { title: { absolute: "Mile A Day" }, robots: { index: false } };
  }

  const title = `@${profile.username} on Mile A Day`;
  const canonical = `/u/${profile.username}`;
  const description = `${displayName(profile)} is building a daily mile habit${
    profile.current_streak > 0
      ? ` — ${profile.current_streak} day streak and counting`
      : ""
  }. Add them on Mile A Day and keep each other moving.`;

  return {
    // `absolute`: the name already ends "on Mile A Day", so the root
    // "%s | Mile A Day" template would say it twice.
    title: { absolute: title },
    description,
    alternates: { canonical },
    openGraph: {
      title,
      description,
      url: canonical,
      type: "profile",
      siteName: "Mile A Day",
      // The animated card (og.mp4 beside this page); the PNG stays og:image.
      videos: ogVideos(`/u/${encodeURIComponent(profile.username ?? username)}/og.mp4`),
    },
    // The co-located opengraph-image is a 1200x630 card; `summary` would crop
    // it to a small square.
    twitter: { card: "summary_large_image", site: "@mileadayapp", title, description },
    // Smart App Banner: iOS Safari shows an "Open in app" banner, which is
    // the fallback path when the universal link opens in the browser.
    // app-argument hands this exact profile to the app, so the banner's
    // OPEN lands on the person instead of just launching the app.
    itunes: {
      appId: "6746970905",
      appArgument: `https://mileaday.run/u/${profile.username}`,
    },
  };
}

// The app's profile is drawn in SF Rounded; ui-rounded IS that on Apple
// devices, DM Sans elsewhere.
const ROUNDED = "[font-family:ui-rounded,var(--font-body),system-ui,sans-serif]";
// MADTheme.Colors.madRed — the app's red, not the site's #c72554.
const MAD_RED = "#D94059";


export default async function ProfilePage({
  params,
}: {
  params: Promise<{ username: string }>;
}) {
  const { username } = await params;
  const profile = await getProfile(username);

  if (!profile) {
    notFound();
  }

  const name = displayName(profile);
  const imageSrc = profileAvatarURL(profile);
  const bannerSrc = profileBannerURL(profile);
  const initials = profileInitials(profile);
  const handle = profile.username;
  const miles = profile.total_miles ?? null;
  const friends = profile.friend_count ?? null;
  // Shared stats come as a set. null = a 'private' account withholds them
  // (say so); absent = an API that predates them (say nothing).
  const sharesStats = miles !== null && friends !== null;
  const withheld = profile.total_miles === null;
  const medals = profile.medals ?? [];
  // The app shrinks a long handle to fit one line; step the size down by
  // length so a 20-character handle doesn't break mid-word at 390px.
  const handleSize =
    (handle ?? name).length > 20
      ? "text-[18px] sm:text-[24px]"
      : (handle ?? name).length > 14
        ? "text-[21px] sm:text-[26px]"
        : "text-[24px] sm:text-[28px]";

  return (
    <main className="relative min-h-screen overflow-x-hidden bg-[#0e0809]">
      <Navbar />
      {/* ProfileHero: full-bleed banner (photo, else the preset gradient),
          scrims top and bottom, the wordmark bar riding on it, and the
          avatar in its goal ring hanging off the bottom edge. */}
      <header className="relative">
        <div
          className="relative h-[220px] w-full overflow-hidden sm:h-[300px]"
          style={{ background: `${bannerGradient(profile.profile_banner_style)}, #000` }}
        >
          {bannerSrc && (
            <Image
              src={bannerSrc}
              alt=""
              fill
              priority
              sizes="100vw"
              className="object-cover"
            />
          )}
          <div className="absolute inset-0 bg-[linear-gradient(to_bottom,rgba(0,0,0,0.5),transparent_45%,transparent_55%,rgba(14,8,9,0.85))]" />
        </div>


        <div className="mx-auto max-w-2xl px-5">
          {/* The ring is ~half on the banner: 88 avatar + 2·4 gap + 2·5 ring
              = 106 (112 → 134 on wider screens), lifted by half its size. */}
          <div className="relative -mt-[53px] h-[106px] w-[106px] sm:-mt-[67px] sm:h-[134px] sm:w-[134px]">
            <div className="absolute inset-0 rounded-full shadow-[0_4px_20px_rgba(0,0,0,0.35)]" />
            {/* GoalRingAvatar with progress unknown: the track alone, no
                claim about today. */}
            <div className="absolute inset-0 rounded-full border-[5px] border-white/10" />
            <div className="absolute inset-[5px] rounded-full bg-black/85" />
            <div className="absolute inset-[9px] overflow-hidden rounded-full bg-[#252525]">
              {imageSrc ? (
                <Image
                  src={imageSrc}
                  alt={`${name}'s profile photo`}
                  fill
                  sizes="116px"
                  className="object-cover"
                />
              ) : (
                <div
                  className={`${ROUNDED} flex h-full w-full items-center justify-center text-[30px] font-black text-white sm:text-[38px]`}
                >
                  {initials}
                </div>
              )}
            </div>
          </div>
        </div>
      </header>

      <section className={`${ROUNDED} mx-auto max-w-2xl px-5 pb-16 pt-4`}>
        {/* ProfileIdentityBlock: "@handle  Display Name", then the bio. */}
        <div className="flex min-w-0 flex-wrap items-baseline gap-x-2 gap-y-0.5">
          <h1 className={`min-w-0 font-black leading-tight text-white [overflow-wrap:anywhere] ${handleSize}`}>
            {handle ? `@${handle}` : name}
          </h1>
          {handle && name !== handle && (
            <span className="min-w-0 text-[14px] font-semibold text-white/55">
              {name}
            </span>
          )}
        </div>
        {profile.bio && (
          <p className="mt-1.5 whitespace-pre-line break-words text-[15px] font-medium leading-snug text-white/80">
            {profile.bio}
          </p>
        )}

        {/* ProfileStatTiles: Streak · Miles · Friends. */}
        <div className="mt-5 grid grid-cols-3 gap-2.5">
          <StatTile
            label="Streak"
            value={profile.current_streak.toLocaleString("en-US")}
            accent={MAD_RED}
            index={0}
          />
          {sharesStats ? (
            <>
              <StatTile label="Miles" value={formatMiles(miles)} index={1} />
              <StatTile
                label={friends === 1 ? "Friend" : "Friends"}
                value={friends.toLocaleString("en-US")}
                index={2}
              />
            </>
          ) : withheld ? (
            <div className="col-span-2 flex items-center gap-2.5 rounded-[14px] border border-white/[0.08] bg-white/[0.05] px-3.5 py-3 text-[13px] font-semibold leading-snug text-white/55">
              <Lock className="h-4 w-4 shrink-0" aria-hidden />
              Miles, friends and medals are private.
            </div>
          ) : null}
        </div>

        {sharesStats && medals.length > 0 && <MedalRow medals={medals} />}

        <div className="mt-9 space-y-3 font-sans">
          <a
            href={`mileaday://u/${encodeURIComponent(profile.username ?? "")}`}
            className="glass-button flex w-full items-center justify-center gap-2 rounded-full px-6 py-4 text-[16px] font-semibold text-white"
          >
            Open in Mile A Day
          </a>
          <a
            href={APP_STORE_URL} data-track="app_store:profile"
            className="flex w-full items-center justify-center gap-2 rounded-full bg-white px-6 py-4 text-[16px] font-semibold text-[#16090c] transition-colors hover:bg-white/90"
          >
            <Apple className="h-5 w-5" aria-hidden />
            Get the app on the App Store
          </a>
          <p className="text-center text-[13px] text-[#a0a0a0]/70">
            Have the app? &ldquo;Open in Mile A Day&rdquo; jumps straight to{" "}
            {profile.first_name ? `${profile.first_name}’s` : "their"} profile
            with an Add Friend button.
          </p>
        </div>
      </section>

      <Footer />
    </main>
  );
}

/** ProfileStatTiles: a rimless card, a sentence-case label (the streak's in red), a big rounded number. */
function StatTile({
  label,
  value,
  accent,
  index,
}: {
  label: string;
  value: string;
  accent?: string;
  index: number;
}) {
  return (
    <div
      data-reveal=""
      style={{ "--d": `${index * 70}ms` } as React.CSSProperties}
      className="min-w-0 rounded-2xl bg-white/[0.045] px-4 py-3.5"
    >
      <div
        className="text-[14px] font-bold"
        style={{ color: accent ?? "rgba(255,255,255,0.6)" }}
      >
        {label}
      </div>
      <div className="mt-1 truncate text-[28px] font-black leading-none tabular-nums text-white sm:text-[32px]">
        {value}
      </div>
    </div>
  );
}

/** The medals they've chosen to show, hanging from their ribbons as the app draws them. */
function MedalRow({ medals }: { medals: PublicMedal[] }) {
  return (
    <div className="mt-3 rounded-2xl bg-white/[0.045] p-4">
      <div className="flex items-center gap-2 text-[15px] font-bold text-white">
        <Pin className="h-4 w-4 text-[#D94059]" aria-hidden />
        Medals
      </div>
      <ul className="mt-4 grid grid-cols-3 gap-2.5 sm:grid-cols-5">
        {medals.map((medal, i) => {
          const rarity = RARITY_LABEL[medal.rarity] ?? RARITY_LABEL.common;
          return (
            <li
              key={medal.badge_id}
              data-reveal="pop"
              style={{ "--d": `${150 + i * 80}ms` } as React.CSSProperties}
              className="flex min-w-0 flex-col items-center rounded-2xl bg-white/[0.04] px-2 pb-3 pt-2 text-center"
            >
              <HangingMedal
                id={`m-${medal.badge_id}`}
                icon={medal.icon}
                category={medal.category}
                rarity={medal.rarity}
                size={60}
              />
              <span className="mt-2 line-clamp-2 w-full break-words text-[13px] font-bold leading-tight text-white">
                {medal.name}
              </span>
              <span className="mt-0.5 text-[11px] font-bold" style={{ color: rarity.color }}>
                {rarity.label}
              </span>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
