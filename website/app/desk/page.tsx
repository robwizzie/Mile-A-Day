import type { Metadata } from "next";
import { DeskShowcase } from "@/components/desk/desk-showcase";
import { Navbar } from "@/components/navbar";
import { Footer } from "@/components/footer";
import { ogVideos } from "../_og/video/meta";

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
    videos: ogVideos("/desk/og.mp4"),
  },
};

export default function DeskPage() {
  return (
    <>
      <Navbar />
      <DeskShowcase />
      <Footer />
    </>
  );
}
