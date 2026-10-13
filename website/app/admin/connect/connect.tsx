"use client";

import Script from "next/script";
import { useState } from "react";
import { CLIENT_ID, REDIRECT_URI } from "../login";

const API_URL = process.env.NEXT_PUBLIC_API_URL || "https://mad.mindgoblin.tech";

/**
 * Sign-in step of the Claude database connector. Same Apple sign-in as the
 * dashboard, plus the backend's one-time `nonce`, which Apple stamps into the
 * id_token so it is good for this one sign-in only. The token then goes back
 * to the backend as a top-level form POST — not fetch — so the browser sends
 * the cookie the backend set when this sign-in started; that cookie is what
 * proves the person signing in is the one who started it.
 */
export function ConnectClaude({
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
      form.action = `${API_URL}/oauth/apple/callback`;
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
      <main className="flex min-h-screen items-center justify-center bg-[#0a0a0a] px-6">
        <div className="w-full max-w-sm rounded-2xl border border-white/10 bg-white/[0.03] p-8 text-center">
          <h1 className="mb-1 text-2xl font-semibold text-white">Connect Claude</h1>
          {valid ? (
            <>
              <p className="mb-4 text-sm text-white/60">
                <span className="text-white">{client || "Claude"}</span> is asking for read and write
                access to the Mile A Day production database.
              </p>
              <p className="mb-6 text-xs text-white/40">
                Only continue if you just started this from Claude yourself. Sign-in returns to{" "}
                {to || "Claude"}.
              </p>
              <button
                onClick={connect}
                disabled={busy}
                className="inline-flex w-full items-center justify-center gap-2 rounded-lg bg-white px-4 py-2.5 font-medium text-black transition hover:bg-white/90 disabled:opacity-50"
              >
                {busy ? "Connecting…" : "Sign in with Apple to connect"}
              </button>
              {error && <p className="mt-4 text-sm text-[#d94059]">{error}</p>}
            </>
          ) : (
            <p className="text-sm text-white/60">
              This link is incomplete. Start the connection again from Claude.
            </p>
          )}
        </div>
      </main>
    </>
  );
}
