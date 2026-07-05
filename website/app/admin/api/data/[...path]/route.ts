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
    },
  });
}

// Action proxy for the few admin POST endpoints (e.g. posts/:id/restore).
// Same cookie auth as GET; no request body is forwarded (none is needed).
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
  const res = await fetch(`${API_URL}/admin/${path.join("/")}${search}`, {
    method: "POST",
    headers: { authorization: `Bearer ${token}` },
    cache: "no-store",
  });

  const body = await res.text();
  return new Response(body, {
    status: res.status,
    headers: {
      "content-type": res.headers.get("content-type") ?? "application/json",
    },
  });
}
