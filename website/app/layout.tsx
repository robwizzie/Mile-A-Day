import type { Metadata, Viewport } from 'next'
import { DM_Sans, Bebas_Neue } from 'next/font/google'
import { Analytics } from '@vercel/analytics/next'
import './globals.css'

const dmSans = DM_Sans({
  subsets: ['latin'],
  weight: ['400', '500', '600', '700'],
  variable: '--font-dm-sans',
  display: 'swap',
})

const bebasNeue = Bebas_Neue({
  subsets: ['latin'],
  weight: '400',
  variable: '--font-bebas-neue',
  display: 'swap',
})

const DESCRIPTION =
  // ≤160 characters, so search results show all of it.
  'The free iPhone & Apple Watch app that turns one mile a day into an unbreakable habit. Build your streak, compete with friends, and earn medals.'
const SOCIAL_DESCRIPTION =
  'Build an unbreakable habit. Track your streak, compete with friends, and Go the Extra Mile.'

export const metadata: Metadata = {
  metadataBase: new URL('https://mileaday.run'),
  title: {
    default: 'Mile A Day - Walk or Run a Mile Every Single Day',
    // Child pages set a short title ("Privacy Policy") and get the suffix.
    template: '%s | Mile A Day',
  },
  description: DESCRIPTION,
  applicationName: 'Mile A Day',
  keywords: [
    'mile a day',
    'mile a day app',
    'run a mile a day',
    'walk a mile a day',
    'daily mile',
    'run streak',
    'walking streak',
    'running app',
    'walking app',
    'habit tracker',
    'streak tracker',
    'apple watch running app',
  ],
  authors: [{ name: 'Rob Wiscount' }, { name: 'David Simmerman' }],
  creator: 'Mile A Day',
  publisher: 'Mile A Day',
  category: 'health',
  // Per-page: the home page only. A canonical here would be inherited by
  // every route that doesn't set its own and point them all at "/".
  openGraph: {
    title: 'Mile A Day - Walk or Run a Mile Every Single Day',
    description: SOCIAL_DESCRIPTION,
    type: 'website',
    siteName: 'Mile A Day',
    locale: 'en_US',
  },
  twitter: {
    card: 'summary_large_image',
    site: '@mileadayapp',
    creator: '@mileadayapp',
    title: 'Mile A Day - Walk or Run a Mile Every Single Day',
    description: SOCIAL_DESCRIPTION,
  },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      'max-image-preview': 'large',
      'max-snippet': -1,
      'max-video-preview': -1,
    },
  },
  appleWebApp: { title: 'Mile A Day', statusBarStyle: 'black-translucent' },
  formatDetection: { telephone: false, email: false, address: false },
  icons: {
    icon: '/images/mad-circle-icon.png',
    apple: '/images/mad-circle-icon.png',
  },
  // Set NEXT_PUBLIC_GOOGLE_SITE_VERIFICATION in the Vercel project env to the
  // Search Console token and the tag renders; omitted while unset.
  ...(process.env.NEXT_PUBLIC_GOOGLE_SITE_VERIFICATION
    ? { verification: { google: process.env.NEXT_PUBLIC_GOOGLE_SITE_VERIFICATION } }
    : {}),
}

export const viewport: Viewport = {
  themeColor: '#0a0a0a',
  width: 'device-width',
  initialScale: 1,
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    <html lang="en" className={`${dmSans.variable} ${bebasNeue.variable}`}>
      <body className="font-sans antialiased bg-[#0a0a0a] text-[#f5f5f5]">
        {children}
        <Analytics />
      </body>
    </html>
  )
}
