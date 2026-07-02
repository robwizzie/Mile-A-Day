import { cookies } from "next/headers";

const API_URL =
  process.env.NEXT_PUBLIC_API_URL || "https://mad.mindgoblin.tech";
const COOKIE = "mad_admin";

// Browser posts the Apple (web) id_token here. We verify it via the backend,
// and on success stash the returned admin access token in an httpOnly cookie
// so it never touches client-side JS (XSS-safe). All dashboard reads then go
// through the same-origin proxy, which replays this cookie.
export async function POST(req: Request) {
  const { id_token } = await req.json().catch(() => ({}));
  if (!id_token) {
    return Response.json({ error: "id_token required" }, { status: 400 });
  }

  const res = await fetch(`${API_URL}/admin/auth/apple`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ id_token }),
  });

  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    return Response.json(
      { error: body.error ?? "Sign-in failed" },
      { status: res.status },
    );
  }

  const { accessToken } = await res.json();
  (await cookies()).set(COOKIE, accessToken, {
    httpOnly: true,
    secure: true,
    sameSite: "lax",
    path: "/admin",
    maxAge: 30 * 24 * 60 * 60, // matches the backend token's 30d lifetime
  });
  return Response.json({ ok: true });
}
