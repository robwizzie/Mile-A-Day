/**
 * Coach MCP (Run Plans for Claude): https://mileaday.run/mcp is the public
 * face of the backend's /coach/* router (backend/src/coachMcp). Every URL in
 * its OAuth metadata is a mileaday.run URL, so these public paths must all
 * reach the backend — exact sources only, query strings pass through.
 * backend/scripts/coach-mcp-check.mjs drives the whole sign-in through THIS
 * table, so a path missing here fails CI.
 */
export function coachMcpRewrites(backend = process.env.COACH_MCP_BACKEND_URL || process.env.NEXT_PUBLIC_API_URL || 'https://mad.mindgoblin.tech') {
	const api = backend.replace(/\/$/, '');
	return [
		{ source: '/mcp', destination: `${api}/coach/mcp` },
		{ source: '/authorize', destination: `${api}/coach/authorize` },
		{ source: '/token', destination: `${api}/coach/token` },
		{ source: '/register', destination: `${api}/coach/register` },
		{ source: '/revoke', destination: `${api}/coach/revoke` },
		{ source: '/coach/oauth/apple/callback', destination: `${api}/coach/oauth/apple/callback` },
		{
			source: '/.well-known/oauth-authorization-server',
			destination: `${api}/coach/.well-known/oauth-authorization-server`
		},
		{
			source: '/.well-known/oauth-protected-resource/mcp',
			destination: `${api}/coach/.well-known/oauth-protected-resource/mcp`
		},
		{
			source: '/.well-known/oauth-protected-resource',
			destination: `${api}/coach/.well-known/oauth-protected-resource`
		}
	];
}

/** @type {import('next').NextConfig} */
const nextConfig = {
	async rewrites() {
		return coachMcpRewrites();
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
			},
			// The coach connector's sign-in (Sign in with Apple for Claude): same rule.
			{
				source: '/connect/:path*',
				headers: [
					{ key: 'Content-Security-Policy', value: "frame-ancestors 'none'" },
					{ key: 'X-Frame-Options', value: 'DENY' },
					{ key: 'Cache-Control', value: 'no-store' }
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
