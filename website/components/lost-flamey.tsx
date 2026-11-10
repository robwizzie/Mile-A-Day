"use client";

import { useState } from "react";

/**
 * The 404's Flamey: the app's own sticker pack (Assets.xcassets/FlameyPack,
 * exported to public/images/flamey-pack/), one reaction per poke. He gets
 * more fed up each time, and the last one heads home.
 */
const REACTIONS = [
  {
    id: "what",
    line: "Flamey looked everywhere. This page isn't on the route.",
  },
  { id: "hmm", line: "Hmm. Maybe it was on yesterday's walk?" },
  { id: "side-eye", line: "Did you type that link yourself?" },
  { id: "bruh", line: "Still nothing. Bruh." },
  { id: "nooo", line: "He really wanted to find it for you." },
  { id: "this-is-fine", line: "This is fine. Your streak is fine too." },
  { id: "im-dead", line: "OK, that's enough poking." },
  { id: "omw", line: "He's heading home. Follow him?" },
];

export function LostFlamey() {
  const [i, setI] = useState(0);
  const [pokes, setPokes] = useState(0);
  const reaction = REACTIONS[i];

  const poke = () => {
    setI((n) => (n + 1) % REACTIONS.length);
    setPokes((n) => n + 1);
  };

  return (
    <div className="flex flex-col items-center">
      <button
        type="button"
        onClick={poke}
        aria-label="Poke Flamey"
        className="group relative h-[230px] w-[230px] cursor-pointer select-none sm:h-[280px] sm:w-[280px]"
      >
        {/* Shadow on the ground, so he stands somewhere */}
        <span className="absolute bottom-1 left-1/2 h-4 w-32 -translate-x-1/2 rounded-[50%] bg-black/25 blur-[2px]" />
        {/* key: each poke remounts the image, which replays the pop */}
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          key={reaction.id}
          src={`/images/flamey-pack/${reaction.id}.webp`}
          alt={`Flamey, reacting: ${reaction.id.replace(/-/g, " ")}`}
          width={420}
          height={420}
          draggable={false}
          className="flamey-pop absolute inset-0 m-auto h-full w-full object-contain drop-shadow-[0_18px_24px_rgba(0,0,0,0.25)] transition-transform duration-200 group-hover:-rotate-3 group-active:scale-95"
        />
      </button>

      <p
        key={`line-${reaction.id}`}
        aria-live="polite"
        className="mad-rise mt-4 min-h-[3.2em] max-w-sm text-center text-[18px] font-semibold leading-snug text-white"
      >
        {reaction.line}
      </p>
      <p className="mt-1 text-[13px] font-medium text-white/70">
        {pokes === 0
          ? "Tap Flamey."
          : `Poked ${pokes} ${pokes === 1 ? "time" : "times"}.`}
      </p>
    </div>
  );
}
