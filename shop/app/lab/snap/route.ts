import { mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";

// Dev-only: the lab posts its rendered canvas here so it can be inspected at
// full resolution (written to shop/.lab/, which is gitignored).
export async function POST(req: Request) {
  if (process.env.NODE_ENV === "production") return new Response(null, { status: 404 });
  const { name, data } = (await req.json()) as { name: string; data: string };
  const safe = name.replace(/[^a-z0-9-]/gi, "");
  const dir = join(process.cwd(), ".lab");
  await mkdir(dir, { recursive: true });
  await writeFile(join(dir, `${safe}.png`), Buffer.from(data.replace(/^data:image\/png;base64,/, ""), "base64"));
  return Response.json({ ok: true });
}
