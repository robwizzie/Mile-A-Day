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
Use `npm` for all operations.

## Tailwind CSS 4
- No `tailwind.config.js` - Tailwind 4 uses CSS-based configuration.
- Theme tokens and custom properties defined in `globals.css` via `@theme` directive.
- Custom glass-morphism classes (`.glass-card`, `.glass-nav`, `.glass-button`) in globals.css.

## Styling Patterns
- Fonts: DM Sans (body) and Bebas Neue (headings) via `next/font/google`.
- Primary color: `#c72554` (burgundy red).
- Dark theme throughout (`bg-[#0a0a0a]`).
- Scroll reveal animations via `ScrollReveal` component (Intersection Observer).

## Admin dashboard (`app/admin/`)
- Tabs render from the `TABS` array in `dashboard.tsx`; each tab is one file in `_components/`. Data goes through `getData("<path>")` → the same-origin proxy → backend `/admin/<path>`, so a new panel needs a backend route and nothing else.
- Multi-series charts use `SERIES` from `lib.tsx` (validated for this dark surface: CVD separation, contrast, one lightness band). Assign in order, never cycle it, and never add a 4th concurrent series — split the chart instead. `PALETTE` is for one-series-per-card breakdowns only.
- A `HeatGrid` needs FIXED px columns and `justify-content: start`. A label placed in the flow widens its own track (the axis then drifts off the cells), and an `auto` first track in a stretched grid absorbs all slack and floats the plot to the right edge.
- Photos ≠ posts: `is_auto` route cards are published FOR a user who skips the prompt, so any "is the social feature working" number reads `photo_count`, never `post_count`.
