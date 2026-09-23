"use client";

import { useEffect, useState } from "react";
import {
  Card,
  Chip,
  fmt,
  fmtDateTime,
  getData,
  Loading,
  relativeDay,
  Section,
  SERIES,
  StatCard,
  STACK_SECTIONS,
} from "./lib";
import { StackedDayBars } from "./charts";
import { useDrilldown } from "./Drilldown";

// ─── Types (mirror backend/src/services/diagnosticsService.ts) ──────

type Kind = "crash" | "hang" | "cpu_exception" | "disk_write_exception";

type Overview = {
  days: number;
  totals: {
    crashes: number;
    hangs: number;
    cpu_exceptions: number;
    disk_write_exceptions: number;
    users_affected: number;
    metrics_payloads: number;
  };
  daily: { date: string; crashes: number; hangs: number; other: number }[];
  by_version: {
    app_version: string | null;
    build: string | null;
    crashes: number;
    hangs: number;
    other: number;
    users: number;
    latest_at: string;
  }[];
  top_signatures: {
    signature: string;
    kind: Kind;
    summary: string | null;
    count: number;
    users: number;
    first_at: string;
    latest_at: string;
    app_versions: string[];
    example: {
      app_version: string | null;
      build: string | null;
      os_version: string | null;
      device_model: string | null;
      frames: string[];
      meta: Record<string, unknown>;
      truncated: boolean;
    } | null;
  }[];
};

// Three concurrent series at most (theme.ts): CPU and disk-write exceptions
// share the third rather than inventing a fourth colour.
const DAILY_SERIES = [
  { key: "crashes" as const, label: "Crashes", color: SERIES[0] },
  { key: "hangs" as const, label: "Hangs", color: SERIES[1] },
  { key: "other" as const, label: "CPU / disk", color: SERIES[2] },
];

const KIND_LABEL: Record<Kind, string> = {
  crash: "Crash",
  hang: "Hang",
  cpu_exception: "CPU",
  disk_write_exception: "Disk writes",
};

const versionLabel = (v: string | null, b: string | null) =>
  v ? `${v}${b ? ` (${b})` : ""}` : "unknown";

/** The metadata lines worth reading above a stack, in reading order. */
const META_ORDER = [
  "exceptionType",
  "exceptionCode",
  "signal",
  "terminationReason",
  "hangDuration",
  "totalCPUTime",
  "writesCaused",
  "virtualMemoryRegionInfo",
];

function ExampleStack({
  example,
}: {
  example: NonNullable<Overview["top_signatures"][number]["example"]>;
}) {
  const meta = example.meta ?? {};
  const reason = meta.exceptionReason as
    | { exceptionName?: string; composedMessage?: string }
    | undefined;
  return (
    <div className="mt-3 space-y-2">
      <p className="text-xs text-white/45">
        Latest: v{versionLabel(example.app_version, example.build)} ·{" "}
        {example.os_version ?? "OS unknown"} ·{" "}
        {example.device_model ?? "device unknown"}
      </p>
      <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-xs">
        {META_ORDER.filter((k) => meta[k] != null && meta[k] !== "").map(
          (k) => (
            <div key={k} className="contents">
              <dt className="text-white/40">{k}</dt>
              <dd className="min-w-0 break-words text-white/70">
                {String(meta[k])}
              </dd>
            </div>
          ),
        )}
        {reason?.exceptionName && (
          <div className="contents">
            <dt className="text-white/40">exception</dt>
            <dd className="min-w-0 break-words text-white/70">
              {reason.exceptionName}
              {reason.composedMessage ? ` — ${reason.composedMessage}` : ""}
            </dd>
          </div>
        )}
      </dl>
      {example.frames.length ? (
        <pre className="max-h-80 overflow-auto rounded-xl bg-black/40 p-3 text-[11px] leading-relaxed text-white/65">
          {example.frames.map((f, i) => `${String(i).padStart(2, " ")}  ${f}`).join("\n")}
        </pre>
      ) : (
        <p className="text-xs text-white/40">
          {example.truncated
            ? "Stack dropped: it didn't fit the size cap even when trimmed."
            : "No stack in this report."}
        </p>
      )}
      <p className="text-[11px] text-white/30">
        Frames are binary + offset, innermost first — symbolicate against the
        build&apos;s dSYM.
      </p>
    </div>
  );
}

export function DiagnosticsTab() {
  const [d, setD] = useState<Overview | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [open, setOpen] = useState<string | null>(null);
  const drill = useDrilldown();

  useEffect(() => {
    getData<Overview>("diagnostics")
      .then(setD)
      .catch((e) => {
        if (e?.message !== "unauthorized")
          setErr("Failed to load crash reports.");
      });
  }, []);

  if (err) return <p className="text-sm text-[#d94059]">{err}</p>;
  if (!d) return <Loading />;

  const t = d.totals;
  const hasAny = t.crashes + t.hangs + t.cpu_exceptions + t.disk_write_exceptions > 0;

  return (
    <div className={STACK_SECTIONS}>
      <Section
        title="Crashes & hangs"
        hint={`MetricKit reports from the iOS app, last ${d.days} days. iOS delivers a report on the next launch, up to a day after it happened, so today always reads low.`}
      >
        <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
          <StatCard label="Crashes" value={fmt(t.crashes)} accent={t.crashes > 0} />
          <StatCard label="Hangs" value={fmt(t.hangs)} />
          <StatCard
            label="CPU / disk"
            value={fmt(t.cpu_exceptions + t.disk_write_exceptions)}
            sub={`${fmt(t.cpu_exceptions)} CPU · ${fmt(t.disk_write_exceptions)} disk`}
          />
          <StatCard
            label="People affected"
            value={fmt(t.users_affected)}
            sub={`${fmt(t.metrics_payloads)} daily metric reports`}
          />
        </div>
        <Card>
          <StackedDayBars
            data={d.daily}
            series={DAILY_SERIES}
            label={`Reports by day received — last ${d.days} days`}
            hint="Dated by when the report reached us (UTC), not when the crash happened."
            windowDays={d.days}
            emptyText={`No reports in the last ${d.days} days.`}
          />
        </Card>
      </Section>

      <Section
        title="By app version"
        hint="A new build that crashes more than the one before it is the thing to catch."
      >
        <Card>
          {d.by_version.length === 0 ? (
            <p className="text-sm text-white/40">No reports in this window.</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-left text-sm">
                <thead className="text-xs whitespace-nowrap text-white/40">
                  <tr>
                    <th className="py-1 pr-3 font-medium">Version</th>
                    <th className="py-1 pr-3 text-right font-medium">Crashes</th>
                    <th className="py-1 pr-3 text-right font-medium">Hangs</th>
                    <th className="py-1 pr-3 text-right font-medium">CPU / disk</th>
                    <th className="py-1 pr-3 text-right font-medium">People</th>
                    <th className="py-1 font-medium">Latest</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-white/5">
                  {d.by_version.map((v) => (
                    <tr key={`${v.app_version}-${v.build}`}>
                      <td className="py-1.5 pr-3 whitespace-nowrap text-white/85">
                        {versionLabel(v.app_version, v.build)}
                      </td>
                      <td className="mad-num py-1.5 pr-3 text-right text-white/85">
                        {fmt(v.crashes)}
                      </td>
                      <td className="mad-num py-1.5 pr-3 text-right text-white/70">
                        {fmt(v.hangs)}
                      </td>
                      <td className="mad-num py-1.5 pr-3 text-right text-white/70">
                        {fmt(v.other)}
                      </td>
                      <td className="mad-num py-1.5 pr-3 text-right text-white/70">
                        {fmt(v.users)}
                      </td>
                      <td className="py-1.5 whitespace-nowrap text-white/50">
                        {relativeDay(v.latest_at)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      </Section>

      <Section
        title="Top signatures"
        hint="Grouped by exception + top frames. Same crash in a new build starts a new group, since offsets move. Open a row for its stack, or every occurrence."
      >
        {!hasAny ? (
          <Card>
            <p className="text-sm text-white/40">
              Nothing reported in the last {d.days} days.
            </p>
          </Card>
        ) : (
          <div className="space-y-3">
            {d.top_signatures.map((s) => {
              const isOpen = open === s.signature;
              return (
                <Card key={s.signature}>
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <button
                      onClick={() => setOpen(isOpen ? null : s.signature)}
                      className="min-w-0 flex-1 basis-72 text-left"
                      aria-expanded={isOpen}
                    >
                      <div className="flex flex-wrap items-center gap-2">
                        <Chip
                          text={KIND_LABEL[s.kind] ?? s.kind}
                          tone={s.kind === "crash" ? "bad" : "muted"}
                        />
                        <span className="min-w-0 break-words text-sm font-semibold text-white/90">
                          {s.summary ?? s.signature}
                        </span>
                      </div>
                      <p className="mt-1.5 text-xs text-white/45">
                        {fmt(s.users)} {s.users === 1 ? "person" : "people"} ·{" "}
                        {s.app_versions.length
                          ? `v${s.app_versions.join(", v")}`
                          : "version unknown"}{" "}
                        · first {fmtDateTime(s.first_at)} · latest{" "}
                        {fmtDateTime(s.latest_at)}
                      </p>
                    </button>
                    <div className="flex shrink-0 items-center gap-2">
                      <span className="mad-num text-[22px] leading-none font-extrabold text-white">
                        {fmt(s.count)}
                      </span>
                      <button
                        onClick={() =>
                          drill({ kind: "diagnostic_signature", id: s.signature })
                        }
                        className="rounded-full border border-white/[0.12] px-2.5 py-1 text-xs text-white/60 transition hover:border-white/25 hover:text-white"
                      >
                        Occurrences
                      </button>
                    </div>
                  </div>
                  {isOpen && s.example && <ExampleStack example={s.example} />}
                </Card>
              );
            })}
          </div>
        )}
      </Section>
    </div>
  );
}
