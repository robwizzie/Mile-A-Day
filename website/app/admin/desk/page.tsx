import { cookies } from "next/headers";
import type { Metadata, Viewport } from "next";
import { AdminLogin } from "../login";
import { DeskRemote } from "../_components/DeskRemote";

// The desk remote: a phone-first page for your own LED desk counter. Same
// sign-in as the admin dashboard (Sign in with Apple, admin accounts only);
// "Add to Home Screen" on an iPhone opens it full-screen like an app.
export const metadata: Metadata = {
  title: "My Desk — Mile A Day",
  robots: { index: false, follow: false },
  appleWebApp: { capable: true, title: "My Desk", statusBarStyle: "black-translucent" },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: "#000000",
};

export default async function DeskPage() {
  const authed = Boolean((await cookies()).get("mad_admin")?.value);
  return authed ? <DeskRemote /> : <AdminLogin />;
}
