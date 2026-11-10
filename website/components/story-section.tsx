"use client";

import Image from "next/image";
import { useEffect, useState } from "react";
import { SectionHeader } from "./section-header";

const API_URL =
  process.env.NEXT_PUBLIC_API_URL || "https://mad.mindgoblin.tech";

function getStreakDays(): number {
  const start = new Date(2025, 4, 13); // May 13, 2025
  const now = new Date();
  const diff = now.getTime() - start.getTime();
  return Math.floor(diff / (1000 * 60 * 60 * 24));
}

async function getProfileImageUrl(username: string): Promise<string | null> {
  try {
    const res = await fetch(`${API_URL}/public/profile-image/${username}`);
    if (!res.ok) return null;
    const data = await res.json();
    return data.profile_image_url
      ? `${API_URL}${data.profile_image_url}`
      : null;
  } catch {
    return null;
  }
}

export function StorySection() {
  const streakDays = getStreakDays();
  const [robImage, setRobImage] = useState<string | null>(null);
  const [daveImage, setDaveImage] = useState<string | null>(null);

  useEffect(() => {
    getProfileImageUrl("rob").then(setRobImage);
    getProfileImageUrl("dave").then(setDaveImage);
  }, []);

  return (
    <section
      id="story"
      className="scroll-mt-20 bg-[#f6f1ec] px-6 py-24 text-[#1d1214]"
    >
      <div className="mx-auto grid max-w-6xl items-center gap-12 lg:grid-cols-2 lg:gap-20">
        {/* Left column: narrative */}
        <div>
          <SectionHeader
            tone="light"
            eyebrow="Our story"
            title={
              <>
                It started with
                <br />a stupid bet.
              </>
            }
          />
          <p data-reveal="" style={{ "--d": "80ms" } as React.CSSProperties} className="mt-6 text-[17px] leading-[1.8] text-[#4a3a3d]">
            <span className="font-semibold text-[#1d1214]">Rob Wiscount</span>{" "}
            and{" "}
            <span className="font-semibold text-[#1d1214]">David Simmerman</span>{" "}
            made a simple challenge: walk or run one mile every single day.
            Whoever broke first had to buy the other a Call of Duty skin. That
            was it. No grand vision. No business plan. Just two competitive guys
            who refused to lose.
          </p>

          <blockquote data-reveal="" style={{ "--d": "140ms" } as React.CSSProperties} className="my-7 border-l-4 border-[#ec3047] pl-6">
            <p className="font-heading text-[20px] leading-[1.3] md:text-[24px]">
              &ldquo;We&apos;re over 500 days in without missing a single one.
              What started as a dumb CoD skin bet became the best habit either
              of us ever built, so we turned it into an app.&rdquo;
            </p>
          </blockquote>

          <p data-reveal="" style={{ "--d": "200ms" } as React.CSSProperties} className="text-[17px] leading-[1.8] text-[#4a3a3d]">
            Mile A Day isn&apos;t backed by venture capital. We&apos;re not in
            this for the money. We built this because this challenge genuinely
            changed our lives, and we think it can change yours too.
          </p>
        </div>

        {/* Right column: founders card */}
        <div data-reveal="" style={{ "--d": "150ms" } as React.CSSProperties} className="rounded-3xl bg-white p-7 md:p-10">
          <div className="mb-7 flex flex-col gap-5 sm:flex-row sm:gap-8">
            <Founder name="Rob Wiscount" image={robImage} />
            <Founder name="David Simmerman" image={daveImage} />
          </div>

          <h3 className="mb-4 font-heading text-[28px]">The CoD skin bet.</h3>
          <div className="space-y-3 text-[15px] leading-[1.8] text-[#4a3a3d]">
            <p>
              It was supposed to be a quick thing. &ldquo;Let&apos;s see who
              breaks first. Loser buys a Call of Duty skin.&rdquo; Days turned
              into weeks. Weeks turned into months. Neither of us would quit.
            </p>
            <p>
              We realized we&apos;d accidentally built the most consistent
              fitness habit of our lives. So we thought: what if everyone could
              feel this? The accountability. The streak you refuse to break. The
              friendly competition that makes you lace up on days you really
              don&apos;t want to.
            </p>
            <p>That&apos;s how Mile A Day was born.</p>
          </div>

          {/* Streak badge */}
          <div data-reveal="pop" style={{ "--d": "450ms" } as React.CSSProperties} className="mt-7 inline-flex items-center gap-2 rounded-full bg-[#ec3047] px-5 py-2.5 text-[15px] font-semibold text-white">
            <span aria-hidden="true">🔥</span> Founders&apos; streak:{" "}
            {streakDays.toLocaleString()} days and counting
          </div>
        </div>
      </div>
    </section>
  );
}

function Founder({ name, image }: { name: string; image: string | null }) {
  return (
    <div className="flex items-center gap-3">
      <div className="relative h-12 w-12 shrink-0 overflow-hidden rounded-full bg-[#ec3047]/15">
        {image && (
          <Image src={image} alt={name} fill className="object-cover" sizes="48px" />
        )}
      </div>
      <div>
        <div className="text-[15px] font-semibold">{name}</div>
        <div className="text-[13px] text-[#c72554]">Co-founder &amp; developer</div>
      </div>
    </div>
  );
}
