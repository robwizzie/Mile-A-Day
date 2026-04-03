const items = [
  "START YOUR MILE",
  "BUILD YOUR STREAK",
  "GO THE EXTRA MILE",
  "NO EXCUSES",
  "COMPETE WITH FRIENDS",
  "GET MAD",
  "WALK IT OR RUN IT",
  "66 DAYS TO A HABIT",
]

function MarqueeItem({ text }: { text: string }) {
  return (
    <span className="flex items-center gap-4 px-10 whitespace-nowrap font-heading text-[17px] tracking-[3px] text-[#606060]">
      <span className="h-[5px] w-[5px] shrink-0 rounded-full bg-[#c72554]" />
      {text}
    </span>
  )
}

export function MarqueeSection() {
  return (
    <div className="relative overflow-hidden border-y border-[#333333]/40 bg-[#111111] py-5">
      {/* Gradient edge fades */}
      <div className="pointer-events-none absolute left-0 top-0 bottom-0 z-10 w-24 bg-gradient-to-r from-[#111111] to-transparent" />
      <div className="pointer-events-none absolute right-0 top-0 bottom-0 z-10 w-24 bg-gradient-to-l from-[#111111] to-transparent" />
      <div className="animate-marquee flex w-max">
        {items.map((item, i) => (
          <MarqueeItem key={i} text={item} />
        ))}
        {items.map((item, i) => (
          <MarqueeItem key={`dup-${i}`} text={item} />
        ))}
      </div>
    </div>
  )
}
