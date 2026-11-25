"use client";

import { useCallback, useEffect, useState } from "react";
import { getData, postData } from "@/app/admin/_components/lib";

/**
 * Laundry in the desk remote: your washer and dryer (a Shelly smart plug
 * under each), what they're doing, and setting up the plugs. Your own
 * machines only; the plug key is shown once, inside the script to paste.
 */

type Machine = "washer" | "dryer";
type View = {
  machine: Machine;
  stage: string;
  minutes: number;
  left: number | null;
  sure: boolean;
  took: number | null;
  learned: number;
  plug_off: boolean;
};
type Plug = { id: string; machine: Machine; key_prefix: string; created_at: string; last_seen_at: string | null };
type Info = {
  status: { washer: View | null; dryer: View | null } | null;
  plugs: Plug[];
  loads: { machine: Machine; started_at: string; ended_at: string; seconds: number }[];
};

const STAGE: Record<string, string> = {
  fill: "Filling", wash: "Washing", rinse: "Rinsing", drain: "Draining", spin: "Spinning",
  dry: "Drying", cool: "Cooling down", tumble: "Tumbling", done: "Done", idle: "Free", offline: "Plug offline",
};
const ICON: Record<Machine, string> = { washer: "🫧", dryer: "🌀" };
const NAME: Record<Machine, string> = { washer: "Washer", dryer: "Dryer" };

function line(v: View): string {
  if (v.plug_off) return "The plug is switched off: the machine has no power";
  if (v.stage === "offline") return "No readings for 15 min: is the plug on Wi-Fi?";
  if (v.stage === "done") return `Finished ${v.minutes} min ago${v.took ? ` · took ${v.took} min` : ""}`;
  if (v.stage === "idle") return "Nothing running";
  const left = v.left == null ? "" : v.sure ? ` · ${v.left} min left` : ` · about ${v.left} min left`;
  return `${v.minutes} min in${left}`;
}

function clock(iso: string) {
  return new Date(iso).toLocaleString([], { weekday: "short", hour: "numeric", minute: "2-digit" });
}

type SectionLike = (p: { title: string; children: React.ReactNode; right?: React.ReactNode }) => React.ReactNode;

export function LaundrySection({ say, Section }: { say: (m: string) => void; Section: SectionLike }) {
  const [info, setInfo] = useState<Info | null>(null);
  const [busy, setBusy] = useState(false);
  const [setup, setSetup] = useState<{ machine: Machine; script: string } | null>(null);
  const [open, setOpen] = useState(false);

  const refresh = useCallback(async () => {
    setInfo(await getData<Info>("desk/laundry").catch(() => null));
  }, []);
  useEffect(() => {
    refresh();
    const id = setInterval(refresh, 15000);
    return () => clearInterval(id);
  }, [refresh]);

  async function addPlug(machine: Machine) {
    const has = info?.plugs.some((p) => p.machine === machine);
    if (has && !confirm(`Replace the ${machine} plug? The old one stops working (what it learned is kept).`)) return;
    setBusy(true);
    try {
      const r = await postData<{ key: string; report_url: string }>(`desk/laundry/plug?machine=${machine}`);
      const src = await (await fetch("/desk/laundry/mad-laundry.js", { cache: "no-store" })).text();
      const script = src
        .replace("PASTE_KEY_HERE", r.key)
        .replace("https://mad.mindgoblin.tech/laundry/report", r.report_url);
      setSetup({ machine, script });
      await refresh();
    } catch (e) {
      say((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  async function removePlug(p: Plug) {
    if (!confirm(`Remove the ${p.machine} plug? It stops reporting right away.`)) return;
    setBusy(true);
    try {
      await postData(`desk/laundry/plug/${p.id}/revoke`);
      say(`${NAME[p.machine]} plug removed`);
      await refresh();
    } catch (e) {
      say((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  async function emptied(m: Machine) {
    setBusy(true);
    try {
      await postData(`desk/laundry/${m}/emptied`);
      say(`${NAME[m]} marked empty`);
      await refresh();
    } catch (e) {
      say((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  async function copy() {
    if (!setup) return;
    try {
      await navigator.clipboard.writeText(setup.script);
      say("Script copied");
    } catch {
      say("Couldn't copy: select the text and copy it");
    }
  }

  if (!info) return null;
  const machines: Machine[] = ["washer", "dryer"];

  return (
    <Section title="Laundry" right={<span className="text-[11px] text-white/40">washer · dryer</span>}>
      {info.status && (
        <div className="grid grid-cols-2 gap-2">
          {machines.map((m) => {
            const v = info.status?.[m];
            if (!v) return (
              <div key={m} className="rounded-xl bg-white/[0.04] p-3 text-sm text-white/40">
                {ICON[m]} {NAME[m]}: no plug yet
              </div>
            );
            const running = !["idle", "done", "offline"].includes(v.stage);
            return (
              <div key={m} className="rounded-xl p-3"
                   style={{ background: v.stage === "done" ? "rgba(52,199,89,0.15)" : running ? "rgba(255,255,255,0.08)" : "rgba(255,255,255,0.04)" }}>
                <div className="text-[11px] font-bold uppercase tracking-wide text-white/50">{ICON[m]} {NAME[m]}</div>
                <div className="text-lg font-extrabold">{v.plug_off ? "Plug off" : STAGE[v.stage] ?? v.stage}</div>
                <div className="text-[12px] leading-snug text-white/60">{line(v)}</div>
                {v.stage === "done" && (
                  <button disabled={busy} onClick={() => emptied(m)}
                          className="mt-2 w-full rounded-lg bg-white/[0.1] py-1.5 text-xs font-bold">
                    I emptied it
                  </button>
                )}
                {v.learned < 3 && v.stage !== "offline" && (
                  <div className="mt-1 text-[10px] text-white/35">Learning your machine: times get better after a few loads</div>
                )}
              </div>
            );
          })}
        </div>
      )}

      {!info.status && !setup && (
        <p className="text-sm text-white/60">
          Put a Shelly Plug US Gen4 between the washer (or dryer) and the wall, and your desk shows when it&apos;s running,
          about how long is left, and when it&apos;s done. Your phone gets a ping when a load finishes.
        </p>
      )}

      {setup && (
        <div className="mt-3 rounded-xl bg-white/[0.06] p-3">
          <div className="text-sm font-extrabold">Set up the {setup.machine} plug</div>
          <p className="mt-1 text-[11px] text-white/50">
            This script holds the plug&apos;s key and is shown only now. If you lose it, just make a new one.
          </p>
          <ol className="mt-2 list-decimal space-y-1.5 pl-5 text-[13px] text-white/75">
            <li>Plug the Shelly into the wall and the {setup.machine} into the Shelly. Add it to your 2.4 GHz Wi-Fi with the Shelly app.</li>
            <li>In the Shelly app: <b>Settings → Power on default → On</b>, so the {setup.machine} always has power after an outage.</li>
            <li>Open the plug&apos;s web page (its IP address from the Shelly app, on your home Wi-Fi) → <b>Scripts → Create script</b>.</li>
            <li>Paste the script below, <b>Save</b>, turn on <b>Run on startup</b>, then <b>Start</b>.</li>
            <li>Done. Within a minute the {setup.machine} shows up here as Free.</li>
          </ol>
          <button onClick={copy} className="mt-3 w-full rounded-xl bg-white/[0.12] py-2 text-sm font-extrabold">Copy the script</button>
          <textarea readOnly value={setup.script} rows={6}
                    className="mt-2 w-full rounded-lg bg-black/40 p-2 font-mono text-[10px] text-white/70"
                    onFocus={(e) => e.currentTarget.select()} />
          <button onClick={() => setSetup(null)} className="mt-2 w-full rounded-xl bg-white/[0.06] py-2 text-sm font-bold">I&apos;ve pasted it</button>
        </div>
      )}

      <button onClick={() => setOpen((o) => !o)} className="mt-3 w-full rounded-xl bg-white/[0.06] py-2 text-sm font-bold">
        {open ? "Hide plugs and history" : info.plugs.length ? "Plugs and history" : "Set up a plug"}
      </button>
      {open && (
        <div className="mt-2 space-y-2">
          {machines.map((m) => {
            const p = info.plugs.find((x) => x.machine === m);
            return (
              <div key={m} className="flex items-center gap-2 rounded-xl bg-white/[0.04] p-2.5 text-sm">
                <div className="min-w-0 flex-1">
                  <div className="font-bold">{ICON[m]} {NAME[m]}</div>
                  <div className="text-[11px] text-white/45">
                    {p ? `Plug ${p.key_prefix}… · ${p.last_seen_at ? `last heard ${clock(p.last_seen_at)}` : "not heard from yet"}` : "No plug"}
                  </div>
                </div>
                <button disabled={busy} onClick={() => addPlug(m)} className="rounded-lg bg-white/[0.1] px-2.5 py-1.5 text-xs font-bold">
                  {p ? "Replace" : "Set up"}
                </button>
                {p && (
                  <button disabled={busy} onClick={() => removePlug(p)} className="rounded-lg bg-white/[0.06] px-2.5 py-1.5 text-xs font-bold text-white/60">
                    Remove
                  </button>
                )}
              </div>
            );
          })}
          {info.loads.length > 0 && (
            <ul className="space-y-1 pt-1 text-[12px] text-white/60">
              {info.loads.map((l) => (
                <li key={l.ended_at + l.machine} className="flex justify-between">
                  <span>{ICON[l.machine]} {NAME[l.machine]} · {Math.round(l.seconds / 60)} min</span>
                  <span className="text-white/40">{clock(l.ended_at)}</span>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </Section>
  );
}
