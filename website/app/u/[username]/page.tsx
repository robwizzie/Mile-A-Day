import Image from 'next/image'
import Link from 'next/link'
import type { Metadata } from 'next'
import { notFound } from 'next/navigation'
import { Flame, Apple } from 'lucide-react'
import { Footer } from '@/components/footer'

const API_URL = process.env.NEXT_PUBLIC_API_URL || 'https://mad.mindgoblin.tech'
const APP_STORE_URL = 'https://apps.apple.com/us/app/mile-a-day/id6746970905'

type PublicProfile = {
  user_id: string
  username: string | null
  first_name: string | null
  last_name: string | null
  bio: string | null
  profile_image_url: string | null
  current_streak: number
}

function displayName(profile: PublicProfile): string {
  if (profile.first_name && profile.last_name) return `${profile.first_name} ${profile.last_name}`
  if (profile.first_name) return profile.first_name
  return profile.username ?? 'A runner'
}

async function getProfile(username: string): Promise<PublicProfile | null> {
  try {
    const res = await fetch(`${API_URL}/public/users/${encodeURIComponent(username)}`, {
      next: { revalidate: 300 },
    })
    if (!res.ok) return null
    return res.json()
  } catch {
    return null
  }
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ username: string }>
}): Promise<Metadata> {
  const { username } = await params
  const profile = await getProfile(username)

  if (!profile) {
    return { title: 'Mile A Day' }
  }

  const title = `@${profile.username} on Mile A Day`
  const description = `${displayName(profile)} is building a daily mile habit${
    profile.current_streak > 0 ? ` — ${profile.current_streak} day streak and counting` : ''
  }. Add them on Mile A Day and keep each other moving.`

  return {
    title,
    description,
    openGraph: { title, description, type: 'profile', siteName: 'Mile A Day' },
    twitter: { card: 'summary', title, description },
    // Smart App Banner: iOS Safari shows an "Open in app" banner, which is
    // the fallback path when the universal link opens in the browser.
    itunes: { appId: '6746970905' },
  }
}

export default async function ProfilePage({
  params,
}: {
  params: Promise<{ username: string }>
}) {
  const { username } = await params
  const profile = await getProfile(username)

  if (!profile) {
    notFound()
  }

  const name = displayName(profile)
  const imageSrc = profile.profile_image_url ? `${API_URL}${profile.profile_image_url}` : null
  const initials = name
    .split(' ')
    .map((part) => part[0])
    .slice(0, 2)
    .join('')
    .toUpperCase()

  return (
    <main className="relative min-h-screen overflow-x-hidden bg-[#0a0a0a]">
      <nav className="border-b border-[#333333]/40 py-5">
        <div className="mx-auto flex max-w-3xl items-center justify-between px-6">
          <Link href="/" className="flex items-center gap-3">
            <Image
              src="/images/mad-circle-icon.png"
              alt="Mile A Day logo"
              width={44}
              height={44}
              className="rounded-full"
            />
            <span className="font-heading text-[22px] tracking-[2px] text-[#f5f5f5]">MILE A DAY</span>
          </Link>
          <Link
            href="/"
            className="text-sm font-medium text-[#a0a0a0] tracking-wide transition-colors hover:text-[#f5f5f5]"
          >
            What is Mile A Day?
          </Link>
        </div>
      </nav>

      <section className="relative flex items-center justify-center px-6 py-20">
        <div className="glass-card w-full max-w-md rounded-3xl p-10 text-center">
          {imageSrc ? (
            <Image
              src={imageSrc}
              alt={`${name}'s profile photo`}
              width={112}
              height={112}
              className="mx-auto h-28 w-28 rounded-full border-2 border-[#c72554]/50 object-cover"
            />
          ) : (
            <div className="mx-auto flex h-28 w-28 items-center justify-center rounded-full border-2 border-[#c72554]/50 bg-[#252525] font-heading text-4xl tracking-[1px] text-[#f5f5f5]">
              {initials}
            </div>
          )}

          <h1 className="mt-6 font-heading text-[36px] leading-none tracking-[0.5px] text-[#f5f5f5]">
            {name}
          </h1>
          <p className="mt-1 text-[15px] font-medium text-[#a0a0a0]">@{profile.username}</p>

          {profile.current_streak > 0 && (
            <div className="mt-5 inline-flex items-center gap-2 rounded-full bg-[#c72554]/15 px-4 py-2">
              <Flame className="h-4 w-4 text-orange-400" aria-hidden />
              <span className="text-sm font-semibold text-[#f5f5f5]">
                {profile.current_streak} day streak
              </span>
            </div>
          )}

          {profile.bio && (
            <p className="mt-5 text-[15px] leading-relaxed text-[#a0a0a0]">{profile.bio}</p>
          )}

          <div className="mt-9 space-y-3">
            <a
              href={APP_STORE_URL}
              className="glass-button flex w-full items-center justify-center gap-2 rounded-2xl bg-[#c72554] px-6 py-4 text-[16px] font-semibold text-white transition-transform hover:scale-[1.02]"
            >
              <Apple className="h-5 w-5" aria-hidden />
              Add {profile.first_name ?? profile.username} on Mile A Day
            </a>
            <p className="text-[13px] text-[#a0a0a0]/70">
              Already have the app? Open this link on your iPhone and it&apos;ll take you straight
              to {profile.first_name ? `${profile.first_name}’s` : 'their'} profile.
            </p>
          </div>
        </div>
      </section>

      <Footer />
    </main>
  )
}
