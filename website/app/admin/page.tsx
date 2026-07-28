import { cookies } from "next/headers";
import type { Metadata } from "next";
import { AdminLogin } from "./login";
import { AdminDashboard } from "./dashboard";

export const metadata: Metadata = {
  title: "Admin",
  robots: { index: false, follow: false },
};

// Cookie presence gates the UI; the proxy endpoints enforce real auth
// (backend requireAdmin). If the token is stale, the dashboard's fetches get
// 401/403 and it bounces back to the login screen.
export default async function AdminPage() {
  const authed = Boolean((await cookies()).get("mad_admin")?.value);
  return authed ? <AdminDashboard /> : <AdminLogin />;
}
