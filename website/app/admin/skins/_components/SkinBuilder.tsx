"use client";

import { useEffect, useState } from "react";
import { APP_BACKGROUND, ROUNDED_STACK } from "../../_components/theme";
import { Chip, Loading } from "../../_components/lib";
import type { Skin } from "@/lib/flamey/compose";
import { Gallery } from "./Gallery";
import { SkinDetail } from "./SkinDetail";
import { NewSkin } from "./NewSkin";

type Payload = { version: string; format_max: number; skins: Skin[] };
type View = { kind: "gallery" } | { kind: "skin"; id: string } | { kind: "new" };

function readHash(): View {
  const h = decodeURIComponent(window.location.hash.slice(1));
  if (h === "new") return { kind: "new" };
  if (h.startsWith("skin/")) return { kind: "skin", id: h.slice(5) };
  return { kind: "gallery" };
}

export function go(hash: string) {
  window.location.hash = hash;
}

export function SkinBuilder() {
  const [data, setData] = useState<Payload | null>(null);
  const [source, setSource] = useState<string>("");
  const [error, setError] = useState<string | null>(null);
  const [view, setView] = useState<View>({ kind: "gallery" });

  useEffect(() => {
    setView(readHash());
    const on = () => {
      setView(readHash());
      window.scrollTo(0, 0);
    };
    window.addEventListener("hashchange", on);
    return () => window.removeEventListener("hashchange", on);
  }, []);

  useEffect(() => {
    (async () => {
      try {
        const res = await fetch("/admin/api/skins", { cache: "no-store" });
        if (res.status === 401 || res.status === 403) {
          await fetch("/admin/api/logout", { method: "POST" });
          window.location.reload();
          return;
        }
        if (!res.ok) throw new Error(`Request failed: ${res.status}`);
        setSource(res.headers.get("x-skins-source") || "backend");
        setData(await res.json());
      } catch (e) {
        setError(e instanceof Error ? e.message : String(e));
      }
    })();
  }, []);

  async function logout() {
    await fetch("/admin/api/logout", { method: "POST" });
    window.location.href = "/admin";
  }

  const skins = data?.skins ?? [];
  const current = view.kind === "skin" ? skins.find((s) => s.id === view.id) : undefined;

  return (
    <main className="min-h-screen text-white" style={{ background: APP_BACKGROUND, fontFamily: ROUNDED_STACK }}>
      <style>{`
        .mad-num { font-feature-settings: "tnum"; letter-spacing: -0.01em; }
        .no-scrollbar { scrollbar-width: none; -ms-overflow-style: none; }
        .no-scrollbar::-webkit-scrollbar { display: none; }
      `}</style>
      <header className="sticky top-0 z-40 border-b border-white/[0.08] backdrop-blur-xl">
        <div className="absolute inset-0 -z-10 bg-[#0a0a0a]/85" />
        <div className="mx-auto max-w-6xl px-5 sm:px-6">
          <div className="flex items-center justify-between py-4">
            <h1 className="text-[26px] leading-none font-extrabold tracking-tight">
              Mile A Day <span className="text-white/35">Admin</span>
            </h1>
            <button
              onClick={logout}
              className="rounded-full border border-white/[0.12] px-3.5 py-1.5 text-sm text-white/55 transition hover:border-white/25 hover:text-white"
            >
              Sign out
            </button>
          </div>
          <nav className="no-scrollbar -mb-px flex gap-1 overflow-x-auto">
            <a href="/admin" className="relative px-3 py-2.5 text-sm font-semibold whitespace-nowrap text-white/45 transition hover:text-white/80">
              Dashboard
            </a>
            {(
              [
                ["", "Skins", view.kind !== "new"],
                ["new", "New skin", view.kind === "new"],
              ] as const
            ).map(([hash, label, active]) => (
              <button
                key={label}
                onClick={() => go(hash)}
                className={`relative px-3 py-2.5 text-sm font-semibold whitespace-nowrap transition ${active ? "text-white" : "text-white/45 hover:text-white/80"}`}
              >
                {label}
                {active && (
                  <span
                    className="absolute inset-x-2 -bottom-px h-[2.5px] rounded-full"
                    style={{ background: "linear-gradient(90deg, #e64d66 0%, #b3334d 100%)" }}
                  />
                )}
              </button>
            ))}
          </nav>
        </div>
      </header>

      <div className="mx-auto max-w-6xl px-5 py-8 sm:px-6">
        {error && <p className="text-sm text-[#ffb3c6]">Couldn&apos;t load the skins: {error}</p>}
        {!data && !error && <Loading label="Loading skins…" />}
        {data && (
          <>
            <div className="mb-6 flex flex-wrap items-center gap-2 text-[12px] text-white/40">
              <span className="mad-num">{skins.length} skins</span>
              <span>·</span>
              <span>format {data.format_max}</span>
              <span>·</span>
              <span className="font-mono">version {data.version}</span>
              {source === "local" ? (
                <Chip text="Local files (dev fallback)" tone="info" />
              ) : (
                <Chip text="From the backend" tone="ok" />
              )}
            </div>
            {view.kind === "gallery" && <Gallery skins={skins} />}
            {view.kind === "skin" &&
              (current ? <SkinDetail skin={current} /> : <p className="text-sm text-white/50">No skin &quot;{view.id}&quot;.</p>)}
            {view.kind === "new" && <NewSkin existing={skins} />}
          </>
        )}
      </div>
    </main>
  );
}
