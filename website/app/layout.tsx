import type { Metadata, Viewport } from 'next'
import { Analytics } from '@vercel/analytics/next'
import './globals.css'

export const metadata: Metadata = {
  title: 'Mile A Day - Walk or Run a Mile Every Single Day',
  description: 'Build an unbreakable habit. Track your streak, compete with friends, and Go the Extra Mile. Available on iOS and Apple Watch.',
  keywords: ['mile a day', 'running app', 'walking app', 'fitness tracker', 'streak tracker', 'daily mile'],
  openGraph: {
    title: 'Mile A Day - Walk or Run a Mile Every Single Day',
    description: 'Build an unbreakable habit. Track your streak, compete with friends, and Go the Extra Mile.',
    type: 'website',
    siteName: 'Mile A Day',
    locale: 'en_US',
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Mile A Day - Walk or Run a Mile Every Single Day',
    description: 'Build an unbreakable habit. Track your streak, compete with friends, and Go the Extra Mile.',
  },
  metadataBase: new URL('https://mileaday.run'),
  icons: {
    icon: '/images/mad-circle-icon.png',
    apple: '/images/mad-circle-icon.png',
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
    <html lang="en">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        <link
          href="https://fonts.googleapis.com/css2?family=Bebas+Neue&family=DM+Sans:wght@400;500;600;700&display=swap"
          rel="stylesheet"
        />
      </head>
      <body className="font-sans antialiased bg-[#0a0a0a] text-[#f5f5f5]">
        {children}
        <Analytics />
      </body>
    </html>
  )
}
