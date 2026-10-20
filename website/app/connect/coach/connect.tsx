"use client";

import Script from "next/script";
import { useState } from "react";
import { CLIENT_ID, REDIRECT_URI } from "../../admin/login";

/**
 * Sign-in step of the Claude coach connector (Run Plans). Same Apple sign-in
 * as the admin dashboard, plus the backend's one-time `nonce`, which Apple
 * stamps into the id_token so it is good for this one sign-in only. The token
 * goes back as a top-level SAME-ORIGIN form POST to /coach/oauth/apple/callback
 * (rewritten to the backend), so the browser sends the cookie set when this
 * sign-in started — the proof that the person signing in started it.
 */
export function ConnectCoach({
  request,
  nonce,
  client,
  to,
}: {
  request: string;
  nonce: string;
  client: string;
  to: string;
}) {
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const valid = /^[A-Za-z0-9_-]{20,100}$/.test(request) && /^[0-9a-f]{64}$/.test(nonce);

  async function connect() {
    setError(null);
    setBusy(true);
    try {
      if (!window.AppleID) throw new Error("Apple sign-in not loaded yet");
      window.AppleID.auth.init({
        clientId: CLIENT_ID,
        scope: "name email",
        redirectURI: REDIRECT_URI,
        nonce,
        usePopup: true,
      });
      const data = await window.AppleID.auth.signIn();
      const idToken = data?.authorization?.id_token;
      if (!idToken) throw new Error("No identity token from Apple");

      const form = document.createElement("form");
      form.method = "POST";
      form.action = "/coach/oauth/apple/callback";
      for (const [name, value] of [
        ["request", request],
        ["id_token", idToken],
      ]) {
        const input = document.createElement("input");
        input.type = "hidden";
        input.name = name;
        input.value = value;
        form.appendChild(input);
      }
      document.body.appendChild(form);
      form.submit();
    } catch (e: any) {
      setBusy(false);
      if (e?.error === "popup_closed_by_user") return;
      setError(e?.message ?? "Sign-in failed");
    }
  }

  return (
    <>
      <Script
        src="https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js"
        strategy="afterInteractive"
      />
      <main className="flex min-h-screen items-center justify-center bg-[#0a0a0a] px-5 py-10">
        <div className="w-full max-w-md rounded-2xl border border-white/10 bg-white/[0.03] p-6 sm:p-8">
          <h1 className="mb-1 text-center text-2xl font-semibold text-white">Connect Claude to your run plan</h1>
          {valid ? (
            <>
              <p className="mb-5 text-center text-sm text-white/60">
                <span className="text-white">{client || "Claude"}</span> is asking to coach you with your
                Mile A Day run plan.
              </p>

              <div className="mb-5 space-y-3 text-sm">
                <div>
                  <p className="mb-1 font-medium text-white">Claude will be able to see</p>
                  <ul className="list-disc space-y-0.5 pl-5 text-white/60">
                    <li>your run plan: goals, effort, and each day&apos;s workout</li>
                    <li>your runs: distance, pace, mile splits and moving time</li>
                    <li>your check-ins: how you said you felt, and any pain you flagged</li>
                  </ul>
                </div>
                <div>
                  <p className="mb-1 font-medium text-white">Claude will be able to</p>
                  <ul className="list-disc space-y-0.5 pl-5 text-white/60">
                    <li>
                      propose changes to your plan. You approve or decline each one in the app, unless you turn
                      on auto-apply for Claude in the app.
                    </li>
                  </ul>
                </div>
                <p className="text-white/60">
                  Claude can&apos;t see your friends, posts, photos, routes or account details, and can&apos;t
                  change anything outside your plan. Every change stays within your plan&apos;s safety limits.
                </p>
                <p className="text-white/60">
                  This needs <span className="text-white">Mile A Day+</span>. Disconnect any time in the app
                  under Run Plan → Connect Claude.
                </p>
              </div>

              <p className="mb-4 text-center text-xs text-white/40">
                Only continue if you just started this from Claude yourself. Use the Apple ID you use in the
                Mile A Day app. Sign-in returns to {to || "Claude"}.
              </p>
              <button
                onClick={connect}
                disabled={busy}
                className="inline-flex w-full items-center justify-center gap-2 rounded-lg bg-white px-4 py-2.5 font-medium text-black transition hover:bg-white/90 disabled:opacity-50"
              >
                {busy ? "Connecting…" : "Sign in with Apple to connect"}
              </button>
              {error && <p className="mt-4 text-center text-sm text-[#d94059]">{error}</p>}
            </>
          ) : (
            <p className="text-center text-sm text-white/60">
              This link is incomplete. Start the connection again from Claude, using the connector URL
              https://mileaday.run/mcp.
            </p>
          )}
        </div>
      </main>
    </>
  );
}
