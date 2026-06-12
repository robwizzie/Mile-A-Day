/** @type {import('next').NextConfig} */
const nextConfig = {
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
