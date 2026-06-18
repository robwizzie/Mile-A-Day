'use client';

import Image from 'next/image';
import { useEffect, useRef, useState } from 'react';

const API_URL = process.env.NEXT_PUBLIC_API_URL || 'https://mad.mindgoblin.tech';
const USER_COUNT_URL = `${API_URL}/public/user-count`;
const POLL_MS = 60_000;

export function LiveCounter() {
	const [count, setCount] = useState<number | null>(null);
	const [display, setDisplay] = useState(0);
	const [updatedAt, setUpdatedAt] = useState<number | null>(null);
	const [now, setNow] = useState(0);
	const [stale, setStale] = useState(false);
	const displayRef = useRef(0);

	// Poll the count every minute
	useEffect(() => {
		let cancelled = false;
		const load = async () => {
			try {
				const res = await fetch(USER_COUNT_URL, { cache: 'no-store' });
				if (!res.ok) throw new Error(`HTTP ${res.status}`);
				const data = await res.json();
				if (!cancelled && typeof data.count === 'number') {
					setCount(data.count);
					setUpdatedAt(Date.now());
					setStale(false);
				}
			} catch {
				if (!cancelled) setStale(true);
			}
		};
		load();
		const id = setInterval(load, POLL_MS);
		return () => {
			cancelled = true;
			clearInterval(id);
		};
	}, []);

	// Ticking clock for "updated Xs ago"
	useEffect(() => {
		setNow(Date.now());
		const id = setInterval(() => setNow(Date.now()), 1000);
		return () => clearInterval(id);
	}, []);

	// Animate the displayed number toward the latest count
	useEffect(() => {
		if (count === null || displayRef.current === count) return;
		const from = displayRef.current;
		const duration = 1500;
		const start = performance.now();
		let frame: number;
		const tick = (t: number) => {
			const p = Math.min((t - start) / duration, 1);
			const eased = 1 - Math.pow(1 - p, 3);
			const val = Math.round(from + (count - from) * eased);
			displayRef.current = val;
			setDisplay(val);
			if (p < 1) frame = requestAnimationFrame(tick);
		};
		frame = requestAnimationFrame(tick);
		return () => cancelAnimationFrame(frame);
	}, [count]);

	const secondsAgo = updatedAt && now ? Math.max(0, Math.floor((now - updatedAt) / 1000)) : null;

	return (
		<main
			className="relative flex min-h-screen flex-col items-center justify-center overflow-hidden px-6"
			style={{
				background:
					'radial-gradient(ellipse 800px 600px at 50% 110%, rgba(199,37,84,0.12) 0%, transparent 70%), radial-gradient(ellipse 500px 500px at 50% -10%, rgba(139,21,56,0.08) 0%, transparent 70%)'
			}}
		>
			{/* Wordmark */}
			<a href="/" className="absolute top-8 flex items-center gap-3 opacity-80 transition-opacity hover:opacity-100">
				<Image src="/images/mad-circle-icon.png" alt="Mile A Day" width={36} height={36} className="rounded-full" />
				<span className="font-heading text-xl tracking-[2px] text-[#f5f5f5]">MILE A DAY</span>
			</a>

			{/* Live badge */}
			<div className="glass-card-highlight mb-8 inline-flex items-center gap-2 rounded-full px-4 py-2">
				<span className="relative flex h-2 w-2">
					<span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-[#c72554] opacity-75" />
					<span className="relative inline-flex h-2 w-2 rounded-full bg-[#c72554]" />
				</span>
				<span className="text-xs font-semibold tracking-[3px] text-[#c72554]">LIVE</span>
			</div>

			{/* The number */}
			<div className="relative">
				<div
					className="absolute left-1/2 top-1/2 -z-10 h-[400px] w-[600px] -translate-x-1/2 -translate-y-1/2 rounded-full"
					style={{ background: 'radial-gradient(circle, rgba(199,37,84,0.1) 0%, transparent 70%)' }}
				/>
				<div className="font-heading text-[clamp(120px,28vw,320px)] leading-none tracking-[-2px] text-[#f5f5f5] tabular-nums">
					{count === null ? '—' : display.toLocaleString()}
				</div>
			</div>

			<div className="mt-2 text-sm font-medium tracking-[6px] text-[#a0a0a0]">USERS</div>

			{/* Status line */}
			<div className="absolute bottom-8 text-xs text-[#555555]">
				{stale
					? 'Connection lost — retrying every minute'
					: secondsAgo === null
						? 'Connecting…'
						: `Updated ${secondsAgo}s ago · refreshes every minute`}
			</div>
		</main>
	);
}
