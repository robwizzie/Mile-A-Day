"use client";

import { useCallback, useEffect, useState, type ReactNode } from "react";
import {
  CARD_INTERACTIVE,
  Chip,
  fmt,
  fmtDate,
  getData,
  Loading,
  MAD_SUCCESS,
  mediaSrc,
  LiveCardTile,
  prettySource,
  relativeDay,
  SegmentedControl,
  PANEL_BACKGROUND,
} from "./lib";

type UserDetail = {
  profile: {
    user_id: string;
    username: string | null;
    first_name: string | null;
    last_name: string | null;
    email: string | null;
    bio: string | null;
    role: string | null;
    profile_image_url: string | null;
    goal_miles: number;
    current_streak: number;
    terms_accepted_at: string | null;
    onboarding_completed_at: string | null;
    referral_source: string | null;
    referral_detail: string | null;
    signup_goal: string | null;
    experience_level: string | null;
    created_at: string;
  };
  stats: {
    total_miles: number;
    total_workouts: number;
    active_days: number;
    miles_7d: number;
    miles_30d: number;
    last_active: string | null;
    first_active: string | null;
  };
  social: {
    friends: number;
    hypes_sent: number;
    hypes_received: number;
    nudges_sent: number;
    nudges_received: number;
    posts_live: number;
    posts_total: number;
  };
  devices: { environment: string; created_at: string; updated_at: string }[];
  recent_workouts: {
    workout_id: string;
    workout_type: string | null;
    distance: number;
    local_date: string;
    total_duration: number;
    deleted_at: string | null;
    exclusion_reason: string | null;
    speed_flagged: boolean;
  }[];
  // Older backends serve the modal without this; the block just doesn't draw.
  acquisition?: {
    source: string | null;
    typed_as: string | null;
    referred_by: {
      user_id: string;
      username: string | null;
      linked_by_hand: boolean;
    } | null;
    referred: PersonRow[];
  };
};

/** The shape every clickable person on this modal shares. */
type PersonRow = {
  user_id: string;
  username: string | null;
  name: string | null;
  profile_image_url: string | null;
  current_streak?: number;
  total_miles?: number;
  last_active?: string | null;
  created_at?: string;
  typed_as?: string | null;
  is_friend?: boolean;
};

type FriendRow = PersonRow & {
  role: string | null;
  current_streak: number;
  referral_source: string | null;
  referral_detail: string | null;
  joined_at: string;
  friends_since: string | null;
  last_active: string | null;
  total_miles: number;
  photo_count: number;
  mutual_friends: number;
  referred_by_me: boolean;
  referred_me: boolean;
};

type FriendsResponse = {
  total: number;
  friends: FriendRow[];
  pending: (PersonRow & {
    direction: "sent" | "received";
    status: "pending" | "ignored";
    created_at: string;
  })[];
};

type PostRow = {
  post_id: string;
  media_url: string;
  caption: string | null;
  is_auto: boolean;
  share_to_feed: boolean;
  share_to_story: boolean;
  include_route: boolean | null;
  local_date: string;
  created_at: string;
  deleted_at: string | null;
  pinned_at: string | null;
  is_buddy_walk: boolean;
  competition_id: string | null;
  workout_type: string | null;
  workout_distance: number | null;
  coauthor_user_id: string | null;
  coauthor_username: string | null;
  hype_count: number;
  comment_count: number;
  crew_photos: number;
};

type PostScope = "all" | "photos" | "auto" | "deleted";

type PostsResponse = {
  summary: {
    total: number;
    live: number;
    photos: number;
    auto: number;
    deleted: number;
    on_feed: number;
    stories: number;
  };
  matching: number;
  posts: PostRow[];
};

const POSTS_PAGE = 48;

type Tab = "overview" | "friends" | "posts";

// ─── Small pieces ───────────────────────────────────────────────────

function MiniStat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-2xl border border-white/[0.08] bg-white/[0.05] px-3 py-2.5">
      <div className="text-[10px] font-semibold tracking-[0.4px] text-white/55 uppercase">
        {label}
      </div>
      <div className="mad-num mt-0.5 text-xl font-extrabold text-white">
        {value}
      </div>
    </div>
  );
}

function Field({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-4 border-b border-white/5 py-1.5 text-sm last:border-0">
      <span className="text-white/40">{label}</span>
      <span className="text-right text-white/80">{value}</span>
    </div>
  );
}

function Heading({ children }: { children: ReactNode }) {
  return (
    <h3 className="mb-2 text-[11px] font-semibold tracking-[0.4px] text-white/45 uppercase">
      {children}
    </h3>
  );
}

function Avatar({
  url,
  fallback,
  size = "h-9 w-9 text-sm",
}: {
  url: string | null;
  fallback: string;
  size?: string;
}) {
  return url ? (
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src={mediaSrc(url)}
      alt=""
      className={`${size} shrink-0 rounded-full border border-white/10 object-cover`}
    />
  ) : (
    <div
      className={`${size} flex shrink-0 items-center justify-center rounded-full border border-white/10 bg-white/5 text-white/40`}
    >
      {fallback.slice(0, 1).toUpperCase()}
    </div>
  );
}

/** "Sep 12" for a YYYY-MM-DD — a tile has no room for the year. */
const shortDate = (d: string) => {
  const t = new Date(`${d}T00:00:00`);
  return Number.isNaN(t.getTime())
    ? d
    : t.toLocaleDateString(undefined, { month: "short", day: "numeric" });
};

const handleOf = (p: {
  username: string | null;
  name?: string | null;
  user_id: string;
}) => (p.username ? `@${p.username}` : p.name || p.user_id.slice(0, 8));

/**
 * One person, as a row you can open. Every list on this modal — friends,
 * requests, the people they brought in — is made of these, so the eye learns
 * one shape and every name on screen leads somewhere.
 */
function PersonButton({
  person,
  onOpen,
  chips,
  right,
  sub,
}: {
  person: PersonRow;
  onOpen: (p: PersonRow) => void;
  chips?: ReactNode;
  right?: ReactNode;
  sub?: ReactNode;
}) {
  return (
    <button
      onClick={() => onOpen(person)}
      // At phone width the stats drop under the name (indented past the
      // avatar) rather than squeezing it to "@m…" — a name is the one thing
      // on the row that must survive.
      className={`${CARD_INTERACTIVE} flex w-full flex-wrap items-center gap-x-3 gap-y-1 px-3 py-2.5 text-left sm:flex-nowrap`}
    >
      <Avatar
        url={person.profile_image_url}
        fallback={person.username || person.name || "?"}
      />
      <span className="min-w-0 flex-1">
        <span className="flex min-w-0 items-center gap-2">
          <span className="truncate text-sm font-semibold text-white/90">
            {handleOf(person)}
          </span>
          {chips}
        </span>
        {sub && (
          <span className="mt-0.5 block truncate text-xs text-white/40">
            {sub}
          </span>
        )}
      </span>
      {right && (
        <span className="w-full shrink-0 pl-12 text-left text-xs tabular-nums text-white/45 sm:w-auto sm:pl-0 sm:text-right">
          {right}
        </span>
      )}
    </button>
  );
}

// ─── The modal ──────────────────────────────────────────────────────

export function UserModal({
  userId,
  onClose,
  backTo,
  hint,
}: {
  userId: string;
  onClose: () => void;
  /** What the row that opened this already knew — drawn until the load lands. */
  hint?: PersonRow;
  /**
   * Set when this modal was opened FROM another user's modal (a friend, a
   * referrer). The close button then reads as "back to @them", because that
   * is exactly what closing does — the parent is still underneath.
   */
  backTo?: string;
}) {
  const [detail, setDetail] = useState<UserDetail | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [tab, setTab] = useState<Tab>("overview");
  const [child, setChild] = useState<PersonRow | null>(null);

  useEffect(() => {
    getData<UserDetail>(`users/${encodeURIComponent(userId)}`)
      .then(setDetail)
      .catch((e) => {
        if (e?.message !== "unauthorized") setErr("Failed to load user.");
      });
  }, [userId]);

  // Escape closes THIS modal — unless a friend's modal is stacked on top, or
  // one key press would dismiss both and lose the reader's place. Body
  // scroll is restored to whatever it was, not to "", so closing a stacked
  // modal doesn't unlock the page under the one still open.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape" && !child) onClose();
    };
    window.addEventListener("keydown", onKey);
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = prev;
    };
  }, [onClose, child]);

  const openPerson = useCallback((p: PersonRow) => setChild(p), []);

  const p = detail?.profile;
  const name = p
    ? [p.first_name, p.last_name].filter(Boolean).join(" ") || "—"
    : "";
  const title = p
    ? p.username
      ? `@${p.username}`
      : name
    : hint
      ? handleOf(hint)
      : "";

  const tabs: { id: Tab; label: string }[] = [
    { id: "overview", label: "Overview" },
    {
      id: "friends",
      label: detail ? `Friends · ${fmt(detail.social.friends)}` : "Friends",
    },
    {
      id: "posts",
      label: detail ? `Posts · ${fmt(detail.social.posts_live)}` : "Posts",
    },
  ];

  return (
    <>
      <div
        className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/70 p-4 backdrop-blur-sm sm:p-8"
        onClick={onClose}
      >
        <div
          className="w-full max-w-3xl rounded-2xl border border-white/[0.08] shadow-2xl"
          style={{ background: PANEL_BACKGROUND }}
          onClick={(e) => e.stopPropagation()}
        >
          {/* Header */}
          <div className="flex items-center gap-4 border-b border-white/[0.08] px-5 pt-5 pb-4">
            <Avatar
              url={p?.profile_image_url ?? hint?.profile_image_url ?? null}
              fallback={p?.username || p?.first_name || hint?.username || "?"}
              size="h-14 w-14 text-xl"
            />
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <h2 className="truncate text-lg font-semibold text-white">
                  {title}
                </h2>
                {p?.role && p.role !== "user" && (
                  <Chip text={p.role.toUpperCase()} tone="info" />
                )}
              </div>
              <p className="truncate text-sm text-white/50">
                {!p
                  ? "Loading…"
                  : `${name !== "—" && p.username ? `${name} · ` : ""}${p.email ?? "no email"}`}
              </p>
            </div>
            <button
              onClick={onClose}
              className="shrink-0 rounded-full border border-white/[0.12] px-3 py-1 text-sm text-white/60 transition hover:text-white"
            >
              {backTo ? `← ${backTo}` : "Close"}
            </button>
          </div>

          {/* Tabs — the dashboard's own underline style, one level down. */}
          <nav className="no-scrollbar flex gap-1 overflow-x-auto border-b border-white/[0.08] px-3">
            {tabs.map((t) => (
              <button
                key={t.id}
                onClick={() => setTab(t.id)}
                className={`relative whitespace-nowrap px-3 py-2.5 text-sm font-semibold transition ${
                  tab === t.id
                    ? "text-white"
                    : "text-white/45 hover:text-white/80"
                }`}
              >
                {t.label}
                {tab === t.id && (
                  <span
                    className="absolute inset-x-2 -bottom-px h-[2.5px] rounded-full"
                    style={{
                      background:
                        "linear-gradient(90deg, #e64d66 0%, #b3334d 100%)",
                    }}
                  />
                )}
              </button>
            ))}
          </nav>

          {err && <p className="p-5 text-sm text-[#d94059]">{err}</p>}
          {!detail && !err && (
            <div className="p-5">
              <Loading />
            </div>
          )}

          {detail && tab === "overview" && (
            <OverviewTab detail={detail} onOpen={openPerson} />
          )}
          {detail && tab === "friends" && (
            <FriendsTab userId={userId} onOpen={openPerson} />
          )}
          {detail && tab === "posts" && (
            <PostsTab userId={userId} onOpen={openPerson} />
          )}
        </div>
      </div>

      {/* A friend's profile stacks ABOVE this one, so closing it comes back
          here — the friend list is still where they left it. */}
      {child && (
        <UserModal
          userId={child.user_id}
          backTo={title || "back"}
          hint={child}
          onClose={() => setChild(null)}
        />
      )}
    </>
  );
}

// ─── Overview ───────────────────────────────────────────────────────

function OverviewTab({
  detail,
  onOpen,
}: {
  detail: UserDetail;
  onOpen: (p: PersonRow) => void;
}) {
  const p = detail.profile;
  const acq = detail.acquisition;

  return (
    <div className="space-y-5 p-5">
      {p.bio && (
        <p className="rounded-lg bg-white/[0.03] px-3 py-2 text-sm text-white/70">
          “{p.bio}”
        </p>
      )}

      <div className="grid grid-cols-3 gap-2 sm:grid-cols-4">
        <MiniStat label="Streak" value={`${p.current_streak}🔥`} />
        <MiniStat
          label="Total mi"
          value={fmt(Math.round(detail.stats.total_miles))}
        />
        <MiniStat label="Workouts" value={fmt(detail.stats.total_workouts)} />
        <MiniStat label="Active days" value={fmt(detail.stats.active_days)} />
        <MiniStat label="Mi (7d)" value={detail.stats.miles_7d.toFixed(1)} />
        <MiniStat label="Mi (30d)" value={detail.stats.miles_30d.toFixed(1)} />
        <MiniStat label="Friends" value={fmt(detail.social.friends)} />
        <MiniStat
          label="Posts"
          value={`${detail.social.posts_live}/${detail.social.posts_total}`}
        />
      </div>

      {/* How they got here. The one block on this modal that answers the
          question the dashboard exists for, so it gets a card of its own
          rather than a row in a column. */}
      <div className="rounded-2xl border border-white/[0.08] bg-white/[0.05] p-4">
        <Heading>How they heard about us</Heading>
        <div className="flex flex-wrap items-center gap-2 text-sm">
          <span className="font-semibold text-white/90">
            {p.referral_source
              ? prettySource(p.referral_source)
              : "Not asked yet"}
          </span>
          {acq?.typed_as && (
            <span className="text-white/45">— said “{acq.typed_as}”</span>
          )}
          {acq?.referred_by ? (
            <>
              <span className="text-white/30">→</span>
              <button
                onClick={() =>
                  onOpen({
                    user_id: acq.referred_by!.user_id,
                    username: acq.referred_by!.username,
                    name: null,
                    profile_image_url: null,
                  })
                }
                className="rounded-full border border-white/[0.12] bg-white/[0.05] px-2.5 py-0.5 text-sm font-semibold text-white/90 transition hover:border-white/25"
              >
                {acq.referred_by.username
                  ? `@${acq.referred_by.username}`
                  : acq.referred_by.user_id.slice(0, 8)}
              </button>
              {acq.referred_by.linked_by_hand && (
                <Chip text="linked by hand" tone="info" />
              )}
            </>
          ) : (
            acq?.typed_as && <Chip text="no such user" tone="bad" />
          )}
          {!acq?.typed_as && p.referral_detail && (
            <span className="text-white/45">— “{p.referral_detail}”</span>
          )}
        </div>

        {acq && (
          <div className="mt-4">
            <Heading>
              Brought in {fmt(acq.referred.length)}{" "}
              {acq.referred.length === 1 ? "person" : "people"}
            </Heading>
            {acq.referred.length === 0 ? (
              <p className="text-sm text-white/40">
                Nobody has named them at onboarding yet.
              </p>
            ) : (
              <ul className="space-y-1.5">
                {acq.referred.map((u) => (
                  <li key={u.user_id}>
                    <PersonButton
                      person={u}
                      onOpen={onOpen}
                      chips={u.is_friend && <Chip text="friends" tone="ok" />}
                      sub={
                        u.typed_as &&
                        u.typed_as.replace(/^@/, "").toLowerCase() !==
                          (p.username ?? "").toLowerCase()
                          ? `typed “${u.typed_as}”`
                          : `joined ${fmtDate(u.created_at)}`
                      }
                      right={
                        <>
                          <span className="block text-white/80">
                            {Math.round(u.total_miles ?? 0)} mi
                            {(u.current_streak ?? 0) > 0 &&
                              ` · ${u.current_streak}🔥`}
                          </span>
                          <span
                            className="block"
                            style={
                              u.last_active &&
                              relativeDay(u.last_active) !== "never" &&
                              !/mo|y ago/.test(relativeDay(u.last_active))
                                ? { color: MAD_SUCCESS }
                                : undefined
                            }
                          >
                            last run {relativeDay(u.last_active)}
                          </span>
                        </>
                      }
                    />
                  </li>
                ))}
              </ul>
            )}
          </div>
        )}
      </div>

      <div className="grid gap-5 sm:grid-cols-2">
        <div>
          <Heading>Account</Heading>
          <Field label="Goal" value={`${p.goal_miles} mi/day`} />
          <Field label="Joined" value={fmtDate(p.created_at)} />
          <Field
            label="Last active"
            value={relativeDay(detail.stats.last_active)}
          />
          <Field
            label="First mile"
            value={fmtDate(detail.stats.first_active)}
          />
          <Field
            label="Terms accepted"
            value={
              p.terms_accepted_at ? (
                <Chip text="Yes" tone="ok" />
              ) : (
                <Chip text="No" tone="muted" />
              )
            }
          />
          <Field
            label="User ID"
            value={
              <span className="font-mono text-xs">
                {p.user_id.slice(0, 12)}…
              </span>
            }
          />
        </div>
        <div>
          <Heading>Onboarding & social</Heading>
          <Field label="Signup goal" value={p.signup_goal ?? "—"} />
          <Field label="Experience" value={p.experience_level ?? "—"} />
          <Field
            label="Hypes"
            value={`${detail.social.hypes_sent} sent · ${detail.social.hypes_received} got`}
          />
          <Field
            label="Nudges"
            value={`${detail.social.nudges_sent} sent · ${detail.social.nudges_received} got (7d)`}
          />
          <Field
            label="Push devices"
            value={
              detail.devices.length === 0 ? (
                <span className="text-white/40">none</span>
              ) : (
                <span className="flex flex-wrap justify-end gap-1">
                  {detail.devices.map((d, i) => (
                    <Chip
                      key={i}
                      text={`${d.environment} · ${relativeDay(d.updated_at)}`}
                      tone={d.environment === "production" ? "ok" : "muted"}
                    />
                  ))}
                </span>
              )
            }
          />
        </div>
      </div>

      <div>
        <Heading>Recent workouts</Heading>
        {detail.recent_workouts.length === 0 ? (
          <p className="text-sm text-white/40">No workouts.</p>
        ) : (
          <ul className="divide-y divide-white/5 text-sm">
            {detail.recent_workouts.map((w) => (
              <li
                key={w.workout_id}
                className="flex items-center justify-between py-1.5"
              >
                <span className="flex items-center gap-2">
                  <span className="text-white/80">{w.local_date}</span>
                  <span className="text-white/50">
                    {w.workout_type ?? "—"} · {w.distance.toFixed(2)} mi
                  </span>
                </span>
                <span className="flex items-center gap-1.5">
                  {w.deleted_at && <Chip text="deleted" tone="bad" />}
                  {w.exclusion_reason && (
                    <Chip text={w.exclusion_reason} tone="bad" />
                  )}
                  {w.speed_flagged && <Chip text="speed?" tone="muted" />}
                </span>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}

// ─── Friends ────────────────────────────────────────────────────────

function FriendsTab({
  userId,
  onOpen,
}: {
  userId: string;
  onOpen: (p: PersonRow) => void;
}) {
  const [data, setData] = useState<FriendsResponse | null>(null);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    getData<FriendsResponse>(`users/${encodeURIComponent(userId)}/friends`)
      .then(setData)
      .catch((e) => {
        if (e?.message !== "unauthorized") setErr("Failed to load friends.");
      });
  }, [userId]);

  if (err) return <p className="p-5 text-sm text-[#d94059]">{err}</p>;
  if (!data)
    return (
      <div className="p-5">
        <Loading />
      </div>
    );

  const broughtIn = data.friends.filter((f) => f.referred_by_me).length;
  const referrer = data.friends.find((f) => f.referred_me);

  // Where this person's circle came from — the friends' own answers,
  // tallied. A circle that all said "Friend" grew by word of mouth; one that
  // all said "TikTok" found each other in the app.
  const sources = new Map<string, number>();
  for (const f of data.friends) {
    const k = f.referral_source ?? "unknown";
    sources.set(k, (sources.get(k) ?? 0) + 1);
  }
  const sourceRows = [...sources.entries()].sort((a, b) => b[1] - a[1]);

  const sent = data.pending.filter((r) => r.direction === "sent");
  const received = data.pending.filter((r) => r.direction === "received");

  return (
    <div className="space-y-5 p-5">
      {data.friends.length === 0 ? (
        <p className="text-sm text-white/40">No friends yet.</p>
      ) : (
        <>
          <div className="rounded-2xl border border-white/[0.08] bg-white/[0.05] p-4">
            <div className="flex flex-wrap items-baseline gap-x-4 gap-y-1 text-sm">
              <span className="text-white/90">
                <span className="mad-num font-extrabold">
                  {fmt(data.total)}
                </span>{" "}
                {data.total === 1 ? "friend" : "friends"}
              </span>
              <span className="text-white/50">
                <span className="text-white/90">{fmt(broughtIn)}</span> brought
                in by them
              </span>
              {referrer && (
                <span className="text-white/50">
                  referred by{" "}
                  <span className="text-white/90">{handleOf(referrer)}</span>
                </span>
              )}
            </div>
            <div className="mt-3">
              <Heading>How their friends heard about us</Heading>
              <div className="flex flex-wrap gap-1.5">
                {sourceRows.map(([k, n]) => (
                  <span
                    key={k}
                    className="rounded-full border border-white/[0.12] bg-white/[0.05] px-2.5 py-1 text-xs text-white/70"
                  >
                    {prettySource(k)}{" "}
                    <span className="mad-num font-semibold text-white">
                      {n}
                    </span>
                  </span>
                ))}
              </div>
            </div>
          </div>

          <ul className="space-y-1.5">
            {data.friends.map((f) => (
              <li key={f.user_id}>
                <PersonButton
                  person={f}
                  onOpen={onOpen}
                  chips={
                    <>
                      {f.role && f.role !== "user" && (
                        <Chip text={f.role} tone="info" />
                      )}
                      {f.referred_by_me && (
                        <Chip text="they brought in" tone="ok" />
                      )}
                      {f.referred_me && (
                        <Chip text="referred them" tone="info" />
                      )}
                    </>
                  }
                  sub={
                    <>
                      {f.name && f.username ? `${f.name} · ` : ""}
                      {f.referral_source
                        ? `via ${prettySource(f.referral_source)}`
                        : "source not asked"}
                      {f.referral_source &&
                        f.referral_detail &&
                        !f.referred_by_me &&
                        ` “${f.referral_detail}”`}
                      {f.mutual_friends > 0 && ` · ${f.mutual_friends} mutual`}
                    </>
                  }
                  right={
                    <>
                      <span className="block text-white/80">
                        {Math.round(f.total_miles)} mi
                        {f.current_streak > 0 && ` · ${f.current_streak}🔥`}
                        {f.photo_count > 0 && ` · ${f.photo_count} 📷`}
                      </span>
                      <span className="block">
                        last run {relativeDay(f.last_active)} · friends since{" "}
                        {fmtDate(f.friends_since)}
                      </span>
                    </>
                  }
                />
              </li>
            ))}
          </ul>
        </>
      )}

      {(sent.length > 0 || received.length > 0) && (
        <div className="grid gap-5 sm:grid-cols-2">
          <div>
            <Heading>Requests they sent · {sent.length}</Heading>
            {sent.length === 0 ? (
              <p className="text-sm text-white/40">None waiting.</p>
            ) : (
              <ul className="space-y-1.5">
                {sent.map((r) => (
                  <li key={r.user_id}>
                    <PersonButton
                      person={r}
                      onOpen={onOpen}
                      chips={
                        r.status === "ignored" && (
                          <Chip text="ignored" tone="muted" />
                        )
                      }
                      right={fmtDate(r.created_at)}
                    />
                  </li>
                ))}
              </ul>
            )}
          </div>
          <div>
            <Heading>Requests waiting on them · {received.length}</Heading>
            {received.length === 0 ? (
              <p className="text-sm text-white/40">None waiting.</p>
            ) : (
              <ul className="space-y-1.5">
                {received.map((r) => (
                  <li key={r.user_id}>
                    <PersonButton
                      person={r}
                      onOpen={onOpen}
                      chips={
                        r.status === "ignored" && (
                          <Chip text="ignored" tone="muted" />
                        )
                      }
                      right={fmtDate(r.created_at)}
                    />
                  </li>
                ))}
              </ul>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

// ─── Posts ──────────────────────────────────────────────────────────

function PostsTab({
  userId,
  onOpen,
}: {
  userId: string;
  onOpen: (p: PersonRow) => void;
}) {
  const [scope, setScope] = useState<PostScope>("all");
  const [data, setData] = useState<PostsResponse | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [loadingMore, setLoadingMore] = useState(false);
  const [open, setOpen] = useState<PostRow | null>(null);

  useEffect(() => {
    setData(null);
    const params = new URLSearchParams({ scope, limit: String(POSTS_PAGE) });
    getData<PostsResponse>(
      `users/${encodeURIComponent(userId)}/posts?${params.toString()}`,
    )
      .then(setData)
      .catch((e) => {
        if (e?.message !== "unauthorized") setErr("Failed to load posts.");
      });
  }, [userId, scope]);

  async function loadMore() {
    if (!data) return;
    setLoadingMore(true);
    try {
      const params = new URLSearchParams({
        scope,
        limit: String(POSTS_PAGE),
        offset: String(data.posts.length),
      });
      const next = await getData<PostsResponse>(
        `users/${encodeURIComponent(userId)}/posts?${params.toString()}`,
      );
      setData({ ...next, posts: [...data.posts, ...next.posts] });
    } catch {
      /* unauthorized handled in getData */
    } finally {
      setLoadingMore(false);
    }
  }

  if (err) return <p className="p-5 text-sm text-[#d94059]">{err}</p>;

  const s = data?.summary;

  return (
    <div className="space-y-4 p-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <SegmentedControl<PostScope>
          value={scope}
          onChange={setScope}
          options={[
            { value: "all", label: "All" },
            { value: "photos", label: "Photos" },
            { value: "auto", label: "Auto cards" },
            { value: "deleted", label: "Deleted" },
          ]}
        />
        {s && (
          // Photos, not posts: an auto route card is published FOR the user
          // when they skip the prompt, so it says nothing about whether they
          // use the social feature. The split is the number that does.
          <span className="text-xs text-white/40">
            {fmt(s.photos)} photos · {fmt(s.auto)} auto · {fmt(s.on_feed)} on
            feed · {fmt(s.stories)} stories
            {s.deleted > 0 && ` · ${fmt(s.deleted)} deleted`}
          </span>
        )}
      </div>

      {!data ? (
        <Loading />
      ) : data.posts.length === 0 ? (
        <p className="text-sm text-white/40">
          {scope === "all"
            ? "They haven't posted anything."
            : `Nothing under “${scope}”.`}
        </p>
      ) : (
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4">
          {data.posts.map((post) => (
            <button
              key={post.post_id}
              onClick={() => setOpen(post)}
              className="group overflow-hidden rounded-2xl border border-white/[0.08] bg-black/40 text-left transition hover:border-white/20"
            >
              <div className="relative aspect-[4/5]">
                {post.media_url ? (
                  <>
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img
                    src={mediaSrc(post.media_url)}
                    alt=""
                    loading="lazy"
                    className={`h-full w-full object-cover ${
                      post.deleted_at ? "opacity-40" : ""
                    }`}
                    onError={(e) => {
                      (e.target as HTMLImageElement).style.opacity = "0.12";
                    }}
                  />
                  </>
                ) : (
                  <LiveCardTile className={`h-full w-full object-cover ${
                    post.deleted_at ? "opacity-40" : ""
                  }`} />
                )}
                <div className="absolute top-1.5 left-1.5 flex flex-wrap gap-1">
                  {post.deleted_at && <Chip text="DELETED" tone="bad" />}
                  {post.pinned_at && <Chip text="PINNED" tone="info" />}
                </div>
                <div className="absolute bottom-1.5 left-1.5 flex flex-wrap gap-1">
                  {post.is_auto && <Chip text="AUTO" tone="muted" />}
                  {post.share_to_story && !post.share_to_feed && (
                    <Chip text="STORY ONLY" tone="muted" />
                  )}
                  {post.is_buddy_walk && <Chip text="BUDDY" tone="ok" />}
                  {post.coauthor_username && !post.is_buddy_walk && (
                    <Chip text="COLLAB" tone="ok" />
                  )}
                </div>
              </div>
              <div className="p-2.5">
                <div className="truncate text-[11px] text-white/60">
                  {shortDate(post.local_date)}
                  {post.workout_distance != null &&
                    ` · ${post.workout_distance.toFixed(2)} mi`}
                </div>
                {(post.hype_count > 0 || post.comment_count > 0) && (
                  <div className="mt-0.5 text-[11px] tabular-nums text-white/40">
                    {post.hype_count > 0 && `👏 ${post.hype_count}`}
                    {post.hype_count > 0 && post.comment_count > 0 && " · "}
                    {post.comment_count > 0 && `💬 ${post.comment_count}`}
                  </div>
                )}
                {post.caption && (
                  <p className="mt-1 line-clamp-2 text-xs text-white/75">
                    {post.caption}
                  </p>
                )}
              </div>
            </button>
          ))}
        </div>
      )}

      {data && data.posts.length < data.matching && (
        <button
          onClick={loadMore}
          disabled={loadingMore}
          className="w-full rounded-full border border-white/[0.12] py-2 text-sm text-white/60 transition hover:text-white disabled:opacity-40"
        >
          {loadingMore
            ? "Loading…"
            : `Show more (${fmt(data.matching - data.posts.length)} left)`}
        </button>
      )}

      {open && (
        <PostLightbox
          post={open}
          onClose={() => setOpen(null)}
          onOpen={onOpen}
        />
      )}
    </div>
  );
}

/** One post at full size, with everything the tile had to abbreviate. */
function PostLightbox({
  post,
  onClose,
  onOpen,
}: {
  post: PostRow;
  onClose: () => void;
  onOpen: (p: PersonRow) => void;
}) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        e.stopPropagation();
        onClose();
      }
    };
    // Capture phase so this fires before the modal's own Escape handler.
    window.addEventListener("keydown", onKey, true);
    return () => window.removeEventListener("keydown", onKey, true);
  }, [onClose]);

  const flags: string[] = [];
  if (post.share_to_feed) flags.push("feed");
  if (post.share_to_story) flags.push("story");
  if (post.include_route === false) flags.push("route hidden");
  if (post.is_auto) flags.push("auto card");
  if (post.pinned_at) flags.push("pinned");

  return (
    <div
      className="fixed inset-0 z-[60] flex items-center justify-center bg-black/85 p-4 backdrop-blur-sm"
      onClick={onClose}
    >
      <div
        className="flex max-h-full w-full max-w-3xl flex-col gap-4 overflow-y-auto rounded-2xl border border-white/[0.08] p-4 sm:flex-row"
        style={{ background: PANEL_BACKGROUND }}
        onClick={(e) => e.stopPropagation()}
      >
        {post.media_url ? (
          <>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={mediaSrc(post.media_url)}
            alt=""
            className="max-h-[70vh] w-full rounded-xl object-contain sm:w-3/5"
          />
          </>
        ) : (
          <LiveCardTile className="aspect-[4/5] w-full rounded-xl sm:w-3/5" />
        )}
        <div className="flex min-w-0 flex-1 flex-col gap-3 text-sm">
          <div className="flex items-start justify-between gap-3">
            <div>
              <div className="text-white/90">{post.local_date}</div>
              <div className="text-xs text-white/40">
                posted {new Date(post.created_at).toLocaleString()}
              </div>
            </div>
            <button
              onClick={onClose}
              className="shrink-0 rounded-full border border-white/[0.12] px-3 py-1 text-xs text-white/60 transition hover:text-white"
            >
              Close
            </button>
          </div>
          {post.caption ? (
            <p className="whitespace-pre-wrap text-white/80">{post.caption}</p>
          ) : (
            <p className="text-white/35">No caption.</p>
          )}
          <div className="flex flex-wrap gap-1.5">
            {post.deleted_at && <Chip text="deleted" tone="bad" />}
            {flags.map((f) => (
              <Chip key={f} text={f} />
            ))}
            {post.is_buddy_walk && <Chip text="buddy walk" tone="ok" />}
          </div>
          <div>
            <Field
              label="Workout"
              value={
                post.workout_distance != null
                  ? `${post.workout_type ?? "—"} · ${post.workout_distance.toFixed(2)} mi`
                  : "not linked"
              }
            />
            <Field label="Hypes" value={fmt(post.hype_count)} />
            <Field label="Comments" value={fmt(post.comment_count)} />
            {post.crew_photos > 0 && (
              <Field label="Crew photos" value={fmt(post.crew_photos)} />
            )}
            {post.coauthor_user_id && (
              <Field
                label="With"
                value={
                  <button
                    onClick={() => {
                      onClose();
                      onOpen({
                        user_id: post.coauthor_user_id!,
                        username: post.coauthor_username,
                        name: null,
                        profile_image_url: null,
                      });
                    }}
                    className="text-white/90 underline decoration-white/30 underline-offset-2 hover:decoration-white"
                  >
                    {post.coauthor_username
                      ? `@${post.coauthor_username}`
                      : post.coauthor_user_id.slice(0, 8)}
                  </button>
                }
              />
            )}
            <Field
              label="Post ID"
              value={
                <span className="font-mono text-xs">
                  {post.post_id.slice(0, 13)}…
                </span>
              }
            />
          </div>
        </div>
      </div>
    </div>
  );
}
