/** @type {import('next').NextConfig} */
const nextConfig = {
	// The admin area (incl. /admin/connect, the database connector's sign-in)
	// must never render inside someone else's frame: a framed sign-in button is
	// a clickjacking target.
	async headers() {
		return [
			{
				source: '/admin/:path*',
				headers: [
					{ key: 'Content-Security-Policy', value: "frame-ancestors 'none'" },
					{ key: 'X-Frame-Options', value: 'DENY' }
				]
			}
		];
	},
	images: {
		formats: ['image/avif', 'image/webp'],
		remotePatterns: [
			{
				protocol: 'https',
				hostname: 'mad.mindgoblin.tech',
				pathname: '/uploads/**'
			},
			// Local API stub/dev server (NEXT_PUBLIC_API_URL override); unused in prod
			{
				protocol: 'http',
				hostname: 'localhost',
				pathname: '/uploads/**'
			}
		]
	}
};

export default nextConfig;
