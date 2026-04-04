---
globs: website/**
---

# Website Conventions

## Stack
- Next.js 16 App Router (single-page marketing site)
- React 19, Tailwind CSS 4 (via `@tailwindcss/postcss` plugin)
- Deployed on Vercel with `@vercel/analytics`
- Icons: `lucide-react`
- Animations: `tw-animate-css` + custom keyframes in globals.css

## Structure
- `app/` - Next.js App Router (layout.tsx, page.tsx, globals.css)
- `components/` - Page sections (navbar, hero, features, CTA, footer, etc.)
- `public/` - Static assets (images, favicons)
- Single page site: `page.tsx` composes section components in order.

## Package Manager
Use `pnpm` for all operations. Do NOT use npm.

## Tailwind CSS 4
- No `tailwind.config.js` - Tailwind 4 uses CSS-based configuration.
- Theme tokens and custom properties defined in `globals.css` via `@theme` directive.
- Custom glass-morphism classes (`.glass-card`, `.glass-nav`, `.glass-button`) in globals.css.

## Styling Patterns
- Fonts: DM Sans (body) and Bebas Neue (headings) via `next/font/google`.
- Primary color: `#c72554` (burgundy red).
- Dark theme throughout (`bg-[#0a0a0a]`).
- Scroll reveal animations via `ScrollReveal` component (Intersection Observer).
