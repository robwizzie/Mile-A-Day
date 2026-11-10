"use client";

import Image from "next/image";
import { useEffect, useState } from "react";

const API_URL =
  process.env.NEXT_PUBLIC_API_URL || "https://mad.mindgoblin.tech";

function getStreakDays(): number {
  const start = new Date(2025, 4, 13); // May 13, 2025
  return Math.floor((Date.now() - start.getTime()) / (1000 * 60 * 60 * 24));
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

function Founder({ name, image }: { name: string; image: string | null }) {
  return (
    <div className="flex items-center gap-3">
      <div className="relative h-12 w-12 shrink-0 overflow-hidden rounded-full bg-[#e9ded5]">
        {image && (
          <Image
            src={image}
            alt={name}
            fill
            className="object-cover"
            sizes="48px"
          />
        )}
      </div>
      <span className="text-[16px] font-semibold text-[#1d1214]">{name}</span>
    </div>
  );
}

/** Who made this, told plainly, on a quiet light page between the colour. */
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
      <div className="mx-auto max-w-3xl">
        <p className="mb-4 text-[13px] font-semibold uppercase tracking-[0.18em] text-[#c72554]">
          Our story
        </p>
        <h2 className="font-heading text-[clamp(40px,6vw,72px)] leading-[0.95]">
          It started with
          <br />a dumb bet.
        </h2>
        <div className="mt-8 space-y-5 text-[18px] leading-[1.7] text-[#3a2c2f]">
          <p>
            In May 2025, Rob and Dave bet each other they could walk or run a
            mile every single day. Whoever missed first bought the other a Call
            of Duty skin.
          </p>
          <p>
            Nobody has bought a skin yet. We're {streakDays.toLocaleString()}{" "}
            days in, and it turned into the most consistent thing either of us
            has ever done. A mile is small enough that there's no excuse, and a
            streak is big enough that you don't want to lose it.
          </p>
          <p>
            So we built the app we wanted for it: a streak you can see, friends
            who notice when you haven't gone yet, and a little flame who's very
            happy when you do. It's just the two of us, no investors, and we use
            it every day.
          </p>
        </div>
        <div className="mt-10 flex flex-wrap gap-x-8 gap-y-4">
          <Founder name="Rob Wiscount" image={robImage} />
          <Founder name="David Simmerman" image={daveImage} />
        </div>
      </div>
    </section>
  );
}
