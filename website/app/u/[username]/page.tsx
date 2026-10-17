import Image from "next/image";
import Link from "next/link";
import type { Metadata } from "next";
import { notFound } from "next/navigation";
import {
  Apple,
  Flame,
  Footprints,
  Lock,
  Medal,
  Route,
  Trophy,
  Zap,
  type LucideIcon,
} from "lucide-react";
import { Footer } from "@/components/footer";
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
const ROUNDED = "[font-family:ui-rounded,var(--font-dm-sans),system-ui,sans-serif]";
// MADTheme.Colors.madRed — the app's red, not the site's #c72554.
const MAD_RED = "#D94059";

// Rarity colours = the app's (PremiumBadgeCard / BadgeRarity), as on the
// home page's medal showcase.
const RARITY: Record<string, { from: string; to: string; accent: string }> = {
  legendary: { from: "#FFD966", to: "#D98C26", accent: "#FF9F0A" },
  rare: { from: "#B380E6", to: "#804DBF", accent: "#BF5AF2" },
  common: { from: "#73A6F2", to: "#4D80CC", accent: "#0A84FF" },
};

const CATEGORY_ICON: Record<string, LucideIcon> = {
  streak: Flame,
  miles: Footprints,
  pace: Zap,
  daily: Route,
  challenge: Trophy,
  weekly_challenge: Trophy,
  competition: Trophy,
};

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
    <main className="relative min-h-screen overflow-x-hidden bg-[#0a0a0a]">
      {/* ProfileHero: full-bleed banner (photo, else the preset gradient),
          scrims top and bottom, the wordmark bar riding on it, and the
          avatar in its goal ring hanging off the bottom edge. */}
      <header className="relative">
        <div
          className="relative h-[190px] w-full overflow-hidden sm:h-[260px]"
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
          <div className="absolute inset-0 bg-[linear-gradient(to_bottom,rgba(0,0,0,0.42),transparent_50%,transparent_50%,rgba(0,0,0,0.62))]" />
        </div>

        <nav className="absolute inset-x-0 top-0">
          <div className="mx-auto flex max-w-2xl items-center justify-between gap-4 px-5 pt-4">
            <Link href="/" className="flex min-w-0 items-center gap-2.5">
              <Image
                src="/images/mad-circle-icon.png"
                alt="Mile A Day logo"
                width={34}
                height={34}
                className="shrink-0 rounded-full"
              />
              <span
                className={`${ROUNDED} text-[11px] font-black tracking-[2.2px] text-white/85`}
              >
                MILE A DAY
              </span>
            </Link>
            <Link
              href="/"
              className="shrink-0 rounded-full border border-white/20 bg-black/35 px-3.5 py-2 text-[13px] font-semibold text-white transition-colors hover:bg-black/50"
            >
              What is Mile A Day?
            </Link>
          </div>
        </nav>

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
            label="STREAK"
            value={profile.current_streak.toLocaleString("en-US")}
            accent={MAD_RED}
          />
          {sharesStats ? (
            <>
              <StatTile label="MILES" value={formatMiles(miles)} />
              <StatTile
                label={friends === 1 ? "FRIEND" : "FRIENDS"}
                value={friends.toLocaleString("en-US")}
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
            className="glass-button flex w-full items-center justify-center gap-2 rounded-2xl bg-[#c72554] px-6 py-4 text-[16px] font-semibold text-white transition-transform hover:scale-[1.02]"
          >
            Open in Mile A Day
          </a>
          <a
            href={APP_STORE_URL}
            className="glass-button flex w-full items-center justify-center gap-2 rounded-2xl border border-[#c72554]/50 px-6 py-4 text-[16px] font-semibold text-[#f5f5f5] transition-transform hover:scale-[1.02]"
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

function StatTile({
  label,
  value,
  accent,
}: {
  label: string;
  value: string;
  accent?: string;
}) {
  return (
    <div
      className="min-w-0 rounded-[14px] border px-3.5 py-3"
      style={
        accent
          ? { background: `${accent}24`, borderColor: `${accent}47` }
          : { background: "rgba(255,255,255,0.05)", borderColor: "rgba(255,255,255,0.08)" }
      }
    >
      <div
        className="text-[9px] font-extrabold tracking-[1.2px]"
        style={{ color: accent ?? "rgba(255,255,255,0.55)" }}
      >
        {label}
      </div>
      <div className="mt-1.5 truncate text-[24px] font-black leading-none tabular-nums text-white">
        {value}
      </div>
    </div>
  );
}

function MedalRow({ medals }: { medals: PublicMedal[] }) {
  return (
    <div className="mt-3 rounded-[14px] border border-white/[0.08] bg-white/[0.04] px-3.5 pb-3.5 pt-3">
      <div className="text-[11px] font-extrabold tracking-[1.2px] text-white/50">
        MEDALS
      </div>
      <ul className="mt-3 grid grid-cols-5 gap-2">
        {medals.map((medal) => {
          const rarity = RARITY[medal.rarity] ?? RARITY.common;
          const Icon = CATEGORY_ICON[medal.category] ?? Medal;
          return (
            <li key={medal.badge_id} className="flex min-w-0 flex-col items-center text-center">
              <div
                className="flex h-12 w-12 items-center justify-center rounded-full sm:h-14 sm:w-14"
                style={{
                  background: `linear-gradient(135deg, ${rarity.from}, ${rarity.to})`,
                  boxShadow: `0 0 18px ${rarity.accent}40, inset 0 0 0 2px rgba(255,255,255,0.25)`,
                }}
              >
                <Icon className="h-5 w-5 text-white drop-shadow sm:h-6 sm:w-6" aria-hidden />
              </div>
              <span className="mt-1.5 line-clamp-2 w-full break-words text-[10px] font-bold leading-tight text-white/75">
                {medal.name}
              </span>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
