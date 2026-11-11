import Image from "next/image";
import Link from "next/link";
import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { Apple } from "lucide-react";
import { Navbar } from "@/components/navbar";
import { Footer } from "@/components/footer";

import {
  getPublicPost,
  publicAuthorInitials,
  publicAuthorName,
  publicAvatarURL,
  publicStreak,
  type PublicPost,
} from "./publicPost";
import { ogVideos } from "../../_og/video/meta";

const APP_STORE_URL = "https://apps.apple.com/us/app/mile-a-day/id6746970905";

/**
 * Deliberately just the author (see publicPost.ts — shared with the OG
 * unfurl image so the two can't disagree). This page is a signpost, not a
 * viewer: it confirms the link is real, says whose post it is, and hands off
 * to the app — which re-checks whether the person tapping may actually see it.
 */
const getPost = getPublicPost;

function authorName(post: PublicPost): string {
  return publicAuthorName(post);
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ postId: string }>;
}): Promise<Metadata> {
  const { postId } = await params;
  const post = await getPost(postId);

  if (!post) {
    return { title: { absolute: "Mile A Day" }, robots: { index: false } };
  }

  const title = `${authorName(post)} on Mile A Day`;
  const description = `${authorName(post)} shared a post on Mile A Day. Open it in the app to see it.`;

  return {
    title: { absolute: title },
    description,
    // A post is friends-only; this page is a signpost to the app, not
    // content. Keep it out of search results (unfurlers ignore this, so
    // link previews are unaffected) while still letting crawlers follow
    // through to the author's public profile.
    robots: { index: false, follow: true },
    openGraph: {
      title,
      description,
      type: "article",
      siteName: "Mile A Day",
      // The animated card (og.mp4 beside this page); the PNG stays og:image.
      videos: ogVideos(`/p/${encodeURIComponent(post.post_id)}/og.mp4`),
    },
    // The co-located opengraph-image is 1200x630 and Next emits it for Twitter
    // too. `summary` rendered that as a small square thumbnail with most of the
    // card cropped away — the one shape it is not.
    twitter: { card: "summary_large_image", site: "@mileadayapp", title, description },
    // Smart App Banner: iOS Safari offers "Open in app", which is the fallback
    // when the universal link opens in the browser instead. app-argument
    // hands this exact post to the app, so the banner's OPEN lands on the
    // post instead of just launching the app.
    itunes: {
      appId: "6746970905",
      appArgument: `https://mileaday.run/p/${post.post_id}`,
    },
  };
}

export default async function PostPage({
  params,
}: {
  params: Promise<{ postId: string }>;
}) {
  const { postId } = await params;
  const post = await getPost(postId);

  if (!post) {
    notFound();
  }

  const name = authorName(post);
  const initials = publicAuthorInitials(post);
  const avatar = publicAvatarURL(post);
  const streak = publicStreak(post);

  return (
    <main className="relative min-h-screen overflow-x-hidden bg-[#0e0809]">
      <Navbar />

      <section className="relative flex items-center justify-center px-6 pb-20 pt-32">
        <div className="glass-card w-full max-w-md rounded-3xl p-10 text-center">
          {/* The real avatar, server-rendered: this page already knows it, so
              there is no initials-then-photo flash. Profile images are the one
              media path the backend leaves unsigned, precisely so world-readable
              share pages can show them. */}
          <div className="mx-auto flex h-28 w-28 items-center justify-center overflow-hidden rounded-full border-[3px] border-[#ec3047] bg-[#252525] font-heading text-4xl text-white">
            {avatar ? (
              <Image
                src={avatar}
                alt={name}
                width={112}
                height={112}
                className="h-full w-full object-cover"
              />
            ) : (
              initials
            )}
          </div>

          {streak !== null && (
            <div className="mt-4 inline-flex items-center rounded-full bg-[#ec3047] px-4 py-1.5 text-[13px] font-semibold text-white">
              {streak} day streak
            </div>
          )}

          <h1 className="mt-4 font-heading text-[32px] leading-tight text-white">
            {name} shared a post.
          </h1>
          <p className="mt-3 text-[15px] leading-relaxed text-[#a0a0a0]">
            Posts are shared with friends inside the app, so this page only says
            who posted it. Open it in Mile A Day to see it.
          </p>

          <div className="mt-9 space-y-3">
            <a
              href={`mileaday://p/${encodeURIComponent(post.post_id)}`}
              className="glass-button flex w-full items-center justify-center gap-2 rounded-full px-6 py-4 text-[16px] font-semibold text-white"
            >
              Open in Mile A Day
            </a>
            <a
              href={APP_STORE_URL} data-track="app_store:post"
              className="flex w-full items-center justify-center gap-2 rounded-full bg-white px-6 py-4 text-[16px] font-semibold text-[#16090c] transition-colors hover:bg-white/90"
            >
              <Apple className="h-5 w-5" aria-hidden />
              Get the app on the App Store
            </a>
            {post.username && (
              <p className="text-[13px] text-[#a0a0a0]/70">
                Or visit{" "}
                <Link
                  href={`/u/${post.username}`}
                  className="text-[#f5f5f5] underline"
                >
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
  );
}
