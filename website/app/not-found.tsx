import Link from "next/link";
import Image from "next/image";
import { APP_STORE_URL } from "@/lib/site";

// Every unknown path — and /u/<name> or /p/<id> when the backend has no such
// profile or post — lands here instead of Next's default white 404.
export default function NotFound() {
  return (
    <main className="hero-gradient flex min-h-screen flex-col items-center justify-center px-6 text-center">
      <Image src="/images/mad-circle-icon.png" alt="Mile A Day" width={72} height={72} className="mb-6 rounded-full" />
      <p className="text-sm font-semibold uppercase tracking-widest text-[#c72554]">404</p>
      <h1 className="font-heading mt-2 text-[clamp(44px,8vw,80px)] leading-none text-[#f5f5f5]">
        WRONG TURN
      </h1>
      <p className="mt-4 max-w-sm text-base leading-relaxed text-[#a0a0a0]">
        This page doesn&apos;t exist, or the profile or post it pointed to is gone.
        Your streak is fine.
      </p>
      <div className="mt-8 flex flex-col items-center gap-3 sm:flex-row">
        <Link
          href="/"
          className="rounded-full border border-white/10 bg-white/[0.04] px-6 py-3 text-sm font-semibold text-[#f5f5f5] transition-colors hover:bg-white/[0.08]"
        >
          Back to Mile A Day
        </Link>
        <a
          href={APP_STORE_URL}
          className="rounded-full bg-[#c72554] px-6 py-3 text-sm font-semibold text-white transition-colors hover:bg-[#a81f47]"
        >
          Get the app
        </a>
      </div>
    </main>
  );
}
