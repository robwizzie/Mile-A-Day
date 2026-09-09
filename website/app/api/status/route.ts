import { MANUAL_OUTAGE } from "./outage";

/**
 * Is Mile A Day up? — the app's outage check.
 *
 * This lives on the WEBSITE, not the API, and that is the entire point: the API
 * is the thing that goes down, so it cannot be the thing that reports being
 * down. The site is on Vercel and the API is self-hosted, so a power cut at the
 * API takes the API and nothing else, and this endpoint is still there to say
 * so. Anything that answers "are you up?" from inside the box being asked about
 * can only ever answer yes.
 *
 * Two sources, in order:
 *  1. `MANUAL_OUTAGE` — a human saying something the probe can't know ("back by
 *     six", "planned maintenance").
 *  2. A live probe of the API's own `/status`, so the common case needs nobody
 *     to do anything at all.
 *
 * Never throws and never 500s: a status endpoint that fails is indistinguishable
 * from the outage it exists to report.
 */

const API_URL =
  process.env.NEXT_PUBLIC_API_URL || "https://mad.mindgoblin.tech";

/** Long enough for a loaded server, short enough that the app isn't waiting. */
const PROBE_TIMEOUT_MS = 4000;

export const dynamic = "force-dynamic";

type StatusPayload = {
  /** The one field a client must understand: is the API reachable? */
  ok: boolean;
  status: "ok" | "outage";
  title: string | null;
  message: string | null;
  until: string | null;
  /** Where the verdict came from — for debugging, not for display. */
  source: "probe" | "manual";
  checked_at: string;
};

async function apiIsUp(): Promise<boolean> {
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), PROBE_TIMEOUT_MS);
    const res = await fetch(`${API_URL}/status`, {
      signal: controller.signal,
      cache: "no-store",
    });
    clearTimeout(timer);
    return res.ok;
  } catch {
    // A refused connection, a DNS failure and a timeout are all "down" from
    // where the user is standing.
    return false;
  }
}

export async function GET() {
  const checked_at = new Date().toISOString();

  let payload: StatusPayload;
  if (MANUAL_OUTAGE.active) {
    payload = {
      ok: false,
      status: "outage",
      title: MANUAL_OUTAGE.title,
      message: MANUAL_OUTAGE.message,
      until: MANUAL_OUTAGE.until,
      source: "manual",
      checked_at,
    };
  } else if (await apiIsUp()) {
    payload = {
      ok: true,
      status: "ok",
      title: null,
      message: null,
      until: null,
      source: "probe",
      checked_at,
    };
  } else {
    payload = {
      ok: false,
      status: "outage",
      title: "Mile A Day is down",
      message:
        "We're on it. Your walks are recorded on your phone and will sync as soon as we're back.",
      until: null,
      source: "probe",
      checked_at,
    };
  }

  return Response.json(payload, {
    headers: {
      "access-control-allow-origin": "*",
      // Short shared cache: during an outage every phone in the user base asks
      // this at once, and one probe every 30s is plenty to answer them all.
      // `stale-while-revalidate` means nobody ever waits on the probe itself.
      "cache-control": "public, s-maxage=30, stale-while-revalidate=60",
    },
  });
}
