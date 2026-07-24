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

export const metadata: Metadata = {
  metadataBase: new URL('https://mileaday.run'),
  title: {
    default: 'Mile A Day - Walk or Run a Mile Every Single Day',
    template: '%s | Mile A Day',
  },
  description:
    'Mile A Day is the free iOS & Apple Watch app that turns one mile a day into an unbreakable habit. Track your streak, compete with friends, earn badges, and go the extra mile.',
  applicationName: 'Mile A Day',
  keywords: [
    'mile a day',
    'mile a day app',
    'run a mile a day',
    'walk a mile a day',
    'daily mile',
    'running app',
    'walking app',
    'fitness tracker',
    'streak tracker',
    'habit tracker',
    'apple watch running app',
    'run streak',
  ],
  authors: [{ name: 'Rob Wiscount' }, { name: 'David Simmerman' }],
  creator: 'Mile A Day',
  publisher: 'Mile A Day',
  category: 'health',
  alternates: {
    canonical: '/',
  },
  openGraph: {
    title: 'Mile A Day - Walk or Run a Mile Every Single Day',
    description: 'Build an unbreakable habit. Track your streak, compete with friends, and Go the Extra Mile.',
    url: '/',
    type: 'website',
    siteName: 'Mile A Day',
    locale: 'en_US',
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Mile A Day - Walk or Run a Mile Every Single Day',
    description: 'Build an unbreakable habit. Track your streak, compete with friends, and Go the Extra Mile.',
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
  icons: {
    icon: '/images/mad-circle-icon.png',
    apple: '/images/mad-circle-icon.png',
  },
  // Set NEXT_PUBLIC_GOOGLE_SITE_VERIFICATION in the Vercel project env to the
  // token from Search Console and the tag renders automatically. Omitted when unset.
  verification: {
    google: process.env.NEXT_PUBLIC_GOOGLE_SITE_VERIFICATION,
  },
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
