import { cookies } from "next/headers";

const API_URL =
  process.env.NEXT_PUBLIC_API_URL || "https://mad.mindgoblin.tech";

// Generic read-only proxy: /admin/api/data/<path> -> backend /admin/<path>,
// attaching the admin token from the httpOnly cookie. Forwards the query
// string so ?category=&limit= pass through.
export async function GET(
  req: Request,
  { params }: { params: Promise<{ path: string[] }> },
) {
  const token = (await cookies()).get("mad_admin")?.value;
  if (!token) {
    return Response.json({ error: "Not authenticated" }, { status: 401 });
  }

  const { path } = await params;
  const search = new URL(req.url).search;
  const res = await fetch(`${API_URL}/admin/${path.join("/")}${search}`, {
    headers: { authorization: `Bearer ${token}` },
    cache: "no-store",
  });

  const body = await res.text();
  return new Response(body, {
    status: res.status,
    headers: {
      "content-type": res.headers.get("content-type") ?? "application/json",
      // Admin data (and a freshly made display key) must never be cached.
      "cache-control": "no-store",
    },
  });
}

// Action proxy for the admin POST endpoints (e.g. posts/:id/restore). Same
// cookie auth as GET. A small JSON body is forwarded when one is sent (desk
// messages); anything else goes through without a body, as before.
export async function POST(
  req: Request,
  { params }: { params: Promise<{ path: string[] }> },
) {
  const token = (await cookies()).get("mad_admin")?.value;
  if (!token) {
    return Response.json({ error: "Not authenticated" }, { status: 401 });
  }

  const { path } = await params;
  const search = new URL(req.url).search;
  const isJson = (req.headers.get("content-type") ?? "").includes("application/json");
  const payload = isJson ? await req.text() : "";
  if (payload.length > 4096) {
    return Response.json({ error: "Body too large" }, { status: 413 });
  }
  const res = await fetch(`${API_URL}/admin/${path.join("/")}${search}`, {
    method: "POST",
    headers: payload
      ? { authorization: `Bearer ${token}`, "content-type": "application/json" }
      : { authorization: `Bearer ${token}` },
    body: payload || undefined,
    cache: "no-store",
  });

  const body = await res.text();
  return new Response(body, {
    status: res.status,
    headers: {
      "content-type": res.headers.get("content-type") ?? "application/json",
      // Admin data (and a freshly made display key) must never be cached.
      "cache-control": "no-store",
    },
  });
}
