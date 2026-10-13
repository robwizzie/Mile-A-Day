import type { Metadata } from "next";
import { DeskShowcase } from "@/components/desk/desk-showcase";

export const metadata: Metadata = {
  title: { absolute: "Mile A Day Desk - your streak, live on your desk" },
  description:
    "A little LED box that runs on real Mile A Day data: your mile, your streak, friends out running, and a party for every new member. Watch it live.",
  alternates: { canonical: "/desk" },
  openGraph: {
    title: "Mile A Day Desk",
    description: "A live LED box for your desk, running on real Mile A Day data. Watch it live and tell us you'd buy one.",
    url: "/desk",
    type: "website",
    siteName: "Mile A Day",
  },
};

export default function DeskPage() {
  return (
    <>
      <header className="absolute left-0 right-0 top-0 z-10 px-6 py-5">
        <a href="/" className="mx-auto flex max-w-5xl items-center gap-3 text-sm font-bold text-white/80">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/images/mad-circle-icon.png" alt="" width={36} height={36} className="rounded-full" />
          Mile A Day
        </a>
      </header>
      <DeskShowcase />
    </>
  );
}
