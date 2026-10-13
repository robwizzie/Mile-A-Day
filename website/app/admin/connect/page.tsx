import type { Metadata } from "next";
import { ConnectClaude } from "./connect";

export const metadata: Metadata = {
  title: "Connect Claude — Mile A Day",
  robots: { index: false, follow: false },
};

type Params = Record<string, string | string[] | undefined>;
const one = (v: string | string[] | undefined) => (typeof v === "string" ? v : "");

// The backend's /authorize sends the browser here (see backend/src/mcp). Not
// gated on the dashboard cookie: this page signs in on its own.
export default async function ConnectPage({ searchParams }: { searchParams: Promise<Params> }) {
  const p = await searchParams;
  return <ConnectClaude request={one(p.request)} nonce={one(p.nonce)} client={one(p.client)} to={one(p.to)} />;
}
