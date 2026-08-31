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
- `_components/theme.ts` is a PORT of the app's `MADTheme.swift` — madRed, walkBlue, the background gradient, the 16px/5%-fill/8%-border card, SF Rounded (`ui-rounded`, Nunito fallback, loaded in `admin/layout.tsx`). Never hand-pick a colour here: if it isn't in MADTheme it's a new brand colour. Workout types must use `workoutColor()` (runs red, walks blue) — the app's language, not a chart palette.
- Multi-series charts use `SERIES` (validated on the app surface: CVD separation, contrast, one lightness band). Assign in order, never cycle it, and never add a 4th concurrent series — walkBlue and warning are too light to join that band, so split the chart instead. `PALETTE` is for one-series-per-card breakdowns only.
- Any number worth reading is worth opening: panels call `useDrilldown()({kind, id})` for the rows behind it and `useOpenUser()` for one person, both from `Drilldown.tsx`. A new drill-down is a `DRILLDOWN_KINDS` entry plus a case in `getDrilldown` — no new endpoint, no new drawer.
- A `HeatGrid` needs FIXED px columns and `justify-content: start`. A label placed in the flow widens its own track (the axis then drifts off the cells), and an `auto` first track in a stretched grid absorbs all slack and floats the plot to the right edge.
- Photos ≠ posts: `is_auto` route cards are published FOR a user who skips the prompt, so any "is the social feature working" number reads `photo_count`, never `post_count`.
