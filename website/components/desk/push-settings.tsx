"use client";

import { useCallback, useEffect, useState } from "react";
import { getData, postData } from "@/app/admin/_components/lib";

const LABELS: Record<string, [string, string]> = {
  doodle: ["Doodles", "Someone sent your desk a doodle"],
  message: ["Desk messages", "A message for your desk"],
  new_user: ["New users", "Every new person who joins"],
  user_milestone: ["User milestones", "Every 50 users"],
  interest: ["“I'd buy one”", "A new desk box signup on the website"],
  review: ["App Store reviews", "A new review comes in"],
  record: ["Record signup day", "Today beats the best of the last 30 days"],
  lead: ["Versus lead", "The lead for today changes hands"],
  box_offline: ["Desk offline", "Your desk stops checking in (and comes back)"],
};

type Info = { enabled: boolean; public_key: string | null; kinds: string[]; default_kinds: string[];
              subscriptions: { endpoint: string; kinds: string[]; service: string }[] };

function keyBytes(b64: string): Uint8Array {
  const pad = "=".repeat((4 - (b64.length % 4)) % 4);
  const raw = atob((b64 + pad).replace(/-/g, "+").replace(/_/g, "/"));
  return Uint8Array.from(raw, (c) => c.charCodeAt(0));
}

/** Notifications on this phone for the desk (web push). Own phone only. */
export function PushSettings({ say }: { say: (m: string) => void }) {
  const [info, setInfo] = useState<Info | null>(null);
  const [endpoint, setEndpoint] = useState<string | null>(null);   // this browser's, if subscribed
  const [support, setSupport] = useState<"ok" | "install" | "no">("ok");
  const [busy, setBusy] = useState(false);

  const refresh = useCallback(async () => {
    const i = await getData<Info>("desk/push").catch(() => null);
    setInfo(i);
    if ("serviceWorker" in navigator) {
      const reg = await navigator.serviceWorker.getRegistration("/admin/");
      const sub = await reg?.pushManager?.getSubscription();
      setEndpoint(sub?.endpoint ?? null);
    }
  }, []);

  useEffect(() => {
    const standalone = window.matchMedia?.("(display-mode: standalone)").matches || (navigator as any).standalone;
    const ios = /iPhone|iPad|iPod/.test(navigator.userAgent);
    if (!("serviceWorker" in navigator) || !("PushManager" in window)) setSupport(ios && !standalone ? "install" : "no");
    refresh();
  }, [refresh]);

  const mine = info?.subscriptions.find((s) => s.endpoint === endpoint) ?? null;

  async function turnOn() {
    if (!info?.public_key) return;
    setBusy(true);
    try {
      const perm = await Notification.requestPermission();
      if (perm !== "granted") throw new Error("Notifications are blocked for this site in Settings");
      const reg = await navigator.serviceWorker.register("/admin-sw.js", { scope: "/admin/" });
      await navigator.serviceWorker.ready;
      const sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: keyBytes(info.public_key) as BufferSource });
      await postData("desk/push/subscribe", { subscription: sub.toJSON() });
      say("Notifications are on for this phone");
      await refresh();
    } catch (e) {
      say((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  async function turnOff() {
    if (!endpoint) return;
    setBusy(true);
    try {
      await postData("desk/push/unsubscribe", { endpoint });
      const reg = await navigator.serviceWorker.getRegistration("/admin/");
      await (await reg?.pushManager.getSubscription())?.unsubscribe();
      say("Notifications are off for this phone");
      await refresh();
    } catch (e) {
      say((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  async function toggle(kind: string) {
    if (!mine || !endpoint) return;
    const kinds = mine.kinds.includes(kind) ? mine.kinds.filter((k) => k !== kind) : [...mine.kinds, kind];
    setInfo((i) => i && { ...i, subscriptions: i.subscriptions.map((s) => (s.endpoint === endpoint ? { ...s, kinds } : s)) });
    await postData("desk/push/kinds", { endpoint, kinds }).catch((e) => say((e as Error).message));
  }

  if (!info) return null;
  if (!info.enabled || !info.public_key) {
    return <p className="text-sm text-white/50">Push isn&apos;t set up on the server yet (it needs VAPID keys).</p>;
  }
  if (support === "install") {
    return (
      <p className="text-sm text-white/60">
        On iPhone, notifications need this page on your home screen: tap Share → Add to Home Screen, then open
        MAD Desk from there and come back here.
      </p>
    );
  }
  if (support === "no") return <p className="text-sm text-white/50">This browser can&apos;t do web notifications.</p>;

  return (
    <div className="flex flex-col gap-2">
      {!mine ? (
        <button disabled={busy} onClick={turnOn} className="rounded-xl py-2.5 text-sm font-extrabold disabled:opacity-50"
                style={{ background: "#d94059" }}>
          Turn on notifications on this phone
        </button>
      ) : (
        <>
          <ul className="flex flex-col">
            {info.kinds.map((k) => (
              <li key={k} className="flex items-center gap-3 border-b border-white/[0.06] py-2 last:border-0">
                <div className="min-w-0 flex-1">
                  <div className="text-sm font-bold">{LABELS[k]?.[0] ?? k}</div>
                  <div className="text-[11px] text-white/45">{LABELS[k]?.[1]}</div>
                </div>
                <button role="switch" aria-checked={mine.kinds.includes(k)} onClick={() => toggle(k)}
                        className="relative h-7 w-12 shrink-0 rounded-full transition-colors"
                        style={{ background: mine.kinds.includes(k) ? "#34c759" : "rgba(255,255,255,0.15)" }}>
                  <span className="absolute top-0.5 h-6 w-6 rounded-full bg-white transition-all"
                        style={{ left: mine.kinds.includes(k) ? 22 : 2 }} />
                </button>
              </li>
            ))}
          </ul>
          <div className="grid grid-cols-2 gap-2">
            <button onClick={() => postData<{ sent: number }>("desk/push/test", {}).then((r) => say(r.sent ? "Sent a test" : "Nothing sent")).catch((e) => say((e as Error).message))}
                    className="rounded-xl bg-white/[0.08] py-2 text-sm font-bold">Send a test</button>
            <button disabled={busy} onClick={turnOff} className="rounded-xl bg-white/[0.08] py-2 text-sm font-bold">Turn off here</button>
          </div>
        </>
      )}
      <p className="text-[11px] text-white/40">
        Only for this phone and your own account. The app already notifies you about nudges, hypes and friends&apos; miles.
      </p>
    </div>
  );
}
