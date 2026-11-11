"use client";

import { useEffect, useRef } from "react";
import { usePathname } from "next/navigation";

// The site's own analytics: one event per page view (including client-side
// navigations) and per click on a link or button, sent to the backend's
// POST /public/web-events and shown in the admin Website tab. Anonymous: no
// cookie, no storage, nothing that identifies a person (the backend makes a
// visitor id that changes every day). Visitors asking not to be tracked
// (Do Not Track / Global Privacy Control) send nothing. Never on /admin.

const API_URL =
  process.env.NEXT_PUBLIC_API_URL || "https://mad.mindgoblin.tech";
const ENDPOINT = `${API_URL}/public/web-events`;
const SKIP = /^\/(admin|users)(\/|$)/;

function optedOut(): boolean {
  const n = navigator as Navigator & {
    globalPrivacyControl?: boolean;
    msDoNotTrack?: string;
  };
  return (
    n.globalPrivacyControl === true ||
    n.doNotTrack === "1" ||
    n.msDoNotTrack === "1"
  );
}

function send(event: Record<string, unknown>) {
  try {
    void fetch(ENDPOINT, {
      method: "POST",
      keepalive: true, // survives the page unloading (an App Store tap leaves the site)
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(event),
    }).catch(() => {});
  } catch {
    // Analytics never gets in the way.
  }
}

/** What a click was on: `data-track`, else what the link does, else its words. */
function labelFor(el: HTMLElement): string | null {
  const tagged = el.closest<HTMLElement>("[data-track]");
  if (tagged?.dataset.track) return tagged.dataset.track;
  const link = el.closest("a");
  if (link?.href) {
    try {
      const url = new URL(link.href, location.href);
      if (
        url.hostname === "apps.apple.com" ||
        url.hostname === "itunes.apple.com"
      )
        return "app_store";
      if (url.protocol === "mailto:") return "email";
      if (url.protocol === "mileaday:") return "open_in_app";
      if (url.origin !== location.origin)
        return `out:${url.hostname.replace(/^www\./, "")}`;
    } catch {
      // fall through to the text
    }
  }
  const clickable = link ?? el.closest("button, [role='button'], summary");
  if (!clickable) return null;
  const text = (
    clickable.getAttribute("aria-label") ||
    clickable.textContent ||
    ""
  )
    .replace(/\s+/g, " ")
    .trim();
  return text ? text.slice(0, 60) : null;
}

export function SiteTracker() {
  const pathname = usePathname();
  const firstView = useRef(true);

  // A page view per path (the first one carries how they arrived).
  useEffect(() => {
    if (!pathname || SKIP.test(pathname) || optedOut()) return;
    const params = new URLSearchParams(location.search);
    send({
      kind: "view",
      path: pathname,
      referrer: firstView.current ? document.referrer || null : null,
      utm_source: params.get("utm_source"),
      utm_medium: params.get("utm_medium"),
      utm_campaign: params.get("utm_campaign"),
    });
    firstView.current = false;
  }, [pathname]);

  // Clicks, from one listener for the whole document.
  useEffect(() => {
    const onClick = (e: MouseEvent) => {
      const path = location.pathname;
      if (SKIP.test(path) || optedOut()) return;
      const target = e.target instanceof HTMLElement ? e.target : null;
      const label = target && labelFor(target);
      if (label) send({ kind: "click", path, target: label });
    };
    document.addEventListener("click", onClick, { capture: true });
    return () =>
      document.removeEventListener("click", onClick, { capture: true });
  }, []);

  return null;
}
