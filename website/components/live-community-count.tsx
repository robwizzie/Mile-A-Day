"use client"

import { useEffect, useRef, useState } from "react"
import { ProfileAvatar } from "@/components/profile-avatar"

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

/** A fun, prominent "live community" banner: a stack of real member photos, an
 * animated live-updating user count, and a pulsing LIVE dot. Refreshes every
 * minute so anyone on the site can watch the community grow in real time. */
export function LiveCommunityCount() {
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
        // Fail silently — banner just doesn't render.
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

  if (count === null) return null

  return (
    <div className="reveal-scale mx-auto inline-flex max-w-full flex-wrap items-center justify-center gap-x-4 gap-y-3 rounded-full border border-white/10 bg-white/[0.04] px-5 py-3 backdrop-blur-xl sm:gap-x-5 sm:px-6">
      {/* Overlapping member photos */}
      <div className="flex -space-x-3">
        {FACES.map((face) => (
          <ProfileAvatar
            key={face.username}
            username={face.username}
            initials={face.initials}
            size={36}
            className="border-2 border-[#0a0a0a]"
          />
        ))}
      </div>

      {/* Animated live count */}
      <div className="flex items-center gap-2">
        <span className="relative flex h-2.5 w-2.5">
          <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-[#33B34D] opacity-75" />
          <span className="relative inline-flex h-2.5 w-2.5 rounded-full bg-[#33B34D]" />
        </span>
        <span className="font-heading text-[28px] leading-none tracking-[0.5px] text-[#f5f5f5] tabular-nums sm:text-[34px]">
          {display.toLocaleString()}
        </span>
        <span className="text-left text-[13px] font-medium leading-tight text-[#a0a0a0]">
          runners moving
          <br className="hidden sm:block" /> every day
        </span>
      </div>
    </div>
  )
}
