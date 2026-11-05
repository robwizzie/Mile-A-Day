import { cookies } from "next/headers";
import type { Metadata } from "next";
import { AdminLogin } from "../login";
import { SkinBuilder } from "./_components/SkinBuilder";

// The Skin Builder: every Flamey skin file drawn with the web renderer, and
// the flow that turns an SVG into a new skin file (docs/flamey-skins.md).
// Same gate as the dashboard: cookie presence shows the UI, the proxy
// (/admin/api/skins) carries the real auth.
export const metadata: Metadata = {
  title: "Skins",
  robots: { index: false, follow: false },
};

export default async function SkinsPage() {
  const authed = Boolean((await cookies()).get("mad_admin")?.value);
  return authed ? <SkinBuilder /> : <AdminLogin />;
}
