import Image from "next/image"

export function Footer() {
  return (
    <footer className="border-t border-[#333333]/40 px-6 py-14">
      <div className="mx-auto max-w-6xl">
        <div className="flex flex-col items-center gap-8 md:flex-row md:justify-between">
          <div className="flex items-center gap-3">
            <Image
              src="/images/mad-circle-icon.png"
              alt="Mile A Day logo"
              width={36}
              height={36}
              className="rounded-full"
            />
            <span className="font-heading text-[22px] tracking-[1px] text-[#f5f5f5]">MILE A DAY</span>
          </div>

          <div className="flex items-center gap-6">
            <a href="#features" className="text-sm text-[#a0a0a0] transition-colors hover:text-[#f5f5f5]">
              Features
            </a>
            <a href="#competitions" className="text-sm text-[#a0a0a0] transition-colors hover:text-[#f5f5f5]">
              Competitions
            </a>
            <a href="#story" className="text-sm text-[#a0a0a0] transition-colors hover:text-[#f5f5f5]">
              Our Story
            </a>
            <a
              href="https://apps.apple.com/us/app/mile-a-day/id6504697812"
              target="_blank"
              rel="noopener noreferrer"
              className="text-sm text-[#a0a0a0] transition-colors hover:text-[#f5f5f5]"
            >
              Download
            </a>
          </div>

          {/* Social links */}
          <div className="flex items-center gap-4">
            <a
              href="https://www.instagram.com/mileadayapp"
              target="_blank"
              rel="noopener noreferrer"
              aria-label="Follow us on Instagram"
              className="text-[#a0a0a0] transition-colors hover:text-[#f5f5f5]"
            >
              <svg className="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <rect width="20" height="20" x="2" y="2" rx="5" ry="5" />
                <path d="M16 11.37A4 4 0 1 1 12.63 8 4 4 0 0 1 16 11.37z" />
                <line x1="17.5" x2="17.51" y1="6.5" y2="6.5" />
              </svg>
            </a>
            <a
              href="https://www.tiktok.com/@mileadayapp"
              target="_blank"
              rel="noopener noreferrer"
              aria-label="Follow us on TikTok"
              className="text-[#a0a0a0] transition-colors hover:text-[#f5f5f5]"
            >
              <svg className="h-5 w-5" viewBox="0 0 24 24" fill="currentColor">
                <path d="M19.59 6.69a4.83 4.83 0 0 1-3.77-4.25V2h-3.45v13.67a2.89 2.89 0 0 1-2.88 2.5 2.89 2.89 0 0 1-2.89-2.89 2.89 2.89 0 0 1 2.89-2.89c.28 0 .54.04.79.1v-3.5a6.37 6.37 0 0 0-.79-.05A6.34 6.34 0 0 0 3.15 15a6.34 6.34 0 0 0 6.34 6.34 6.34 6.34 0 0 0 6.34-6.34V8.66a8.21 8.21 0 0 0 4.76 1.51v-3.5c0 .02-1 .02-1 .02z" />
              </svg>
            </a>
            <a
              href="https://x.com/mileadayapp"
              target="_blank"
              rel="noopener noreferrer"
              aria-label="Follow us on X"
              className="text-[#a0a0a0] transition-colors hover:text-[#f5f5f5]"
            >
              <svg className="h-4 w-4" viewBox="0 0 24 24" fill="currentColor">
                <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
              </svg>
            </a>
          </div>
        </div>

        <div className="mt-8 flex flex-col items-center gap-4 border-t border-[#333333]/30 pt-8 md:flex-row md:justify-between">
          <p className="text-xs text-[#a0a0a0]/50">
            &copy; {new Date().getFullYear()} Mile A Day. Built by Rob Wiscount & David Simmerman.
          </p>
          <div className="flex items-center gap-4">
            <a href="/privacy" className="text-xs text-[#a0a0a0]/40 transition-colors hover:text-[#a0a0a0]">
              Privacy Policy
            </a>
            <a href="/terms" className="text-xs text-[#a0a0a0]/40 transition-colors hover:text-[#a0a0a0]">
              Terms of Use
            </a>
          </div>
        </div>
      </div>
    </footer>
  )
}
