"use client";

import { useState } from "react";
import { AppStoreButton } from "./app-store-button";
import { LiveCommunityCount } from "./live-community-count";

const API_URL =
  process.env.NEXT_PUBLIC_API_URL || "https://mad.mindgoblin.tech";

/** The last panel: the same red as the top, the live community, one ask, and the Android waitlist. */
export function CtaSection() {
  const [email, setEmail] = useState("");
  const [status, setStatus] = useState<"idle" | "sending" | "done" | "error">(
    "idle",
  );

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email || status === "sending") return;
    setStatus("sending");
    try {
      const res = await fetch(`${API_URL}/public/android-waitlist`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email }),
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      setStatus("done");
      setEmail("");
    } catch {
      setStatus("error");
    }
  };

  return (
    <section
      id="download"
      className="relative scroll-mt-20 overflow-hidden px-6 py-24 text-white"
      style={{
        background: "linear-gradient(180deg, #ec3047 0%, #dc253b 100%)",
      }}
    >
      <div
        aria-hidden="true"
        className="pointer-events-none absolute bottom-[-10%] left-1/2 h-[120%] w-[60%] -translate-x-1/2 opacity-[0.08]"
        style={{
          background:
            "url(/images/app-store/flamey-silhouette.svg) no-repeat bottom center / contain",
        }}
      />
      <div className="relative mx-auto max-w-3xl text-center">
        <p data-reveal="" style={{ "--d": "0ms" } as React.CSSProperties} className="mb-6 text-[13px] font-semibold uppercase tracking-[0.18em] text-white/85">
          Join the movement
        </p>
        <div data-reveal="pop" style={{ "--d": "100ms" } as React.CSSProperties} className="mb-9 flex justify-center">
          <LiveCommunityCount />
        </div>
        <h2 data-reveal="" style={{ "--d": "180ms" } as React.CSSProperties} className="font-heading text-[clamp(48px,8vw,96px)] leading-[0.92]">
          Your streak
          <br />
          starts today.
        </h2>
        <p data-reveal="" style={{ "--d": "260ms" } as React.CSSProperties} className="mx-auto mt-6 max-w-lg text-[18px] leading-relaxed text-white/90">
          One mile. Every day. That&apos;s all it takes to build a habit that
          lasts a lifetime. Download Mile A Day free and never look back.
        </p>
        <div data-reveal="" style={{ "--d": "320ms" } as React.CSSProperties} className="mt-9 flex justify-center">
          <AppStoreButton place="cta" />
        </div>

        <div className="mx-auto mt-14 max-w-md">
          <p className="mb-3 text-[15px] text-white/85">
            On Android? We'll email you when it's ready.
          </p>
          {status === "done" ? (
            <p className="rounded-full bg-white/15 px-6 py-3 text-[15px] font-semibold">
              You're on the list. Thanks!
            </p>
          ) : (
            <>
              <form onSubmit={handleSubmit} className="flex gap-2">
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="you@email.com"
                  required
                  disabled={status === "sending"}
                  aria-label="Email for the Android waitlist"
                  className="min-w-0 flex-1 rounded-full border border-white/30 bg-white/10 px-5 py-3 text-[15px] text-white placeholder-white/60 outline-none focus:border-white disabled:opacity-60"
                />
                <button
                  type="submit"
                  data-track="android_waitlist"
                  disabled={status === "sending"}
                  className="whitespace-nowrap rounded-full bg-white px-5 py-3 text-[15px] font-semibold text-[#16090c] disabled:opacity-60"
                >
                  {status === "sending" ? "Adding…" : "Notify me"}
                </button>
              </form>
              {status === "error" && (
                <p className="mt-2 text-sm text-white">
                  That didn't go through. Try again in a minute?
                </p>
              )}
            </>
          )}
        </div>
      </div>
    </section>
  );
}
