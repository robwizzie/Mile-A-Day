import type { CSSProperties } from "react";
import type { Release } from "@/lib/releases";

// Shared by the home page's What's New (client) and /updates (server), so
// it carries no "use client": the icons are components and can't cross
// from a server page into a client one as props.
/** A release's features as the app's What's New sheet lists them: its icon in its colour, title, line. */
export function ReleaseFeatureList({
  features,
  columns = 2,
}: {
  features: Release["features"];
  columns?: 1 | 2;
}) {
  return (
    <ul
      className={`grid gap-x-10 gap-y-7 ${columns === 2 ? "sm:grid-cols-2" : ""}`}
    >
      {features.map((item, i) => (
        <li
          key={item.title}
          data-reveal=""
          style={{ "--d": `${Math.min(i, 8) * 60}ms` } as CSSProperties}
          className="flex min-w-0 gap-4"
        >
          <item.icon
            className="mt-0.5 h-6 w-6 shrink-0"
            style={{ color: item.color }}
            aria-hidden
          />
          <div className="min-w-0">
            <p className="text-[17px] font-semibold text-white">{item.title}</p>
            <p className="mt-1 text-[15px] leading-relaxed text-white/65">
              {item.desc}
            </p>
          </div>
        </li>
      ))}
    </ul>
  );
}

