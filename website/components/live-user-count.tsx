'use client';

import { useEffect, useState } from 'react';

const API_URL = process.env.NEXT_PUBLIC_API_URL || 'https://mad.mindgoblin.tech';
const USER_COUNT_URL = `${API_URL}/public/user-count`;

export function LiveUserCount() {
	const [count, setCount] = useState<number | null>(null);
	const [display, setDisplay] = useState(0);

	useEffect(() => {
		let cancelled = false;
		fetch(USER_COUNT_URL)
			.then(res => (res.ok ? res.json() : Promise.reject(new Error(`HTTP ${res.status}`))))
			.then(data => {
				if (!cancelled && typeof data.count === 'number') setCount(data.count);
			})
			.catch(() => {
				// Fail silently — the stat simply doesn't render
			});
		return () => {
			cancelled = true;
		};
	}, []);

	useEffect(() => {
		if (count === null) return;
		const duration = 1200;
		const start = performance.now();
		let frame: number;
		const tick = (now: number) => {
			const t = Math.min((now - start) / duration, 1);
			const eased = 1 - Math.pow(1 - t, 3);
			setDisplay(Math.round(eased * count));
			if (t < 1) frame = requestAnimationFrame(tick);
		};
		frame = requestAnimationFrame(tick);
		return () => cancelAnimationFrame(frame);
	}, [count]);

	if (count === null) return null;

	return (
		<div className="animate-fade-in-up text-center lg:text-left">
			<div className="flex items-center justify-center gap-2 lg:justify-start">
				<span className="relative flex h-2 w-2">
					<span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-[#c72554] opacity-75" />
					<span className="relative inline-flex h-2 w-2 rounded-full bg-[#c72554]" />
				</span>
				<div className="font-heading text-[28px] text-[#f5f5f5]">{display.toLocaleString()}</div>
			</div>
			<div className="text-xs text-[#a0a0a0]">Users</div>
		</div>
	);
}
