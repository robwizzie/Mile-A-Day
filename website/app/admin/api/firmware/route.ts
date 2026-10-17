import { cookies } from "next/headers";

const API_URL =
  process.env.NEXT_PUBLIC_API_URL || "https://mad.mindgoblin.tech";

// The desk box firmware (.uf2), for desk owners: the admin cookie's token is
// passed to the backend, which only hands it to someone with a box. Binary,
// so it can't go through the JSON data proxy.
export async function GET() {
  const token = (await cookies()).get("mad_admin")?.value;
  if (!token) {
    return Response.json({ error: "Not authenticated" }, { status: 401 });
  }
  const res = await fetch(`${API_URL}/admin/desk/firmware`, {
    headers: { authorization: `Bearer ${token}` },
    cache: "no-store",
  });
  if (!res.ok) {
    return new Response(await res.text(), {
      status: res.status,
      headers: { "content-type": "application/json", "cache-control": "no-store" },
    });
  }
  return new Response(await res.arrayBuffer(), {
    status: 200,
    headers: {
      "content-type": "application/octet-stream",
      "content-disposition": res.headers.get("content-disposition") ?? 'attachment; filename="mad-desk.uf2"',
      "cache-control": "no-store",
    },
  });
}
