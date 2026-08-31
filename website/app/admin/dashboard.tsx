"use client";

import { useEffect, useState } from "react";
import { OverviewTab } from "./_components/Overview";
import { UsersTab } from "./_components/Users";
import { ContentTab } from "./_components/Content";
import { FeaturesTab } from "./_components/Features";
import { GrowthTab } from "./_components/Growth";
import { ErrorsTab } from "./_components/Errors";
import { DrilldownProvider } from "./_components/Drilldown";
import { APP_BACKGROUND, ROUNDED_STACK } from "./_components/theme";

const TABS = [
  { id: "overview", label: "Overview", render: () => <OverviewTab /> },
  { id: "users", label: "Users", render: () => <UsersTab /> },
  { id: "content", label: "Content", render: () => <ContentTab /> },
  { id: "features", label: "Features", render: () => <FeaturesTab /> },
  { id: "growth", label: "Growth", render: () => <GrowthTab /> },
  { id: "errors", label: "Errors", render: () => <ErrorsTab /> },
] as const;

type TabId = (typeof TABS)[number]["id"];

export function AdminDashboard() {
  const [tab, setTab] = useState<TabId>("overview");

  // Keep the active tab in the URL hash so a refresh (and the browser back
  // button) lands on the same view.
  useEffect(() => {
    const fromHash = window.location.hash.slice(1) as TabId;
    if (TABS.some((t) => t.id === fromHash)) setTab(fromHash);
  }, []);

  function select(id: TabId) {
    setTab(id);
    history.replaceState(null, "", `#${id}`);
  }

  async function logout() {
    await fetch("/admin/api/logout", { method: "POST" });
    window.location.reload();
  }

  const active = TABS.find((t) => t.id === tab) ?? TABS[0];

  return (
    <DrilldownProvider>
      {/* The app's own background gradient and rounded type, so the dashboard
          and the product read as one thing. `ui-rounded` resolves to real SF
          Rounded on Apple platforms; Nunito stands in elsewhere. */}
      <main
        className="min-h-screen text-white"
        style={{ background: APP_BACKGROUND, fontFamily: ROUNDED_STACK }}
      >
        <style>{`
          .mad-num { font-feature-settings: "tnum"; letter-spacing: -0.01em; }
          /* The tab row still scrolls on a narrow window; it just does not
             draw a bar across the header to say so. */
          .no-scrollbar { scrollbar-width: none; -ms-overflow-style: none; }
          .no-scrollbar::-webkit-scrollbar { display: none; }
        `}</style>

        <header className="sticky top-0 z-40 border-b border-white/[0.08] backdrop-blur-xl">
          {/* Its own translucent wash rather than the page gradient, which
              would band against the content scrolling under it. */}
          <div className="absolute inset-0 -z-10 bg-[#0a0a0a]/85" />
          <div className="mx-auto max-w-6xl px-5 sm:px-6">
            <div className="flex items-center justify-between py-4">
              {/* MADTabHeader: 26pt heavy rounded title. */}
              <h1 className="text-[26px] leading-none font-extrabold tracking-tight">
                Mile A Day{" "}
                <span className="text-white/35">Admin</span>
              </h1>
              <button
                onClick={logout}
                className="rounded-full border border-white/[0.12] px-3.5 py-1.5 text-sm text-white/55 transition hover:border-white/25 hover:text-white"
              >
                Sign out
              </button>
            </div>
            <nav className="no-scrollbar -mb-px flex gap-1 overflow-x-auto">
              {TABS.map((t) => (
                <button
                  key={t.id}
                  onClick={() => select(t.id)}
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
          </div>
        </header>

        <div className="mx-auto max-w-6xl px-5 py-8 sm:px-6">
          {active.render()}
        </div>
      </main>
    </DrilldownProvider>
  );
}
