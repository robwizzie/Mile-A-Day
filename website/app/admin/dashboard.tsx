"use client";

import { useEffect, useState } from "react";
import { OverviewTab } from "./_components/Overview";
import { UsersTab } from "./_components/Users";
import { ContentTab } from "./_components/Content";
import { GrowthTab } from "./_components/Growth";
import { ErrorsTab } from "./_components/Errors";

const TABS = [
  { id: "overview", label: "Overview", render: () => <OverviewTab /> },
  { id: "users", label: "Users", render: () => <UsersTab /> },
  { id: "content", label: "Content", render: () => <ContentTab /> },
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
    <main className="min-h-screen bg-[#0a0a0a] text-white">
      {/* Sticky header with title + tab nav */}
      <header className="sticky top-0 z-40 border-b border-white/10 bg-[#0a0a0a]/90 backdrop-blur">
        <div className="mx-auto max-w-6xl px-4 sm:px-6">
          <div className="flex items-center justify-between py-4">
            <h1 className="text-lg font-semibold sm:text-xl">
              Mile A Day <span className="text-white/40">— Admin</span>
            </h1>
            <button
              onClick={logout}
              className="rounded-lg border border-white/10 px-3 py-1.5 text-sm text-white/60 hover:text-white"
            >
              Sign out
            </button>
          </div>
          <nav className="-mb-px flex gap-1 overflow-x-auto">
            {TABS.map((t) => (
              <button
                key={t.id}
                onClick={() => select(t.id)}
                className={`whitespace-nowrap border-b-2 px-3 py-2.5 text-sm font-medium transition ${
                  tab === t.id
                    ? "border-[#c72554] text-white"
                    : "border-transparent text-white/50 hover:text-white/80"
                }`}
              >
                {t.label}
              </button>
            ))}
          </nav>
        </div>
      </header>

      <div className="mx-auto max-w-6xl px-4 py-8 sm:px-6">
        {active.render()}
      </div>
    </main>
  );
}
