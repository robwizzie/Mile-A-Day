import type { Metadata } from "next";
import { DeskTv } from "@/components/desk/desk-tv";

export const metadata: Metadata = {
  title: "Mile A Day Desk - TV mode",
  robots: { index: false },
};

export default function DeskTvPage() {
  return <DeskTv />;
}
