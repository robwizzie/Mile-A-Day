import { ChevronDown, Mail } from "lucide-react";
import { SectionHeader } from "./section-header";
import { SUPPORT_EMAIL, SUPPORT_MAILTO } from "@/lib/site";

// Help, on the landing page: the support inbox up front, plus the questions
// people actually write in about. Answers describe what the app does today;
// change them when the feature changes.
export const FAQ = [
  {
    q: "Do walks from my Apple Watch or other apps count?",
    a: "Yes. Anything that saves a walk or run to Apple Health counts toward your mile automatically: your Apple Watch, a treadmill, another running app. You can also track right in the app with Start your mile.",
  },
  {
    q: "What happens if I miss a day?",
    a: "Streak Tokens have your back. Streak Save and Double Down are earned by going the extra mile, and with a Streak Assist a friend can give you a mile they ran past their own goal. Injured? Recovery Mode pauses your streak instead of ending it.",
  },
  {
    q: "Who can see my routes?",
    a: "Your friends, by default, and the first and last stretch of every route is trimmed off so your front door stays private. You can change how much in Settings, turn route maps off, or use Stealth Mode to never record a map at all.",
  },
  {
    q: "Is Mile A Day free? Is there an Android app?",
    a: "Mile A Day is free on iPhone and Apple Watch. Mile A Day+ is optional. Android isn't out yet; join the waitlist below and we'll let you know.",
  },
  {
    q: "How do I delete my account?",
    a: "In the app, tap the gear on Home to open Settings, then Delete Account. If you can't get into the app, email us and we'll take care of it.",
  },
];

export function SupportSection() {
  return (
    <section
      id="support"
      className="scroll-mt-20 bg-[#140b0e] px-6 py-24 text-white"
    >
      <div className="mx-auto grid max-w-6xl gap-12 lg:grid-cols-[minmax(0,5fr)_minmax(0,7fr)] lg:gap-16">
        <div>
          <SectionHeader
            eyebrow="Help & support"
            title="Need a hand?"
            body="Question, bug, or a streak that doesn't look right? Email us. A real person from the team reads every message."
          />

          <a
            href={SUPPORT_MAILTO}
            data-reveal=""
            style={{ "--d": "120ms" } as React.CSSProperties}
            className="lift group mt-8 flex max-w-md items-center gap-4 rounded-3xl bg-white/[0.05] p-5 hover:bg-white/[0.08]"
          >
            <span className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-[#ec3047]">
              <Mail className="h-5 w-5 text-white" aria-hidden="true" />
            </span>
            <span className="min-w-0">
              <span className="block text-[12px] font-semibold uppercase tracking-[0.16em] text-white/55">
                Email support
              </span>
              <span className="block truncate text-[18px] font-semibold group-hover:underline">
                {SUPPORT_EMAIL}
              </span>
            </span>
          </a>

          <p className="mt-5 max-w-md text-[15px] leading-relaxed text-white/60">
            In the app?{" "}
            <span className="text-white">Settings → Help &amp; Support</span>{" "}
            opens an email with your app version filled in, which helps us fix
            things faster.
          </p>
        </div>

        <div>
          <h3 className="sr-only">Frequently asked questions</h3>
          <div data-reveal="" style={{ "--d": "150ms" } as React.CSSProperties} className="divide-y divide-white/10 border-y border-white/10">
            {FAQ.map((item) => (
              <details
                key={item.q}
                className="group py-5 [&_summary::-webkit-details-marker]:hidden"
              >
                <summary className="flex cursor-pointer list-none items-center justify-between gap-4 text-[17px] font-semibold">
                  {item.q}
                  <ChevronDown className="h-5 w-5 shrink-0 text-white/50 transition-transform group-open:rotate-180" />
                </summary>
                <p className="mt-3 max-w-2xl text-[15px] leading-relaxed text-white/70">
                  {item.a}
                </p>
              </details>
            ))}
          </div>
          <p className="pt-5 text-[15px] text-white/60">
            Didn&apos;t find it?{" "}
            <a
              href={SUPPORT_MAILTO}
              className="font-semibold text-white underline decoration-white/30 underline-offset-4 hover:decoration-white"
            >
              Ask us at {SUPPORT_EMAIL}
            </a>
          </p>
        </div>
      </div>
    </section>
  );
}
