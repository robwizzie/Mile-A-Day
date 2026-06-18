"use client"

import { useEffect, useState } from "react"

const API_URL = process.env.NEXT_PUBLIC_API_URL || "https://mad.mindgoblin.tech"

export type PublicUser = {
  username: string
  firstName: string | null
  lastName: string | null
  /** Absolute URL to the profile image, or null if the user has none. */
  profileImageUrl: string | null
  currentStreak: number
}

// One fetch per username per page load, shared across every component that
// needs the same user (avatar + streak no longer fire separate requests).
const cache = new Map<string, Promise<PublicUser | null>>()

/** Fetch a user's public profile (image + streak + name) by username from the
 * marketing-site's world-readable endpoint. Returns null for unknown users or
 * on any error so callers can fall back to placeholders. */
export function fetchPublicUser(username: string): Promise<PublicUser | null> {
  const key = username.toLowerCase()
  if (!cache.has(key)) {
    cache.set(
      key,
      fetch(`${API_URL}/public/users/${encodeURIComponent(username)}`)
        .then((res) => (res.ok ? res.json() : null))
        .then((data) =>
          data
            ? {
                username: data.username,
                firstName: data.first_name ?? null,
                lastName: data.last_name ?? null,
                profileImageUrl: data.profile_image_url
                  ? `${API_URL}${data.profile_image_url}`
                  : null,
                currentStreak:
                  typeof data.current_streak === "number" ? data.current_streak : 0,
              }
            : null
        )
        .catch(() => null)
    )
  }
  return cache.get(key)!
}

/** React hook wrapper around {@link fetchPublicUser}. Returns null until the
 * profile loads (or permanently if the user can't be fetched). */
export function usePublicUser(username?: string): PublicUser | null {
  const [user, setUser] = useState<PublicUser | null>(null)

  useEffect(() => {
    if (!username) return
    let cancelled = false
    fetchPublicUser(username).then((u) => {
      if (!cancelled) setUser(u)
    })
    return () => {
      cancelled = true
    }
  }, [username])

  return user
}
