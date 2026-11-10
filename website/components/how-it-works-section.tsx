import { AppStoreButton } from "./app-store-button";
import { SectionHeader } from "./section-header";

const steps = [
  {
    number: 1,
    title: "Download",
    description:
      "Grab Mile A Day free from the App Store. Create your account in 30 seconds.",
  },
  {
    number: 2,
    title: "Tap Start Mile",
    description:
      "Walk it or run it. Rain or shine. Hit that red button and get your mile done. Walks from your Apple Watch or any app that saves to Apple Health count too.",
  },
  {
    number: 3,
    title: "Build your streak",
    description:
      "Watch your streak grow. Add friends. Start competitions. Keep showing up and it becomes a habit.",
  },
];

/** How to start, in three steps, right under the proof: the shortest path to the download. */
export function HowItWorksSection() {
  return (
    <section
      id="how-it-works"
      className="scroll-mt-20 bg-[#f6f1ec] px-6 py-24 text-[#1d1214]"
    >
      <div className="mx-auto max-w-6xl">
        <SectionHeader
          tone="light"
          eyebrow="How it works"
          title="Dead simple. By design."
          body="One mile a day, walked or run, anywhere. That's the whole rule."
        />

        <ol className="mt-14 grid gap-4 md:grid-cols-3">
          {steps.map((step) => (
            <li key={step.number} className="rounded-3xl bg-white px-7 py-8">
              <span className="flex h-11 w-11 items-center justify-center rounded-full bg-[#ec3047] font-heading text-[20px] text-white">
                {step.number}
              </span>
              <h3 className="mt-6 font-heading text-[26px] leading-tight">
                {step.title}
              </h3>
              <p className="mt-2 text-[16px] leading-relaxed text-[#4a3a3d]">
                {step.description}
              </p>
            </li>
          ))}
        </ol>

        <div className="mt-10">
          <AppStoreButton tone="dark" />
        </div>
      </div>
    </section>
  );
}
