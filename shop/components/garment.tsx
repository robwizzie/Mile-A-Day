import type { CSSProperties } from "react";
import type { Product } from "@/lib/catalog";
import { BODIES } from "@/lib/garment-bodies";
import { DrawnGarment } from "./designs";

/** Rack angle for a piece that isn't facing you: nearly edge-on, like a real rail. */
export const SIDE_TURN = -76;

/** The drawn box is 400×440; photos keep their own proportions. */
export function garmentWidth(product: Product, height: number) {
  return product.art.kind === "photo" ? garmentHeight(product, height) * product.art.aspect : (height * 400) / 440;
}

export function garmentHeight(product: Product, height: number) {
  return product.art.kind === "photo" ? height * (product.art.scale ?? 1) : height;
}

/** Vertical strips a photo is cut into to curve it round the torso. */
const STRIPS = 40;
/** Half the torso's thickness, as a share of its width (a hung piece with some body to it). */
const DEPTH = 0.2;

/**
 * How far a photo garment stands out of its centre plane at each strip edge,
 * left to right as seen from the front: one smooth dome across the piece,
 * as deep as its torso is wide, easing out along the sleeves (no crease
 * where body meets sleeve). The back photo bulges the other way by the same
 * amount, so the two meet at the edges and the piece has real thickness
 * when it turns.
 */
function profile(product: Product, width: number): number[] {
  if (product.art.kind !== "photo") return [];
  const [l, r] = BODIES[product.art.front] ?? [0.2, 0.8];
  const centre = ((l + r) / 2) * width;
  const depth = DEPTH * (r - l) * width;
  const reach = Math.max(centre, width - centre);
  return Array.from({ length: STRIPS + 1 }, (_, i) => {
    const t = ((i / STRIPS) * width - centre) / reach;
    return depth * Math.pow(Math.max(0, 1 - t * t), 0.7);
  });
}

/** Width a piece takes on the rail when it hangs side-on: its edge plus its thickness. */
export function sideWidth(product: Product, height: number) {
  const w = garmentWidth(product, height);
  const deepest = Math.max(0, ...profile(product, w));
  const a = (SIDE_TURN * Math.PI) / 180;
  return w * Math.abs(Math.cos(a)) + 2 * deepest * Math.abs(Math.sin(a));
}

/** Hanger height above the garment, as a share of the garment's height. */
const HANGER = 0.17;

/** Total box a garment on its hanger takes (for layout). */
export function hungSize(product: Product, height: number) {
  const h = garmentHeight(product, height);
  return { width: garmentWidth(product, height), height: h + h * HANGER * 0.72 };
}

export const TURN_EASE = "cubic-bezier(0.22, 1, 0.36, 1)";

/**
 * A garment on its hanger as a 3D object with a front and a back face.
 * `turn` is its rotation about the hook in degrees: 0 faces you, ±180 shows
 * the back, SIDE_TURN hangs it side-on.
 */
export function Garment3D({
  product,
  height,
  turn,
  transition = `transform 0.8s ${TURN_EASE}, --turn 0.8s ${TURN_EASE}`,
  className,
  style,
}: {
  product: Product;
  height: number;
  turn: number;
  transition?: string;
  className?: string;
  style?: CSSProperties;
}) {
  const { width, height: total } = hungSize(product, height);
  return (
    <div
      className={`garment-3d relative ${className ?? ""}`}
      style={
        {
          width,
          height: total,
          transform: `perspective(1600px) rotateY(${turn}deg)`,
          transition,
          "--turn": turn,
          ...style,
        } as CSSProperties
      }
    >
      <Face product={product} height={height} side="front" />
      <Face product={product} height={height} side="back" />
    </div>
  );
}

function Face({ product, height, side }: { product: Product; height: number; side: "front" | "back" }) {
  const { art } = product;
  const h = garmentHeight(product, height);
  const hangerH = h * HANGER;
  return (
    <div className={`garment-face flex flex-col items-center ${side === "back" ? "is-back" : ""}`}>
      <Hanger style={{ height: hangerH, width: hangerH * 1.6 }} />
      <div className="garment-ink relative w-full" style={{ height: h, marginTop: -hangerH * 0.28 }}>
        {art.kind === "photo" ? (
          <Curved product={product} src={side === "back" ? art.back : art.front} width={garmentWidth(product, height)} height={h} back={side === "back"} />
        ) : (
          <DrawnGarment cut={art.cut} color={art.color} design={art.design} side={side} className="garment-flat h-full w-full" />
        )}
      </div>
    </div>
  );
}

/**
 * A photo bent round the torso: STRIPS vertical slices of it, each stood out
 * by the profile and angled to meet its neighbours, so the piece has a
 * rounded body you can see from the side. Each slice is shaded by which way
 * it faces as the piece turns (--turn, plus its own angle --a).
 */
function Curved({ product, src, width, height, back }: { product: Product; src: string; width: number; height: number; back: boolean }) {
  const depth = profile(product, width);
  // Seen from behind, left and right swap.
  const z = back ? [...depth].reverse() : depth;
  const dx = width / STRIPS;
  // Rounded so the server's markup matches the client's exactly.
  const r = (n: number) => Math.round(n * 100) / 100;
  return (
    <>
      <img
        src={src}
        alt=""
        draggable={false}
        className="garment-shadow pointer-events-none absolute inset-0 h-full w-full select-none"
        style={{ transform: "translateY(14px)" }}
      />
      {z.slice(0, -1).map((z0, i) => {
        const rise = z[i + 1] - z0;
        const angle = Math.atan2(rise, dx);
        return (
          <div
            key={i}
            className="garment-strip absolute top-0"
            style={
              {
                left: r(i * dx),
                // A hair of overlap hides the seams between slices.
                width: r(dx + 1.25),
                height: r(height),
                backgroundImage: `url(${src})`,
                backgroundSize: `${r(width)}px ${r(height)}px`,
                backgroundPosition: `${r(-i * dx)}px 0`,
                transform: `translateZ(${r(z0)}px) rotateY(${r((-angle * 180) / Math.PI)}deg) scaleX(${r(Math.hypot(dx, rise) / dx)})`,
                "--a": r((-angle * 180) / Math.PI + (back ? 180 : 0)),
              } as CSSProperties
            }
          />
        );
      })}
    </>
  );
}

/** A hanger: the hook wraps the rail, the shoulders sit behind the garment
 *  (so a tee's neckline shows them, like a real one would). */
function Hanger({ style }: { style?: CSSProperties }) {
  return (
    <svg viewBox="0 0 64 40" style={style} className="garment-hanger relative z-0 shrink-0" aria-hidden="true">
      <path
        d="M32 26 L32 17 C32 12.5, 39 11.5, 39 6.5 C39 2.5, 35.5 1, 32 1 C28 1, 25.5 3.5, 25.5 6.5"
        stroke="url(#hook-metal)"
        strokeWidth="2.4"
        strokeLinecap="round"
        fill="none"
      />
      <path d="M4 37 C 16 31, 26 25, 32 23 C 38 25, 48 31, 60 37" style={{ stroke: "var(--hanger)" }} strokeWidth="4.5" strokeLinecap="round" fill="none" />
      <circle cx="32" cy="23.5" r="3.2" style={{ fill: "var(--hanger)" }} />
    </svg>
  );
}
