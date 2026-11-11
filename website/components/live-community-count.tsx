"use client"

import { useEffect, useRef, useState } from "react"
import { ProfileAvatar } from "@/components/profile-avatar"
import { LiveDot } from "./section-header"

const API_URL = process.env.NEXT_PUBLIC_API_URL || "https://mad.mindgoblin.tech"
const USER_COUNT_URL = `${API_URL}/public/user-count`
const POLL_MS = 60_000

// Real accounts whose photos appear in the live member stack.
const FACES = [
  { username: "rob", initials: "RW" },
  { username: "dave", initials: "DS" },
  { username: "MegsMiles", initials: "MM" },
  { username: "Aaron", initials: "AA" },
  { username: "mad", initials: "M" },
]

/** The "live community" pill on the closing panel: a stack of real member photos, an
 * animated live-updating user count, and a pulsing LIVE dot. Refreshes every
 * minute so anyone on the site can watch the community grow in real time. */
export function LiveCommunityCount({
  label = ["runners moving", "every day"],
}: {
  /** The two short lines beside the number. */
  label?: [string, string]
} = {}) {
  const [count, setCount] = useState<number | null>(null)
  const [display, setDisplay] = useState(0)
  const displayRef = useRef(0)

  // Poll the count every minute.
  useEffect(() => {
    let cancelled = false
    const load = async () => {
      try {
        const res = await fetch(USER_COUNT_URL, { cache: "no-store" })
        if (!res.ok) throw new Error(`HTTP ${res.status}`)
        const data = await res.json()
        if (!cancelled && typeof data.count === "number") setCount(data.count)
      } catch {
        // Fail silently: the banner just doesn't render.
      }
    }
    load()
    const id = setInterval(load, POLL_MS)
    return () => {
      cancelled = true
      clearInterval(id)
    }
  }, [])

  // Animate the displayed number toward the latest count.
  useEffect(() => {
    if (count === null || displayRef.current === count) return
    const from = displayRef.current
    const duration = 1400
    const start = performance.now()
    let frame: number
    const tick = (now: number) => {
      const t = Math.min((now - start) / duration, 1)
      const eased = 1 - Math.pow(1 - t, 3)
      const val = Math.round(from + (count - from) * eased)
      displayRef.current = val
      setDisplay(val)
      if (t < 1) frame = requestAnimationFrame(tick)
    }
    frame = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(frame)
  }, [count])

  // Always drawn (a placeholder count until the real one lands), so the
  // header never jumps when it arrives.
  return (
    <div className="group inline-flex max-w-full flex-wrap items-center gap-x-3 gap-y-2 rounded-[28px] bg-black/20 py-2.5 pl-2.5 pr-4 sm:gap-x-5 sm:pl-3 sm:pr-6">
      {/* Overlapping member photos: they pop in one by one and spread on hover */}
      <div className="flex -space-x-2.5 transition-all duration-300 group-hover:-space-x-1">
        {FACES.map((face, i) => (
          <span
            key={face.username}
            className="community-face inline-block transition-transform duration-200 hover:-translate-y-1"
            style={{ "--i": i } as React.CSSProperties}
          >
            <ProfileAvatar
              username={face.username}
              initials={face.initials}
              size={30}
              className="border-2 border-[#e42c42]"
            />
          </span>
        ))}
      </div>

      {/* Animated live count */}
      <div className="flex items-center gap-2">
        <LiveDot />
        <span className="font-heading text-[26px] leading-none text-white tabular-nums sm:text-[34px]">
          {count === null ? "…" : display.toLocaleString()}
        </span>
        <span className="text-left text-[12px] font-semibold leading-tight text-white/85 sm:text-[13px]">
          {label[0]}
          <br />
          {label[1]}
        </span>
      </div>
    </div>
  )
}
