import Image from "next/image";

type Reward = { days: number; name: string; item_id: string | null; rarity?: string };

/** Rendered from the app's own Flamey art, so the site shows the real thing. */
const ART: Record<string, string> = {
  coast_compass: "/images/rewards/coast_compass.png",
  trail_cap: "/images/rewards/trail_cap.png",
  trailblazer: "/images/rewards/trailblazer.png",
  horizon_wings: "/images/rewards/horizon_wings.png",
};

const RARITY: Record<string, { label: string; colour: string }> = {
  rare: { label: "Rare", colour: "#5cbcff" },
  epic: { label: "Epic", colour: "#b885ff" },
  legendary: { label: "Legendary", colour: "#ffb833" },
  mythic: { label: "Mythic", colour: "#ff5c9e" },
};

export function GoalRewards({ rewards }: { rewards: Reward[] }) {
  const hasSet = rewards.some((r) => r.item_id && ART[r.item_id]);
  return (
    <div className="flex flex-col gap-3">
      {hasSet && (
        <Image
          src="/images/rewards/collection.png"
          alt="Flamey wearing the full collection: wings, explorer hat and compass pendant, at sunset"
          width={1920}
          height={1140}
          sizes="(max-width: 672px) 100vw, 624px"
          className="h-auto w-full rounded-2xl"
        />
      )}
      <ul className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {rewards.map((reward) => {
          const art = reward.item_id ? ART[reward.item_id] : undefined;
          const rarity = RARITY[reward.rarity ?? "rare"] ?? RARITY.rare;
          return (
            <li
              key={reward.days}
              className="flex flex-col items-center gap-1 rounded-xl border p-3 text-center"
              style={{ borderColor: `${rarity.colour}66`, backgroundColor: `${rarity.colour}1a` }}
            >
              <div className="flex h-24 w-24 items-center justify-center" aria-hidden="true">
                {art ? <Image src={art} alt="" width={96} height={96} /> : <span className="text-5xl">🏅</span>}
              </div>
              <p className="text-xs font-extrabold uppercase tracking-wide" style={{ color: rarity.colour }}>
                {rarity.label}
              </p>
              <p className="font-bold leading-tight text-white">{reward.name}</p>
              <p className="text-sm text-[#a0a0a0]">Walk {reward.days} days</p>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
