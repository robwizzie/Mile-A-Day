"use client"

import { useEffect, useRef, useState } from "react"

const steps = [
  {
    number: 1,
    title: "DOWNLOAD",
    description:
      "Grab Mile A Day free from the App Store. Create your account in 30 seconds.",
  },
  {
    number: 2,
    title: "TAP START MILE",
    description:
      "Walk it or run it. Rain or shine. Hit that red button and get your mile done.",
  },
  {
    number: 3,
    title: "BUILD YOUR STREAK",
    description:
      "Watch your streak grow. Add friends. Start competitions. After 66 days, it's automatic.",
  },
]

export function HowItWorksSection() {
  const sectionRef = useRef<HTMLDivElement>(null)
  const [visible, setVisible] = useState(false)

  useEffect(() => {
    const el = sectionRef.current
    if (!el) return

    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setVisible(true)
          observer.disconnect()
        }
      },
      { threshold: 0.1 }
    )

    observer.observe(el)
    return () => observer.disconnect()
  }, [])

  return (
    <section ref={sectionRef} className="relative px-6 py-24">
      <div className="pointer-events-none absolute inset-0">
        <div className="absolute bottom-0 left-1/2 h-[400px] w-[400px] -translate-x-1/2 rounded-full bg-[#c72554] opacity-[0.04] blur-[150px]" />
      </div>
      <div className="relative mx-auto max-w-6xl text-center">
        <span
          className={`mb-4 inline-block text-sm font-semibold uppercase tracking-widest text-[#c72554] transition-all duration-700 ${
            visible ? "opacity-100 translate-y-0" : "opacity-0 translate-y-8"
          }`}
        >
          How It Works
        </span>
        <h2
          className={`font-heading text-[clamp(40px,6vw,72px)] leading-none tracking-[-1px] text-[#f5f5f5] mb-14 transition-all duration-700 delay-100 ${
            visible ? "opacity-100 translate-y-0" : "opacity-0 translate-y-8"
          }`}
        >
          DEAD SIMPLE. BY DESIGN.
        </h2>

        {/* Steps */}
        <div className="relative flex flex-col items-center gap-6 md:flex-row md:gap-0">
          {/* Connecting line (desktop only) */}
          <div className="pointer-events-none absolute top-9 left-[16.67%] right-[16.67%] hidden h-[2px] md:block">
            <div
              className={`h-full w-full rounded-full bg-gradient-to-r from-[#8b1538] via-[#c72554] to-[#ff4d7d] opacity-30 origin-left transition-transform duration-1000 ease-out ${
                visible ? "scale-x-100" : "scale-x-0"
              }`}
              style={{ transitionDelay: "0.2s" }}
            />
          </div>

          {steps.map((step, i) => (
            <div key={step.number} className="relative flex flex-1 flex-col items-center px-5">
              <div
                className={`relative z-10 mb-4 flex h-[72px] w-[72px] items-center justify-center rounded-full border-2 border-[#c72554]/30 bg-[#0a0a0a] transition-all duration-300 hover:border-[#c72554]/60 hover:shadow-[0_0_20px_rgba(199,37,84,0.2)] ${
                  visible ? `step-circle step-circle-delay-${i + 1}` : "opacity-0"
                }`}
              >
                <span className="font-heading text-[28px] text-[#c72554]">
                  {step.number}
                </span>
              </div>
              <div className={visible ? `step-content step-content-delay-${i + 1}` : "opacity-0"}>
                <h3 className="font-heading mb-2 text-[22px] tracking-[1px] text-[#f5f5f5]">
                  {step.title}
                </h3>
                <p className="text-sm leading-relaxed text-[#a0a0a0]">
                  {step.description}
                </p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
