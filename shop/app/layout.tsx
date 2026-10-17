import type { Metadata, Viewport } from "next";
import { DM_Sans, Bebas_Neue } from "next/font/google";
import { Analytics } from "@vercel/analytics/next";
import "./globals.css";
import { THEME_KEY } from "@/lib/theme";

const dmSans = DM_Sans({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
  variable: "--font-dm-sans",
  display: "swap",
});

const bebasNeue = Bebas_Neue({
  subsets: ["latin"],
  weight: "400",
  variable: "--font-bebas-neue",
  display: "swap",
});

const TITLE = "Mile A Day Shop: Go The Extra Mile";
const DESCRIPTION =
  "Official Mile A Day merch. The Go The Extra Mile hoodie is here, with tees, long sleeves, tanks and Flamey gear on the way.";

export const metadata: Metadata = {
  metadataBase: new URL("https://mileaday.shop"),
  title: { default: TITLE, template: "%s | Mile A Day Shop" },
  description: DESCRIPTION,
  applicationName: "Mile A Day Shop",
  alternates: { canonical: "/" },
  openGraph: {
    title: TITLE,
    description: DESCRIPTION,
    type: "website",
    siteName: "Mile A Day Shop",
    locale: "en_US",
  },
  twitter: {
    card: "summary_large_image",
    site: "@mileadayapp",
    title: TITLE,
    description: DESCRIPTION,
  },
  icons: { icon: "/mad-icon.png", apple: "/mad-icon.png" },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f1ede6" },
    { media: "(prefers-color-scheme: dark)", color: "#0d0c0c" },
  ],
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={`${dmSans.variable} ${bebasNeue.variable}`} suppressHydrationWarning>
      <head>
        {/* Apply a saved light/dark choice before first paint (no flash). No
            saved choice = follow the system, via the CSS media query. */}
        <script
          dangerouslySetInnerHTML={{
            __html: `try{var t=localStorage.getItem("${THEME_KEY}");if(t==="light"||t==="dark")document.documentElement.dataset.theme=t}catch(e){}`,
          }}
        />
      </head>
      <body className="font-sans antialiased">
        {children}
        <Analytics />
      </body>
    </html>
  );
}
