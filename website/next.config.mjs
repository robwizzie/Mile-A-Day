const OG_ASSETS = ['./app/_og/fonts/*', './app/_og/*.png', './app/_og/*.jpg'];

/** @type {import('next').NextConfig} */
const nextConfig = {
	// The link-preview videos (app/_og/video, every segment's og.mp4): a
	// native Skia canvas and a WebAssembly H.264 encoder, loaded from
	// node_modules at runtime rather than bundled.
	serverExternalPackages: ['@napi-rs/canvas', 'h264-mp4-encoder'],
	// Files those routes read from disk: the vendored fonts and images, and
	// for /desk the box's MicroPython engine and code.
	outputFileTracingIncludes: {
		'/og.mp4': OG_ASSETS,
		'/**/og.mp4': OG_ASSETS,
		'/desk/og.mp4': [...OG_ASSETS, './public/desk/mp/*', './public/desk/py/**/*']
	},
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
