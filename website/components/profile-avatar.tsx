"use client"

import Image from "next/image"
import { useEffect, useState } from "react"

const API_URL = process.env.NEXT_PUBLIC_API_URL || "https://mad.mindgoblin.tech"

// One fetch per username per page load, shared across every avatar instance.
const imageCache = new Map<string, Promise<string | null>>()

function fetchProfileImage(username: string): Promise<string | null> {
  if (!imageCache.has(username)) {
    imageCache.set(
      username,
      fetch(`${API_URL}/public/profile-image/${username}`)
        .then((res) => (res.ok ? res.json() : null))
        .then((data) => (data?.profile_image_url ? `${API_URL}${data.profile_image_url}` : null))
        .catch(() => null)
    )
  }
  return imageCache.get(username)!
}

/** Circular avatar that loads the user's real profile picture from the
 * backend (same endpoint the story section uses), with an initials
 * fallback while loading or for users without accounts. */
export function ProfileAvatar({
  username,
  initials,
  size,
  className,
  style,
}: {
  username?: string
  initials: string
  size: number
  className?: string
  style?: React.CSSProperties
}) {
  const [src, setSrc] = useState<string | null>(null)

  useEffect(() => {
    if (username) fetchProfileImage(username).then(setSrc)
  }, [username])

  return (
    <div
      className={`relative shrink-0 overflow-hidden rounded-full bg-[#222] ${className ?? ""}`}
      style={{ width: size, height: size, ...style }}
    >
      {src ? (
        <Image src={src} alt={initials} fill className="object-cover" sizes={`${size}px`} />
      ) : (
        <span
          className="flex h-full w-full items-center justify-center font-bold text-white/60"
          style={{ fontSize: Math.max(9, Math.round(size * 0.3)) }}
        >
          {initials}
        </span>
      )}
    </div>
  )
}
