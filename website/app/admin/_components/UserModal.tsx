"use client";

import { useEffect, useState, type ReactNode } from "react";
import {
  Chip,
  fmt,
  fmtDate,
  fmtDateTime,
  getData,
  Loading,
  mediaSrc,
  relativeDay,
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
  recent_posts: {
    post_id: string;
    media_url: string;
    caption: string | null;
    is_auto: boolean;
    share_to_feed: boolean;
    share_to_story: boolean;
    local_date: string;
    created_at: string;
    deleted_at: string | null;
  }[];
};

function MiniStat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg border border-white/10 bg-white/[0.02] px-3 py-2">
      <div className="text-[10px] uppercase tracking-wide text-white/40">
        {label}
      </div>
      <div className="mt-0.5 text-lg font-semibold text-white">{value}</div>
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

export function UserModal({
  userId,
  onClose,
}: {
  userId: string;
  onClose: () => void;
}) {
  const [detail, setDetail] = useState<UserDetail | null>(null);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    getData<UserDetail>(`users/${encodeURIComponent(userId)}`)
      .then(setDetail)
      .catch((e) => {
        if (e?.message !== "unauthorized") setErr("Failed to load user.");
      });
  }, [userId]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = "";
    };
  }, [onClose]);

  const p = detail?.profile;
  const name = p
    ? [p.first_name, p.last_name].filter(Boolean).join(" ") || "—"
    : "";

  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/70 p-4 backdrop-blur-sm sm:p-8"
      onClick={onClose}
    >
      <div
        className="w-full max-w-2xl rounded-2xl border border-white/10 bg-[#111] shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center gap-4 border-b border-white/10 p-5">
          {p?.profile_image_url ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={mediaSrc(p.profile_image_url)}
              alt=""
              className="h-14 w-14 shrink-0 rounded-full border border-white/10 object-cover"
            />
          ) : (
            <div className="flex h-14 w-14 shrink-0 items-center justify-center rounded-full border border-white/10 bg-white/5 text-xl text-white/40">
              {(p?.username || p?.first_name || "?").slice(0, 1).toUpperCase()}
            </div>
          )}
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-2">
              <h2 className="truncate text-lg font-semibold text-white">
                {p?.username ? `@${p.username}` : name}
              </h2>
              {p?.role && p.role !== "user" && (
                <Chip text={p.role.toUpperCase()} tone="info" />
              )}
            </div>
            <p className="truncate text-sm text-white/50">
              {name !== "—" && p?.username ? `${name} · ` : ""}
              {p?.email ?? "no email"}
            </p>
          </div>
          <button
            onClick={onClose}
            className="shrink-0 rounded-md border border-white/10 px-2.5 py-1 text-sm text-white/60 hover:text-white"
          >
            Close
          </button>
        </div>

        {err && <p className="p-5 text-sm text-[#c72554]">{err}</p>}
        {!detail && !err && (
          <div className="p-5">
            <Loading />
          </div>
        )}

        {detail && (
          <div className="space-y-5 p-5">
            {p?.bio && (
              <p className="rounded-lg bg-white/[0.03] px-3 py-2 text-sm text-white/70">
                “{p.bio}”
              </p>
            )}

            {/* Activity stats */}
            <div className="grid grid-cols-3 gap-2 sm:grid-cols-4">
              <MiniStat
                label="Streak"
                value={`${detail.profile.current_streak}🔥`}
              />
              <MiniStat
                label="Total mi"
                value={fmt(Math.round(detail.stats.total_miles))}
              />
              <MiniStat
                label="Workouts"
                value={fmt(detail.stats.total_workouts)}
              />
              <MiniStat
                label="Active days"
                value={fmt(detail.stats.active_days)}
              />
              <MiniStat
                label="Mi (7d)"
                value={detail.stats.miles_7d.toFixed(1)}
              />
              <MiniStat
                label="Mi (30d)"
                value={detail.stats.miles_30d.toFixed(1)}
              />
              <MiniStat label="Friends" value={fmt(detail.social.friends)} />
              <MiniStat
                label="Posts"
                value={`${detail.social.posts_live}/${detail.social.posts_total}`}
              />
            </div>

            {/* Two-column detail */}
            <div className="grid gap-5 sm:grid-cols-2">
              <div>
                <h3 className="mb-2 text-xs font-medium uppercase tracking-wide text-white/40">
                  Account
                </h3>
                <Field
                  label="Goal"
                  value={`${detail.profile.goal_miles} mi/day`}
                />
                <Field
                  label="Joined"
                  value={fmtDate(detail.profile.created_at)}
                />
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
                    detail.profile.terms_accepted_at ? (
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
                      {detail.profile.user_id.slice(0, 12)}…
                    </span>
                  }
                />
              </div>
              <div>
                <h3 className="mb-2 text-xs font-medium uppercase tracking-wide text-white/40">
                  Acquisition & social
                </h3>
                <Field
                  label="Heard via"
                  value={detail.profile.referral_source ?? "—"}
                />
                {detail.profile.referral_detail && (
                  <Field
                    label="Referral detail"
                    value={detail.profile.referral_detail}
                  />
                )}
                <Field
                  label="Signup goal"
                  value={detail.profile.signup_goal ?? "—"}
                />
                <Field
                  label="Experience"
                  value={detail.profile.experience_level ?? "—"}
                />
                <Field
                  label="Hypes"
                  value={`${detail.social.hypes_sent} sent · ${detail.social.hypes_received} got`}
                />
                <Field
                  label="Nudges"
                  value={`${detail.social.nudges_sent} sent · ${detail.social.nudges_received} got`}
                />
              </div>
            </div>

            {/* Devices */}
            <div>
              <h3 className="mb-2 text-xs font-medium uppercase tracking-wide text-white/40">
                Push devices ({detail.devices.length})
              </h3>
              {detail.devices.length === 0 ? (
                <p className="text-sm text-white/40">No registered devices.</p>
              ) : (
                <div className="flex flex-wrap gap-2">
                  {detail.devices.map((d, i) => (
                    <span
                      key={i}
                      className="rounded-md border border-white/10 bg-white/[0.02] px-2.5 py-1 text-xs text-white/60"
                    >
                      <Chip
                        text={d.environment}
                        tone={d.environment === "production" ? "ok" : "muted"}
                      />{" "}
                      <span className="ml-1">
                        seen {relativeDay(d.updated_at)}
                      </span>
                    </span>
                  ))}
                </div>
              )}
            </div>

            {/* Recent posts */}
            {detail.recent_posts.length > 0 && (
              <div>
                <h3 className="mb-2 text-xs font-medium uppercase tracking-wide text-white/40">
                  Recent posts
                </h3>
                <div className="flex gap-2 overflow-x-auto pb-1">
                  {detail.recent_posts.map((post) => (
                    <div key={post.post_id} className="relative shrink-0">
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img
                        src={mediaSrc(post.media_url)}
                        alt=""
                        className={`h-24 w-20 rounded-md border border-white/10 object-cover ${
                          post.deleted_at ? "opacity-40" : ""
                        }`}
                        onError={(e) => {
                          (e.target as HTMLImageElement).style.opacity = "0.15";
                        }}
                      />
                      {post.deleted_at && (
                        <span className="absolute left-1 top-1 rounded bg-[#c72554]/80 px-1 text-[9px] font-medium text-white">
                          DEL
                        </span>
                      )}
                      {post.is_auto && (
                        <span className="absolute bottom-1 left-1 rounded bg-black/70 px-1 text-[9px] text-white/70">
                          AUTO
                        </span>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Recent workouts */}
            <div>
              <h3 className="mb-2 text-xs font-medium uppercase tracking-wide text-white/40">
                Recent workouts
              </h3>
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
        )}
      </div>
    </div>
  );
}
