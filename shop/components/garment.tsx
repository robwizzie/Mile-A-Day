import type { CSSProperties } from "react";
import type { Product } from "@/lib/catalog";
import { HOOK_RISE, bounds, type ModelId } from "@/lib/models";
import { DrawnGarment } from "./designs";
import { GlGarment } from "./garment-gl";

/** Rack angle for a piece that isn't facing you: nearly edge-on, like a real rail. */
export const SIDE_TURN = -76;

/** A model this tall (metres) is drawn at the `height` callers ask for; others scale with it. */
const REF_HEIGHT = 0.7;

function modelOf(product: Product): ModelId | undefined {
  return product.art.kind === "photo" ? product.art.model : undefined;
}

/** The drawn box is 400×440; photos keep their own proportions; models their real ones. */
export function garmentWidth(product: Product, height: number) {
  const model = modelOf(product);
  if (model) return (garmentHeight(product, height) * bounds(model).width) / bounds(model).height;
  return product.art.kind === "photo" ? garmentHeight(product, height) * product.art.aspect : (height * 400) / 440;
}

export function garmentHeight(product: Product, height: number) {
  const model = modelOf(product);
  if (model) return (height * bounds(model).height) / REF_HEIGHT;
  return product.art.kind === "photo" ? height * (product.art.scale ?? 1) : height;
}

/** Width a piece takes on the rail when it hangs side-on: its edge plus its depth. */
export function sideWidth(product: Product, height: number) {
  const a = (SIDE_TURN * Math.PI) / 180;
  const model = modelOf(product);
  if (!model) return garmentWidth(product, height) * Math.abs(Math.cos(a));
  const b = bounds(model);
  const ppm = garmentHeight(product, height) / b.height;
  return ppm * (b.width * Math.abs(Math.cos(a)) + b.depth * Math.abs(Math.sin(a)));
}

/** Hanger height above the garment, as a share of the garment's height (drawn and photo pieces). */
const HANGER = 0.17;

/** Total box a garment on its hanger takes (for layout): hook top to hem. */
export function hungSize(product: Product, height: number) {
  const h = garmentHeight(product, height);
  const model = modelOf(product);
  if (model) return { width: garmentWidth(product, height), height: (h * (bounds(model).height + HOOK_RISE)) / bounds(model).height };
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
  const model = modelOf(product);
  if (model && product.art.kind === "photo") {
    // Until the model is in (or with no WebGL), the photo stands in.
    const h = garmentHeight(product, height);
    const back = Math.abs(((((turn + 180) % 360) + 360) % 360) - 180) > 90;
    return (
      <GlGarment
        product={product}
        model={model}
        width={width}
        height={total}
        turn={turn}
        immediate={transition === "none"}
        className={className}
        style={style}
        photo={
          <img
            src={back ? product.art.back : product.art.front}
            alt=""
            draggable={false}
            className="absolute inset-x-0 bottom-0 w-full select-none object-contain"
            style={{ height: h }}
          />
        }
      />
    );
  }
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
          <img src={side === "back" ? art.back : art.front} alt="" draggable={false} className="garment-flat h-full w-full select-none object-contain" />
        ) : (
          <DrawnGarment cut={art.cut} color={art.color} design={art.design} side={side} className="garment-flat h-full w-full" />
        )}
      </div>
    </div>
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
