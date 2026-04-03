<p align="center">
  <img src="public/images/mad-circle-icon.png" alt="Mile A Day" width="120" />
</p>

# Mile A Day — Website

The official marketing website for **Mile A Day**, a free iOS app that challenges you to walk or run one mile every single day and build an unbreakable streak.

🔗 **Live site:** [mileaday.run](https://mileaday.run)

---

## About the App

Mile A Day was born from a bet between two competitive friends — Rob Wiscount and David Simmerman — who challenged each other to run a mile every day and never stopped. The app is free, not VC-backed, and built because it changed our lives.

**Core idea:** One mile. Every day. No excuses.

- Track your daily mile streak
- Compete with friends across 5 game modes
- Earn badges and medals
- Apple Watch + HealthKit integration
- 100% free

[![Download on the App Store](https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg)](https://apps.apple.com/app/mile-a-day/id6744917105)

---

## Tech Stack

- **Next.js 16** — React framework with App Router
- **React 19** — UI library
- **TypeScript** — Type safety
- **Tailwind CSS 4** — Utility-first styling
- **Radix UI** — Accessible headless components
- **React Hook Form + Zod** — Form handling and validation
- **Vercel Analytics** — Usage tracking

---

## Getting Started

```bash
# Install dependencies
npm install

# Start development server
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) to view the site.

### Other Commands

```bash
npm run build    # Production build
npm start        # Start production server
npm run lint     # Run ESLint
```

---

## Project Structure

```
app/
  layout.tsx              # Root layout, fonts, metadata
  page.tsx                # Home page

components/
  navbar.tsx              # Navigation bar
  hero-section.tsx        # Landing hero with phone mockup
  features-section.tsx    # App feature highlights
  habit-section.tsx       # 66-day habit science breakdown
  competitions-section.tsx # 5 competition game modes
  how-it-works-section.tsx # 3-step onboarding flow
  story-section.tsx       # Founder origin story
  cta-section.tsx         # Download CTA + Android waitlist
  footer.tsx              # Site footer
  ui/                     # Reusable UI components (Radix-based)

public/
  images/                 # App screenshots, logos, avatars
```

---

## License

All rights reserved. This project is proprietary software.

---

## Connect

- [Instagram](https://instagram.com/mileadayapp)
- [TikTok](https://tiktok.com/@mileadayapp)
- [X / Twitter](https://x.com/mileadayapp)
