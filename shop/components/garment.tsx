import type { CSSProperties } from "react";
import type { Product } from "@/lib/catalog";
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
  transition = `transform 0.8s ${TURN_EASE}, --side 0.8s ${TURN_EASE}`,
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
  const side = Math.abs(Math.sin((turn * Math.PI) / 180));
  return (
    <div
      className={`garment-3d relative ${className ?? ""}`}
      style={
        {
          width,
          height: total,
          transform: `perspective(1600px) rotateY(${turn}deg)`,
          transition,
          "--side": side,
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
          <img
            src={side === "back" ? art.back : art.front}
            alt=""
            draggable={false}
            className="h-full w-full select-none object-contain"
          />
        ) : (
          <DrawnGarment cut={art.cut} color={art.color} design={art.design} side={side} className="h-full w-full" />
        )}
      </div>
    </div>
  );
}

/** A hanger: the hook wraps the rail, the shoulders sit behind the garment
 *  (so a tee's neckline shows them, like a real one would). */
function Hanger({ style }: { style?: CSSProperties }) {
  return (
    <svg viewBox="0 0 64 40" style={style} className="relative z-0 shrink-0" aria-hidden="true">
      <path
        d="M32 26 L32 17 C32 12.5, 39 11.5, 39 6.5 C39 2.5, 35.5 1, 32 1 C28 1, 25.5 3.5, 25.5 6.5"
        stroke="url(#hook-metal)"
        strokeWidth="2.4"
        strokeLinecap="round"
        fill="none"
      />
      <path d="M4 37 C 16 31, 26 25, 32 23 C 38 25, 48 31, 60 37" stroke="#2b2420" strokeWidth="4.5" strokeLinecap="round" fill="none" />
      <circle cx="32" cy="23.5" r="3.2" fill="#2b2420" />
    </svg>
  );
}
