"use client";

import Script from "next/script";
import { useState } from "react";

// The Services ID registered in the Apple Developer portal (team NS237SS5KD).
// NOT a secret — Apple client IDs travel in every sign-in request by design,
// so a code default is safe and spares the hosting-dashboard env-var dance.
// An env var still wins when set (e.g. a staging Services ID).
const CLIENT_ID =
  process.env.NEXT_PUBLIC_APPLE_WEB_CLIENT_ID ||
  "org.robertwiscount.Mile-A-Day.web";
const REDIRECT_URI =
  process.env.NEXT_PUBLIC_APPLE_WEB_REDIRECT_URI ||
  "https://mileaday.run/admin";

declare global {
  interface Window {
    AppleID?: any;
  }
}

export function AdminLogin() {
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function signIn() {
    setError(null);
    setBusy(true);
    try {
      if (!CLIENT_ID) throw new Error("Apple web client ID not configured");
      if (!window.AppleID) throw new Error("Apple sign-in not loaded yet");

      window.AppleID.auth.init({
        clientId: CLIENT_ID,
        scope: "name email",
        redirectURI: REDIRECT_URI,
        usePopup: true,
      });

      const data = await window.AppleID.auth.signIn();
      const idToken = data?.authorization?.id_token;
      if (!idToken) throw new Error("No identity token from Apple");

      const res = await fetch("/admin/api/login", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ id_token: idToken }),
      });
      if (!res.ok) {
        const b = await res.json().catch(() => ({}));
        throw new Error(b.error ?? "Sign-in failed");
      }
      window.location.reload();
    } catch (e: any) {
      // Apple rejects with { error: 'popup_closed_by_user' } on cancel — not an error worth showing.
      if (e?.error === "popup_closed_by_user") return;
      setError(e?.message ?? "Sign-in failed");
    } finally {
      setBusy(false);
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
          <h1 className="mb-1 text-2xl font-semibold text-white">Admin</h1>
          <p className="mb-6 text-sm text-white/50">
            Mile A Day dashboard — authorized admins only.
          </p>
          <button
            onClick={signIn}
            disabled={busy}
            className="inline-flex w-full items-center justify-center gap-2 rounded-lg bg-white px-4 py-2.5 font-medium text-black transition hover:bg-white/90 disabled:opacity-50"
          >
            {busy ? "Signing in…" : "Sign in with Apple"}
          </button>
          {error && <p className="mt-4 text-sm text-[#c72554]">{error}</p>}
        </div>
      </main>
    </>
  );
}
