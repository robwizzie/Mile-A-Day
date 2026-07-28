import Image from 'next/image'
import Link from 'next/link'
import type { Metadata } from 'next'
import { notFound } from 'next/navigation'
import { Apple } from 'lucide-react'
import { Footer } from '@/components/footer'

const API_URL = process.env.NEXT_PUBLIC_API_URL || 'https://mad.mindgoblin.tech'
const APP_STORE_URL = 'https://apps.apple.com/us/app/mile-a-day/id6746970905'

/**
 * Deliberately just the author. A post is friends-only content and a shared
 * link travels well past that audience, so this page is a signpost, not a
 * viewer: it confirms the link is real, says whose post it is, and hands off
 * to the app — which re-checks whether the person tapping may actually see it.
 */
type PublicPost = {
  post_id: string
  username: string | null
  first_name: string | null
}

async function getPost(postId: string): Promise<PublicPost | null> {
  try {
    const res = await fetch(`${API_URL}/public/posts/${encodeURIComponent(postId)}`, {
      next: { revalidate: 300 },
    })
    if (!res.ok) return null
    return res.json()
  } catch {
    return null
  }
}

function authorName(post: PublicPost): string {
  if (post.username) return `@${post.username}`
  if (post.first_name) return post.first_name
  return 'A runner'
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ postId: string }>
}): Promise<Metadata> {
  const { postId } = await params
  const post = await getPost(postId)

  if (!post) {
    return { title: 'Mile A Day' }
  }

  const title = `${authorName(post)} on Mile A Day`
  const description = `${authorName(post)} shared a post on Mile A Day. Open it in the app to see it.`

  return {
    title,
    description,
    openGraph: { title, description, type: 'article', siteName: 'Mile A Day' },
    twitter: { card: 'summary', title, description },
    // Smart App Banner: iOS Safari offers "Open in app", which is the fallback
    // when the universal link opens in the browser instead.
    itunes: { appId: '6746970905' },
  }
}

export default async function PostPage({
  params,
}: {
  params: Promise<{ postId: string }>
}) {
  const { postId } = await params
  const post = await getPost(postId)

  if (!post) {
    notFound()
  }

  const name = authorName(post)
  const initials = (post.username ?? post.first_name ?? 'M').slice(0, 2).toUpperCase()

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
          <div className="mx-auto flex h-28 w-28 items-center justify-center rounded-full border-2 border-[#c72554]/50 bg-[#252525] font-heading text-4xl tracking-[1px] text-[#f5f5f5]">
            {initials}
          </div>

          <h1 className="mt-6 font-heading text-[32px] leading-tight tracking-[0.5px] text-[#f5f5f5]">
            {name} shared a post
          </h1>
          <p className="mt-3 text-[15px] leading-relaxed text-[#a0a0a0]">
            Posts are shared with friends inside the app, so this page only says who
            posted it. Open it in Mile A Day to see the run.
          </p>

          <div className="mt-9 space-y-3">
            <a
              href={`mileaday://p/${encodeURIComponent(post.post_id)}`}
              className="glass-button flex w-full items-center justify-center gap-2 rounded-2xl bg-[#c72554] px-6 py-4 text-[16px] font-semibold text-white transition-transform hover:scale-[1.02]"
            >
              Open in Mile A Day
            </a>
            <a
              href={APP_STORE_URL}
              className="glass-button flex w-full items-center justify-center gap-2 rounded-2xl border border-[#c72554]/50 px-6 py-4 text-[16px] font-semibold text-[#f5f5f5] transition-transform hover:scale-[1.02]"
            >
              <Apple className="h-5 w-5" aria-hidden />
              Get the app on the App Store
            </a>
            {post.username && (
              <p className="text-[13px] text-[#a0a0a0]/70">
                Or visit{' '}
                <Link href={`/u/${post.username}`} className="text-[#f5f5f5] underline">
                  {name}
                </Link>
                {"'"}s profile.
              </p>
            )}
          </div>
        </div>
      </section>

      <Footer />
    </main>
  )
}
