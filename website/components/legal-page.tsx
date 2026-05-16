import Image from 'next/image';
import Link from 'next/link';
import { Footer } from '@/components/footer';

export function LegalPage({ title, lastUpdated, children }: { title: string; lastUpdated: string; children: React.ReactNode }) {
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
							loading="lazy"
						/>
						<span className="font-heading text-[22px] tracking-[2px] text-[#f5f5f5]">MILE A DAY</span>
					</Link>
					<Link
						href="/"
						className="text-sm font-medium text-[#a0a0a0] tracking-wide transition-colors hover:text-[#f5f5f5]"
					>
						Back to home
					</Link>
				</div>
			</nav>

			<section className="relative px-6 py-20">
				<div className="mx-auto max-w-3xl">
					<h1 className="font-heading text-[clamp(40px,7vw,64px)] leading-none tracking-[-1px] text-[#f5f5f5]">
						{title}
					</h1>
					<p className="mt-4 text-sm text-[#a0a0a0]/60">Last updated: {lastUpdated}</p>

					<div className="mt-12 text-[16px] leading-[1.8] text-[#a0a0a0]">{children}</div>
				</div>
			</section>

			<Footer />
		</main>
	);
}

export function Section({ heading, children }: { heading: string; children: React.ReactNode }) {
	return (
		<div className="mt-10 first:mt-0">
			<h2 className="font-heading text-[26px] tracking-[0.5px] text-[#f5f5f5]">{heading}</h2>
			<div className="mt-3 space-y-4">{children}</div>
		</div>
	);
}
