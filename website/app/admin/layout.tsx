import { Nunito } from "next/font/google";
import type { Metadata } from "next";
import type { ReactNode } from "react";

// Added to the home screen from here, the admin panel opens on the desk
// remote as its own app (and can get web push: iOS needs that).
export const metadata: Metadata = {
  manifest: "/admin-desk.webmanifest",
  appleWebApp: { capable: true, title: "MAD Desk", statusBarStyle: "black" },
};

/**
 * The admin area is set in rounded type to match the app, every label of
 * which is `design: .rounded` (MADTheme.Typography). `ui-rounded` in the
 * dashboard's font stack resolves to real SF Rounded on Apple platforms —
 * where this is actually read — and this is the stand-in everywhere else.
 *
 * Scoped to /admin on purpose: the marketing site keeps DM Sans + Bebas Neue,
 * which are its own identity, and loading a third family site-wide to serve
 * one internal route would be a cost paid by every visitor.
 */
const nunito = Nunito({
  subsets: ["latin"],
  weight: ["400", "600", "700", "800"],
  variable: "--font-nunito",
  display: "swap",
});

export default function AdminLayout({ children }: { children: ReactNode }) {
  return <div className={nunito.variable}>{children}</div>;
}
