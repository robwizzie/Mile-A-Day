import { cookies } from "next/headers";

export async function POST() {
  (await cookies()).delete({ name: "mad_admin", path: "/admin" });
  return Response.json({ ok: true });
}
