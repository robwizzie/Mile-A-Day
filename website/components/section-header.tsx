import type { ReactNode } from "react";

/**
 * The one heading style every home section uses, so the page reads as one
 * piece: a small tracked-caps eyebrow, a heavy sentence-case headline, one
 * plain line under it. `tone` follows the band it sits on.
 */
export function SectionHeader({
  eyebrow,
  title,
  body,
  align = "left",
  tone = "dark",
  className = "",
}: {
  eyebrow: ReactNode;
  title: ReactNode;
  body?: ReactNode;
  align?: "left" | "center";
  tone?: "dark" | "light";
  className?: string;
}) {
  const centered = align === "center";
  return (
    <div
      data-reveal=""
      className={`${centered ? "mx-auto text-center" : ""} max-w-3xl ${className}`}
    >
      <p
        className={`mb-4 inline-flex items-center gap-2 text-[13px] font-semibold uppercase tracking-[0.18em] ${
          tone === "light" ? "text-[#c72554]" : "text-[#ff5a6e]"
        }`}
      >
        {eyebrow}
      </p>
      <h2
        className={`font-heading text-[clamp(40px,5.5vw,72px)] leading-[0.95] ${
          tone === "light" ? "text-[#1d1214]" : "text-white"
        }`}
      >
        {title}
      </h2>
      {body && (
        <p
          className={`mt-5 text-[18px] leading-relaxed ${centered ? "mx-auto" : ""} max-w-xl ${
            tone === "light" ? "text-[#4a3a3d]" : "text-white/70"
          }`}
        >
          {body}
        </p>
      )}
    </div>
  );
}

/** The pulsing green dot that marks a number as live. */
export function LiveDot() {
  return (
    <span className="relative flex h-2.5 w-2.5">
      <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-[#33B34D] opacity-75" />
      <span className="relative inline-flex h-2.5 w-2.5 rounded-full bg-[#33B34D]" />
    </span>
  );
}
