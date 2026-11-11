import { Navbar } from '@/components/navbar';
import { Footer } from '@/components/footer';

export function LegalPage({ title, lastUpdated, children }: { title: string; lastUpdated: string; children: React.ReactNode }) {
	return (
		<main className="relative min-h-screen overflow-x-hidden bg-[#0e0809]">
			<Navbar />

			<section className="relative px-6 pb-20 pt-36">
				<div className="mx-auto max-w-3xl">
					<h1 className="font-heading text-[clamp(40px,7vw,64px)] leading-[0.95] text-white">
						{title}
					</h1>
					<p className="mt-4 text-[13px] font-semibold uppercase tracking-[0.18em] text-[#ff5a6e]">Last updated {lastUpdated}</p>

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
			<h2 className="font-heading text-[26px] text-white">{heading}</h2>
			<div className="mt-3 space-y-4">{children}</div>
		</div>
	);
}
