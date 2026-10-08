import { ChevronDown, LifeBuoy, Mail } from "lucide-react";
import { SUPPORT_EMAIL, SUPPORT_MAILTO } from "@/lib/site";

// Help, on the landing page: the support inbox up front, plus the questions
// people actually write in about. Answers describe what the app does today —
// change them when the feature changes.
const FAQ = [
  {
    q: "Do walks from my Apple Watch or other apps count?",
    a: "Yes. Anything that saves a walk or run to Apple Health — your Apple Watch, a treadmill, or another running app — counts toward your mile automatically. You can also track right in the app with Start Mile.",
  },
  {
    q: "What happens if I miss a day?",
    a: "Streak Tokens have your back: Streak Save and Double Down are earned by running, and with a Streak Assist a friend can give you a mile they ran past their own goal to save your streak. Injured? Recovery Mode pauses your streak instead of ending it.",
  },
  {
    q: "Who can see my routes?",
    a: "Only your friends, and by default the first and last stretch of every route is trimmed off so your front door stays private. You can change how much in Settings, turn route maps off, or use Stealth Mode to never record a map at all.",
  },
  {
    q: "Is Mile A Day free? Is there an Android app?",
    a: "Mile A Day is free on iPhone and Apple Watch. Android isn't available yet — join the waitlist below and we'll let you know.",
  },
  {
    q: "How do I delete my account?",
    a: "Open the app, tap the gear on your Dashboard to open Settings, and choose Delete Account. If you can't get into the app, email us and we'll take care of it.",
  },
];

export function SupportSection() {
  return (
    <section
      id="support"
      className="section-lazy relative scroll-mt-20 px-6 py-24"
    >
      <div className="mx-auto grid max-w-6xl gap-10 lg:grid-cols-[minmax(0,5fr)_minmax(0,7fr)] lg:gap-16">
        <div>
          <span className="reveal mb-4 inline-block text-sm font-semibold uppercase tracking-widest text-[#c72554]">
            Help &amp; Support
          </span>
          <h2 className="reveal reveal-delay-1 font-heading text-[clamp(40px,6vw,64px)] leading-none tracking-[-1px] text-[#f5f5f5]">
            NEED A HAND?
          </h2>
          <p className="reveal reveal-delay-2 mt-4 max-w-md text-base leading-relaxed text-[#a0a0a0]">
            Question, bug, or a streak that doesn&apos;t look right? Email us —
            a real person from the team reads every message.
          </p>

          <a
            href={SUPPORT_MAILTO}
            className="reveal reveal-delay-3 glass-card-highlight group mt-8 flex max-w-md items-center gap-4 rounded-2xl p-5 transition-transform hover:-translate-y-0.5"
          >
            <span className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-[#c72554]">
              <Mail className="h-5 w-5 text-white" />
            </span>
            <span className="min-w-0">
              <span className="block text-xs font-semibold uppercase tracking-widest text-[#ff4d7d]">
                Email support
              </span>
              <span className="block truncate text-lg font-semibold text-[#f5f5f5] group-hover:underline">
                {SUPPORT_EMAIL}
              </span>
            </span>
          </a>

          <p className="reveal reveal-delay-4 mt-5 flex max-w-md items-start gap-2 text-sm leading-relaxed text-[#a0a0a0]/80">
            <LifeBuoy className="mt-0.5 h-4 w-4 shrink-0 text-[#c72554]" />
            <span>
              In the app?{" "}
              <span className="text-[#f5f5f5]">
                Settings → Help &amp; Support
              </span>{" "}
              opens an email with your app version filled in, which helps us fix
              things faster.
            </span>
          </p>
        </div>

        <div className="reveal reveal-delay-2 space-y-3">
          {FAQ.map((item) => (
            <details
              key={item.q}
              className="glass-card group rounded-2xl px-5 py-4 [&_summary::-webkit-details-marker]:hidden"
            >
              <summary className="flex cursor-pointer list-none items-center justify-between gap-4 text-[15px] font-semibold text-[#f5f5f5]">
                {item.q}
                <ChevronDown className="h-5 w-5 shrink-0 text-[#a0a0a0] transition-transform group-open:rotate-180" />
              </summary>
              <p className="mt-3 text-sm leading-relaxed text-[#a0a0a0]">
                {item.a}
              </p>
            </details>
          ))}
          <p className="px-1 pt-2 text-sm text-[#a0a0a0]/80">
            Didn&apos;t find it?{" "}
            <a
              href={SUPPORT_MAILTO}
              className="font-semibold text-[#ff4d7d] hover:underline"
            >
              Ask us at {SUPPORT_EMAIL}
            </a>
          </p>
        </div>
      </div>
    </section>
  );
}
