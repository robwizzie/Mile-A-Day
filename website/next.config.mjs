/** @type {import('next').NextConfig} */
const nextConfig = {
  images: {
    formats: ['image/avif', 'image/webp'],
    remotePatterns: [
      {
        protocol: 'https',
        hostname: 'mad.mindgoblin.tech',
        pathname: '/uploads/**',
      },
    ],
  },
}

export default nextConfig
