import { cookies } from "next/headers";

const API_URL =
  process.env.NEXT_PUBLIC_API_URL || "https://mad.mindgoblin.tech";

// The Skin Builder's data: GET /admin/api/skins -> backend GET /flamey/skins
// (every skin file, { version, format_max, skins }), with the admin token
// from the httpOnly cookie like the /admin/api/data proxy. Not under
// /admin/<path> on the backend: the skins endpoint is the app's own, and an
// admin token is an ordinary user token to it.
//
// The website deploys on its own and never sees ../backend, so production
// reads the backend only. `next dev` alone falls back to the repo's
// backend/flamey-skins folder when the backend can't answer (not deployed
// yet, offline, a placeholder cookie) — `x-skins-source` says which it was.
export async function GET() {
  const token = (await cookies()).get("mad_admin")?.value;
  if (!token) {
    return Response.json({ error: "Not authenticated" }, { status: 401 });
  }

  let res: Response | null = null;
  try {
    res = await fetch(`${API_URL}/flamey/skins`, {
      headers: { authorization: `Bearer ${token}` },
      cache: "no-store",
    });
  } catch {
    res = null;
  }

  if (process.env.NODE_ENV === "development" && (!res || !res.ok)) {
    const local = await readLocalSkins();
    if (local) {
      return Response.json(local, {
        headers: { "cache-control": "no-store", "x-skins-source": "local" },
      });
    }
  }
  if (!res) {
    return Response.json({ error: "Backend unreachable" }, { status: 502 });
  }

  const body = await res.text();
  return new Response(body, {
    status: res.status,
    headers: {
      "content-type": res.headers.get("content-type") ?? "application/json",
      "cache-control": "no-store",
      "x-skins-source": "backend",
    },
  });
}

/** Dev only: the repo's skin files, in the endpoint's shape. */
async function readLocalSkins() {
  const fs = await import("node:fs/promises");
  const path = await import("node:path");
  const dir = path.join(/* turbopackIgnore: true */ process.cwd(), "..", "backend", "flamey-skins");
  try {
    const files = (await fs.readdir(dir)).filter((f) => f.endsWith(".json")).sort();
    const skins = await Promise.all(
      files.map(async (f) => JSON.parse(await fs.readFile(path.join(dir, f), "utf8"))),
    );
    skins.sort((a, b) => a.order - b.order || (a.id < b.id ? -1 : 1));
    return {
      version: "local",
      format_max: Math.max(1, ...skins.map((s) => s.format)),
      skins,
    };
  } catch {
    return null;
  }
}
