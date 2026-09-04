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
- `_components/theme.ts` ports the app's `MADTheme.swift` — madRed, walkBlue, the 16px/5%-fill/8%-border card, SF Rounded (`ui-rounded`, Nunito fallback, loaded in `admin/layout.tsx`). Never hand-pick a colour: if it isn't in MADTheme it's a new brand colour. Workout types use `workoutColor()` (runs red, walks blue). The PAGE stays black, deliberately — the app's red-tinted ground pushes colour into every neutral, which a metrics screen can't afford.
- Spacing is three tokens, not a per-card guess: `STACK_SECTIONS` between subjects, `Section` for the header above a group, `gap-3`/`gap-5` inside grids. Everything was `space-y-6` once, which is why a stat grid and a whole new subject looked equally far apart.
- A delta must describe the number it sits on — same quantity, same window. A "today" figure with a 30-day delta, or a signups delta on a total-users count, reads as precision and means nothing. Under ten in the prior window `Delta` shows the absolute change, because "+200%" off one event is noise.
- A metric that counts PEOPLE is `distinct` in `TREND_SPECS` and needs a `windowTotal` — summing its daily values counts somebody active on ten days as ten people, which once printed a number larger than the whole user base. Its bars stay a shape, never addends.
- `HeatGrid` only takes `fit` (stretch to the card) because its header labels are absolutely positioned; put a label back in the flow and flexible tracks drift off their cells again.
- Multi-series charts use `SERIES` (validated on the app surface: CVD separation, contrast, one lightness band). Assign in order, never cycle it, and never add a 4th concurrent series — walkBlue and warning are too light to join that band, so split the chart instead. `PALETTE` is for one-series-per-card breakdowns only.
- Any number worth reading is worth opening: panels call `useDrilldown()({kind, id})` for the rows behind it and `useOpenUser()` for one person, both from `Drilldown.tsx`. A new drill-down is a `DRILLDOWN_KINDS` entry plus a case in `getDrilldown` — no new endpoint, no new drawer.
- A `HeatGrid` needs FIXED px columns and `justify-content: start`. A label placed in the flow widens its own track (the axis then drifts off the cells), and an `auto` first track in a stretched grid absorbs all slack and floats the plot to the right edge.
- Photos ≠ posts: `is_auto` route cards are published FOR a user who skips the prompt, so any "is the social feature working" number reads `photo_count`, never `post_count`.
- `Section`/`Card` headers wrap on CONTENT, never a breakpoint. Their `actions` slot usually holds a `SegmentedControl`, which is ONE nowrap line of pills — 805px for the 7-metric Trends one — so a `shrink-0` actions div takes that width off the top and the title column collapses (64px, one word per line) while the DOCUMENT, not the card, goes 899px wide on a 390px phone: horizontal scroll on every tab, cards looking clipped, and raising the page gutter does nothing. `flex-wrap` + `basis-72` on the title drops the control to its own full-width line only when it truly won't fit; `min-w-0` is what lets a hint wrap at all. Verify by MEASURING `document.documentElement.scrollWidth` against the viewport, not by reading the JSX — the admin dashboard renders end-to-end offline with a `mad_admin` cookie (presence is the only gate) and Playwright `route()` mocks on `/admin/api/data/**`.
