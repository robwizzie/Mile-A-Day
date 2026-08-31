import { Nunito } from "next/font/google";
import type { ReactNode } from "react";

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
