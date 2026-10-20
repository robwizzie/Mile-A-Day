import type { Metadata } from "next";
import { ConnectCoach } from "./connect";

export const metadata: Metadata = {
  title: "Connect Claude to your run plan — Mile A Day",
  robots: { index: false, follow: false },
};

type Params = Record<string, string | string[] | undefined>;
const one = (v: string | string[] | undefined) => (typeof v === "string" ? v : "");

// The coach connector's /authorize (backend/src/coachMcp, reached through this
// site's /authorize rewrite) sends the browser here with a one-time request id
// and nonce. Headers for /connect/* (frame-ancestors 'none') are in
// next.config.mjs.
export default async function ConnectCoachPage({ searchParams }: { searchParams: Promise<Params> }) {
  const p = await searchParams;
  return <ConnectCoach request={one(p.request)} nonce={one(p.nonce)} client={one(p.client)} to={one(p.to)} />;
}
