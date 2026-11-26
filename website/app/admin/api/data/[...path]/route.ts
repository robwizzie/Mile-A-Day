import { cookies } from "next/headers";

const API_URL =
  process.env.NEXT_PUBLIC_API_URL || "https://mad.mindgoblin.tech";

type Params = { params: Promise<{ path: string[] }> };

// Generic proxy: /admin/api/data/<path> -> backend /admin/<path>, attaching
// the admin token from the httpOnly cookie. Forwards the query string so
// ?category=&limit= pass through. GET reads; POST/PUT/PATCH are the admin
// actions (posts/:id/restore, desk messages, coach/settings, coach AI mode,
// review-note status). A small JSON body is forwarded when one is sent;
// anything else goes through without a body.
async function forward(method: "GET" | "POST" | "PUT" | "PATCH", req: Request, { params }: Params) {
  const token = (await cookies()).get("mad_admin")?.value;
  if (!token) {
    return Response.json({ error: "Not authenticated" }, { status: 401 });
  }

  const { path } = await params;
  const search = new URL(req.url).search;
  let payload = "";
  if (method !== "GET") {
    const isJson = (req.headers.get("content-type") ?? "").includes("application/json");
    payload = isJson ? await req.text() : "";
    if (payload.length > 4096) {
      return Response.json({ error: "Body too large" }, { status: 413 });
    }
  }
  const res = await fetch(`${API_URL}/admin/${path.join("/")}${search}`, {
    method,
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

export const GET = (req: Request, ctx: Params) => forward("GET", req, ctx);
export const POST = (req: Request, ctx: Params) => forward("POST", req, ctx);
export const PUT = (req: Request, ctx: Params) => forward("PUT", req, ctx);
export const PATCH = (req: Request, ctx: Params) => forward("PATCH", req, ctx);
