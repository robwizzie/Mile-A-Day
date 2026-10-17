import { notFound } from "next/navigation";
import { Lab } from "./lab";

// Dev-only: every piece at front, three-quarter, rack (side-on) and back, to
// judge the 3D garments side by side. Not served in production.
export default function Page() {
  if (process.env.NODE_ENV === "production") notFound();
  return <Lab />;
}
