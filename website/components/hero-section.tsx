import { CURRENT_RELEASE } from "@/lib/releases";
import { AppStoreButton } from "./app-store-button";
import { PanelBand } from "./feature-panels";
import { LiveCommunityCount } from "./live-community-count";

/** The App Store header, as the top of the site. */
export function HeroSection() {
  return (
    <PanelBand
      heading="h1"
      hero
      priority
      panel={{
        eyebrow: "Daily streaks",
        title: ["Walk or run a mile.", "Every day."],
        body: "Build a streak that keeps you moving. Free on iPhone and Apple Watch.",
        shot: "01-streak",
        alt: "The Mile A Day home screen: a 541 day streak and Flamey",
        from: "#ec3047",
        to: "#dc253b",
      }}
    >
      <div className="mt-8 flex flex-wrap items-center gap-x-6 gap-y-4">
        <AppStoreButton place="hero" />
        <a
          href="/updates"
          data-track="whats_new_hero"
          className="text-[15px] font-semibold text-white/90 underline decoration-white/40 underline-offset-4 hover:decoration-white"
        >
          New in {CURRENT_RELEASE.version}
        </a>
      </div>
      <div className="mt-10">
        <LiveCommunityCount label={["walking or running", "a mile a day with us"]} />
      </div>
    </PanelBand>
  );
}
