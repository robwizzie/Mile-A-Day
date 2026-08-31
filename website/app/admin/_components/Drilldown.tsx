"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from "react";
import { CARD_INTERACTIVE, MAD_RED, PANEL_BACKGROUND } from "./theme";
import { fmt, getData, Loading } from "./lib";
import { UserModal } from "./UserModal";

/**
 * Every number on this dashboard is an aggregate over rows somebody will
 * eventually want to see. Rather than a bespoke expander per panel, one drawer
 * resolves any of them: a panel calls `open(kind, id)` and the backend's
 * /admin/drilldown returns the rows in a single shape.
 *
 * Rows that carry a `user_id` chain straight into the existing user modal, so
 * "which of my users spent a streak token" ends on that person's profile
 * rather than at a username you then have to go search for.
 */

type DrilldownRow = {
  user_id: string | null;
  username: string | null;
  title: string;
  subtitle: string | null;
  stat: string | null;
  meta: string | null;
};

type DrilldownData = {
  kind: string;
  id: string | null;
  title: string;
  subtitle: string | null;
  total: number;
  rows: DrilldownRow[];
};

type Target = {
  kind: string;
  id?: string | null;
  /**
   * Turns the drawer into a PICKER: a row calls this with its user instead
   * of opening that person's profile. Used to answer "who did they mean?"
   * for a referral name that matches no account.
   */
  onPick?: (userId: string, username: string | null) => void;
  /** Replaces the row hint in the footer when picking. */
  pickHint?: string;
};

const DrilldownContext = createContext<(t: Target) => void>(() => {});
const UserContext = createContext<(userId: string) => void>(() => {});

/** Open the rows behind a number. `useDrilldown()(...)` from any panel. */
export function useDrilldown() {
  return useContext(DrilldownContext);
}

/**
 * Open one person's profile from anywhere. Every leaderboard on this
 * dashboard ends in a username, and "who is that" is the next question every
 * time — so the modal is reachable without going via a list first.
 */
export function useOpenUser() {
  return useContext(UserContext);
}

export function DrilldownProvider({ children }: { children: ReactNode }) {
  const [target, setTarget] = useState<Target | null>(null);
  const [directUser, setDirectUser] = useState<string | null>(null);
  const open = useCallback((t: Target) => setTarget(t), []);
  const openUser = useCallback((userId: string) => setDirectUser(userId), []);
  return (
    <DrilldownContext.Provider value={open}>
      <UserContext.Provider value={openUser}>
        {children}
        {target && (
          <DrilldownDrawer target={target} onClose={() => setTarget(null)} />
        )}
        {directUser && (
          <UserModal
            userId={directUser}
            onClose={() => setDirectUser(null)}
          />
        )}
      </UserContext.Provider>
    </DrilldownContext.Provider>
  );
}

function DrilldownDrawer({
  target,
  onClose,
}: {
  target: Target;
  onClose: () => void;
}) {
  const [data, setData] = useState<DrilldownData | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [openUser, setOpenUser] = useState<string | null>(null);

  useEffect(() => {
    setData(null);
    setErr(null);
    const params = new URLSearchParams({ kind: target.kind });
    if (target.id) params.set("id", target.id);
    getData<DrilldownData>(`drilldown?${params.toString()}`)
      .then(setData)
      .catch((e) => {
        if (e?.message !== "unauthorized")
          setErr("Nothing to show for this one.");
      });
  }, [target.kind, target.id]);

  // Escape closes the drawer — but only when no user modal is stacked on top
  // of it, or one key press would dismiss both and lose the reader's place.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape" && !openUser) onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose, openUser]);

  return (
    <>
      <div className="fixed inset-0 z-50 flex justify-end">
        <button
          aria-label="Close"
          onClick={onClose}
          className="absolute inset-0 bg-black/60 backdrop-blur-[2px]"
        />
        <aside
          className="relative flex h-full w-full max-w-md flex-col border-l border-white/[0.08] shadow-2xl"
          // One flat step off the page rather than a gradient: the drawer
          // slides over content, and a gradient panel over a gradient page
          // reads as two different blacks fighting.
          style={{ background: PANEL_BACKGROUND }}
        >
          <header className="flex items-start justify-between gap-3 border-b border-white/[0.08] px-5 py-4">
            <div className="min-w-0">
              <h2 className="mad-num truncate text-lg font-extrabold text-white">
                {data?.title ?? "Loading…"}
              </h2>
              {data?.subtitle && (
                <p className="mt-0.5 text-xs text-white/45">{data.subtitle}</p>
              )}
            </div>
            <button
              onClick={onClose}
              className="shrink-0 rounded-full border border-white/[0.12] px-3 py-1 text-xs text-white/60 transition hover:text-white"
            >
              Close
            </button>
          </header>

          <div className="flex-1 overflow-y-auto px-5 py-4">
            {err ? (
              <p className="text-sm text-white/40">{err}</p>
            ) : !data ? (
              <Loading />
            ) : data.rows.length === 0 ? (
              <p className="text-sm text-white/40">
                Nobody yet — the number that opened this is zero.
              </p>
            ) : (
              <ul className="space-y-1.5">
                {data.rows.map((r, i) => {
                  const inner = (
                    <div className="flex items-baseline justify-between gap-3">
                      <span className="min-w-0">
                        <span className="block truncate text-sm text-white/90">
                          {r.title}
                        </span>
                        {r.subtitle && (
                          <span className="block truncate text-xs text-white/40">
                            {r.subtitle}
                          </span>
                        )}
                      </span>
                      <span className="shrink-0 text-right">
                        {r.stat && (
                          <span className="block text-sm font-semibold tabular-nums text-white/90">
                            {r.stat}
                          </span>
                        )}
                        {r.meta && (
                          <span className="block text-xs tabular-nums text-white/35">
                            {r.meta}
                          </span>
                        )}
                      </span>
                    </div>
                  );
                  return (
                    <li key={`${r.user_id ?? r.title}-${i}`}>
                      {r.user_id ? (
                        <button
                          onClick={() => {
                            if (target.onPick) {
                              target.onPick(r.user_id!, r.username);
                              onClose();
                            } else {
                              setOpenUser(r.user_id);
                            }
                          }}
                          className={`${CARD_INTERACTIVE} w-full px-3 py-2.5 text-left`}
                        >
                          {inner}
                        </button>
                      ) : (
                        <div className="rounded-2xl border border-white/[0.08] bg-white/[0.05] px-3 py-2.5">
                          {inner}
                        </div>
                      )}
                    </li>
                  );
                })}
              </ul>
            )}
          </div>

          {data && data.rows.length > 0 && (
            <footer className="border-t border-white/[0.08] px-5 py-3 text-xs text-white/35">
              {fmt(data.rows.length)} shown
              {data.rows.length >= 100 && " (capped at 100)"}
              <span className="ml-2" style={{ color: MAD_RED }}>
                ·
              </span>{" "}
              {target.pickHint ?? "tap a row for that user"}
            </footer>
          )}
        </aside>
      </div>

      {/* Stacked above the drawer so closing the profile returns to the list. */}
      {openUser && (
        <UserModal userId={openUser} onClose={() => setOpenUser(null)} />
      )}
    </>
  );
}
