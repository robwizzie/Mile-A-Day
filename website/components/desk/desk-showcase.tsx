"use client";

import { useState } from "react";
import { DeskBox } from "./desk-box";
import { useDeskFeed } from "@/lib/use-desk-feed";
import { MASCOT, STYLE } from "@/lib/desk-engine";

const API_URL = process.env.NEXT_PUBLIC_API_URL || "https://mad.mindgoblin.tech";

/** The styles a box shows with community numbers alone. */
const STYLES: { id: number; name: string; blurb: string }[] = [
  { id: STYLE.ARCADE, name: "Arcade", blurb: "The mascot runs, hops hurdles and grabs coins" },
  { id: STYLE.ODOMETER, name: "Odometer", blurb: "Every mile ever logged, on rolling wheels" },
  { id: STYLE.CLASSIC, name: "Classic", blurb: "Users, miles today and all time" },
  { id: STYLE.BIG, name: "Big", blurb: "One giant stat at a time" },
  { id: STYLE.CAMPFIRE, name: "Campfire", blurb: "A cozy fire with the mascot" },
  { id: STYLE.SPOTLIGHT, name: "Spotlight", blurb: "Stats slide by under the user count" },
  { id: STYLE.SHOWCASE, name: "Showcase", blurb: "Cycles every style, with a stat show" },
];

const FEATURES = [
  ["Your mile and streak", "See at a glance whether today's mile is done. Flamey gets nervous when it's late."],
  ["Friends out running", "Live distance when a friend is out on a run, and a party when they finish."],
  ["Nudges and hypes", "The moment someone nudges or hypes you in the app, your box shows it."],
  ["Doodles", "Draw a little picture on your phone and send it to a friend's box."],
  ["Your runs, replayed", "Each mile of your run drawn as a bar, with your fastest one in gold."],
];

const PRICES = ["79", "99", "129+"];

export function DeskShowcase() {
  const feed = useDeskFeed();
  const [style, setStyle] = useState<number>(STYLE.ARCADE);
  const [mascot, setMascot] = useState<number>(MASCOT.FLAMEY);
  const users = (() => {
    try {
      return feed ? (JSON.parse(feed).community?.total_users as number) : null;
    } catch {
      return null;
    }
  })();

  const nextStyle = () => {
    const i = STYLES.findIndex((s) => s.id === style);
    setStyle(STYLES[(i + 1) % STYLES.length].id);
  };

  return (
    <main className="relative min-h-screen overflow-x-hidden bg-[#0a0a0a] text-[#f5f5f5]">
      <section className="relative px-4 pb-10 pt-28 sm:px-6"
               style={{ background: "radial-gradient(ellipse 900px 520px at 50% 40%, rgba(199,37,84,0.14) 0%, transparent 70%)" }}>
        <div className="mx-auto max-w-5xl text-center">
          <span className="mb-4 inline-flex items-center gap-2 rounded-full bg-white/[0.06] px-3 py-1 text-xs font-semibold uppercase tracking-widest text-[#c72554]">
            <span className="h-1.5 w-1.5 rounded-full bg-[#3ddc84]" /> Live right now
          </span>
          <h1 className="font-heading text-[clamp(44px,8vw,92px)] leading-[0.95] tracking-[-1px]">
            YOUR STREAK,<br />ON YOUR <span className="text-[#c72554]">DESK</span>
          </h1>
          <p className="mx-auto mt-5 max-w-2xl text-base leading-relaxed text-[#a0a0a0] sm:text-lg">
            A little LED box that runs on real Mile A Day data. The one below is live: every number on it
            is real{users ? <> ({users.toLocaleString()} people and counting)</> : null}, and it throws a party the moment
            someone new joins.
          </p>
        </div>

        <div className="mx-auto mt-8 max-w-3xl">
          <DeskBox feed={feed} style={style} mascot={mascot} onNextStyle={nextStyle} />
          <p className="mt-1 text-center text-xs text-white/40">
            Just like the real one: tap it, or shake it side to side.
          </p>
        </div>

        <div className="mx-auto mt-6 flex max-w-3xl flex-col items-center gap-3">
          <div className="flex rounded-full bg-white/[0.06] p-1">
            {[["Flamey", MASCOT.FLAMEY], ["Runner", MASCOT.RUNNER]].map(([label, id]) => (
              <button key={label} onClick={() => setMascot(id as number)}
                      className="rounded-full px-5 py-2 text-sm font-bold transition-colors"
                      style={{ background: mascot === id ? "#c72554" : "transparent" }}>
                {label}
              </button>
            ))}
          </div>
          <div className="flex flex-wrap justify-center gap-2">
            {STYLES.map((s) => (
              <button key={s.id} onClick={() => setStyle(s.id)} title={s.blurb}
                      className="rounded-xl px-3.5 py-2 text-sm font-semibold transition-colors"
                      style={{ background: style === s.id ? "rgba(199,37,84,0.25)" : "rgba(255,255,255,0.05)",
                               boxShadow: style === s.id ? "inset 0 0 0 1.5px #c72554" : undefined }}>
                {s.name}
              </button>
            ))}
          </div>
          <p className="text-sm text-white/50">{STYLES.find((s) => s.id === style)?.blurb}</p>
          <a href="#want-one"
             className="mt-3 rounded-2xl bg-[#c72554] px-6 py-3 text-sm font-extrabold transition-transform hover:-translate-y-0.5">
            I want one ↓
          </a>
        </div>
      </section>

      <section className="px-6 py-14">
        <div className="mx-auto max-w-5xl">
          <h2 className="text-center font-heading text-[clamp(32px,5vw,56px)] leading-none">
            WITH YOUR OWN, IT&apos;S <span className="text-[#c72554]">ALL YOU</span>
          </h2>
          <p className="mx-auto mt-3 max-w-xl text-center text-[#a0a0a0]">
            Connected to your account, the box shows your day and your friends, not just the community.
          </p>
          <div className="mt-10 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {FEATURES.map(([title, body]) => (
              <div key={title} className="rounded-2xl border border-white/[0.06] bg-white/[0.03] p-5">
                <h3 className="text-base font-bold">{title}</h3>
                <p className="mt-1.5 text-sm leading-relaxed text-[#a0a0a0]">{body}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <InterestForm />

      <footer className="px-6 pb-16 text-center text-sm text-white/40">
        Running a booth or a coffee shop counter?{" "}
        <a href="/desk/tv" className="font-semibold text-white/70 underline-offset-4 hover:underline">Open TV mode</a>{" "}
        for a full-screen version.
        <div className="mt-4"><a href="/" className="hover:text-white/70">← mileaday.run</a></div>
      </footer>
    </main>
  );
}

function InterestForm() {
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [price, setPrice] = useState<string | null>(null);
  const [trap, setTrap] = useState("");
  const [status, setStatus] = useState<"idle" | "sending" | "done" | "error">("idle");
  const [error, setError] = useState("");

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (status === "sending") return;
    setStatus("sending");
    setError("");
    try {
      const res = await fetch(`${API_URL}/public/desk-interest`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name, email, price, website: trap }),
      });
      if (!res.ok) {
        const j = await res.json().catch(() => ({}));
        throw new Error(j.error || "Something went wrong");
      }
      setStatus("done");
    } catch (err) {
      setError((err as Error).message);
      setStatus("error");
    }
  };

  return (
    <section id="want-one" className="px-4 py-16 sm:px-6"
             style={{ background: "radial-gradient(ellipse 600px 400px at 50% 100%, rgba(199,37,84,0.10) 0%, transparent 70%)" }}>
      <div className="mx-auto max-w-xl rounded-3xl border border-white/[0.08] bg-[#121214] p-6 sm:p-8">
        {status === "done" ? (
          <div className="py-6 text-center">
            <div className="desk-pop mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-full bg-[#c72554] text-2xl font-black">✓</div>
            <h2 className="font-heading text-4xl">YOU&apos;RE ON THE LIST</h2>
            <p className="mt-2 text-[#a0a0a0]">Thanks{name.trim() ? `, ${name.trim().split(" ")[0]}` : ""}! We&apos;ll email you before anyone else when boxes are ready.</p>
          </div>
        ) : (
          <form onSubmit={submit} className="flex flex-col gap-4">
            <div className="text-center">
              <h2 className="font-heading text-[clamp(34px,5vw,48px)] leading-none">WANT ONE?</h2>
              <p className="mt-2 text-sm text-[#a0a0a0]">
                We&apos;re thinking about making a small batch. Tell us you&apos;d buy one and you&apos;ll hear first.
              </p>
            </div>
            <label className="flex flex-col gap-1.5 text-sm font-semibold">
              Name
              <input required maxLength={60} value={name} onChange={(e) => setName(e.target.value)} autoComplete="name"
                     className="rounded-xl border border-white/[0.08] bg-white/[0.04] px-4 py-3 text-base font-normal outline-none focus:border-[#c72554]" />
            </label>
            <label className="flex flex-col gap-1.5 text-sm font-semibold">
              Email
              <input required type="email" maxLength={254} value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="email"
                     className="rounded-xl border border-white/[0.08] bg-white/[0.04] px-4 py-3 text-base font-normal outline-none focus:border-[#c72554]" />
            </label>
            <fieldset className="flex flex-col gap-2">
              <legend className="mb-1.5 text-sm font-semibold">What would you pay? <span className="font-normal text-white/40">(optional)</span></legend>
              <div className="grid grid-cols-3 gap-2">
                {PRICES.map((p) => (
                  <button type="button" key={p} onClick={() => setPrice((cur) => (cur === p ? null : p))}
                          aria-pressed={price === p}
                          className="rounded-xl py-3 text-base font-bold transition-colors"
                          style={{ background: price === p ? "#c72554" : "rgba(255,255,255,0.05)" }}>
                    ${p}
                  </button>
                ))}
              </div>
            </fieldset>
            {/* a field people never see; bots fill it in */}
            <input tabIndex={-1} autoComplete="off" aria-hidden value={trap} onChange={(e) => setTrap(e.target.value)}
                   name="website" style={{ position: "absolute", left: "-10000px", width: 1, height: 1, opacity: 0 }} />
            <button type="submit" disabled={status === "sending"}
                    className="mt-1 rounded-2xl bg-[#c72554] py-3.5 text-base font-extrabold transition-transform hover:-translate-y-0.5 disabled:opacity-60">
              {status === "sending" ? "Saving…" : "I'd buy one"}
            </button>
            {status === "error" && <p className="text-center text-sm text-[#ff6b8b]">{error}</p>}
            <p className="text-center text-xs text-white/35">
              We only use your email to tell you about the desk box. No spam, ever.
            </p>
          </form>
        )}
      </div>
    </section>
  );
}
