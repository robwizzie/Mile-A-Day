// Everything the shop sells, in rack order. One file so a new drop is a new
// entry here and a garment image in public/garments/ — nothing else.

import type { ModelId } from "./models";

export const APP_STORE_URL = "https://apps.apple.com/us/app/mile-a-day/id6746970905";
export const SITE_URL = "https://mileaday.run";
export const SUPPORT_EMAIL = "support@mileaday.run";

// Checkout is Shopify (Tapstitch is linked to the store and fulfils each
// order). A size's Buy button goes straight to Shopify's cart permalink —
// https://<domain>/cart/<variantId>:1 — so the shop needs no cart of its own.
// Until the domain and a size's variant id are both set, that size reads
// "Coming soon" instead of linking anywhere.
export const SHOPIFY_DOMAIN = process.env.NEXT_PUBLIC_SHOPIFY_DOMAIN ?? "";

export type Status = "available" | "soon" | "later";

export type Cut = "tee" | "longsleeve" | "tank";
export type DesignId = "daily-mile" | "streak" | "extra-mile" | "run-club" | "flamey-lit" | "flamey-crew";

export type Art =
  | {
      kind: "photo";
      front: string;
      back: string;
      aspect: number;
      /** Size vs the drawn pieces. */
      scale?: number;
      /** The drawn design printed on it, for `npm run prints`. */
      design?: DesignId;
      /** Its 3D model (lib/models.ts); the photo shows until that loads. */
      model?: ModelId;
    }
  | { kind: "drawn"; cut: Cut; color: string; design: DesignId };

export type Product = {
  id: string;
  name: string;
  /** Short line under the name: fabric / fit. */
  kind: string;
  /** USD. null hides the price (not decided yet). */
  price: number | null;
  status: Status;
  colorName: string;
  /** Hex of the garment, for the swatch. */
  swatch: string;
  art: Art;
  description: string;
  details: string[];
  sizes: string[];
  /** Shopify variant id per size; a size without one isn't buyable yet. */
  variants: Record<string, string>;
};

export const PRODUCTS: Product[] = [
  {
    id: "extra-mile-hoodie",
    name: "Go The Extra Mile Hoodie",
    kind: "Oversized fleece hoodie",
    // TODO(owner): confirm the retail price before launch.
    price: 60,
    status: "available",
    colorName: "Black",
    swatch: "#0d0d0d",
    art: { kind: "photo", front: "/garments/hoodie-front.webp", back: "/garments/hoodie-back.webp", aspect: 1210 / 1000, scale: 1.12, model: "hoodie" },
    description:
      "The MAD runner on the chest, Go The Extra Mile across the back, and a red bolt down each sleeve. Heavy and soft, cut roomy for cold-morning miles and post-run couches.",
    details: ["Oversized, dropped-shoulder fit", "Brushed fleece inside", "Front, back and both sleeves printed", "Printed to order and shipped to you"],
    sizes: ["S", "M", "L", "XL", "2XL"],
    variants: {},
  },
  {
    id: "daily-mile-tee",
    name: "One Mile Every Day Tee",
    kind: "Everyday cotton tee",
    price: null,
    status: "soon",
    colorName: "White",
    swatch: "#f7f6f2",
    art: { kind: "photo", front: "/garments/daily-mile-tee-front.webp", back: "/garments/daily-mile-tee-back.webp", aspect: 1208 / 1016, design: "daily-mile", model: "tee" },
    description:
      "A small MAD badge up front. On the back, the whole idea in three words and a week of checked-off days.",
    details: ["Soft cotton, regular fit", "MAD badge on the chest", "Big back print", "Printed to order"],
    sizes: ["S", "M", "L", "XL", "2XL"],
    variants: {},
  },
  {
    id: "extra-mile-long-sleeve",
    name: "Extra Mile Long Sleeve",
    kind: "Sun-faded boxy long sleeve",
    price: null,
    status: "soon",
    colorName: "Navy",
    swatch: "#1d3354",
    art: { kind: "photo", front: "/garments/extra-mile-long-sleeve-front.webp", back: "/garments/extra-mile-long-sleeve-back.webp", aspect: 1242 / 750, scale: 0.9, design: "extra-mile", model: "longsleeve" },
    description:
      "MAD on the chest and a 1.00 mile with its route across the back. For the miles that start before sunrise.",
    details: ["Boxy fit, sun-faded cotton", "Chest and back prints", "Printed to order"],
    sizes: ["S", "M", "L", "XL", "2XL"],
    variants: {},
  },
  {
    id: "streak-tee",
    name: "Don't Break The Streak Tee",
    kind: "Everyday cotton tee",
    price: null,
    status: "soon",
    colorName: "Black",
    swatch: "#151515",
    art: { kind: "photo", front: "/garments/streak-tee-front.webp", back: "/garments/streak-tee-back.webp", aspect: 1210 / 1017, design: "streak", model: "tee" },
    description: "The one rule on the front. The number everyone's chasing on the back.",
    details: ["Soft cotton, regular fit", "Front and back prints", "Printed to order"],
    sizes: ["S", "M", "L", "XL", "2XL"],
    variants: {},
  },
  {
    id: "run-club-tank",
    name: "Run Club Tank",
    kind: "Crewneck tank",
    price: null,
    status: "soon",
    colorName: "Heather Gray",
    swatch: "#9a9a9a",
    art: { kind: "photo", front: "/garments/run-club-tank-front.webp", back: "/garments/run-club-tank-back.webp", aspect: 802 / 1055, design: "run-club", model: "tank" },
    description: "A collegiate Mile A Day Run Club front for hot-weather miles, with a small MAD on the back.",
    details: ["Relaxed crewneck fit", "Front and back prints", "Printed to order"],
    sizes: ["S", "M", "L", "XL", "2XL"],
    variants: {},
  },
  {
    id: "flamey-tee",
    name: "Keep It Lit Flamey Tee",
    kind: "Everyday cotton tee",
    price: null,
    status: "later",
    colorName: "Cream",
    swatch: "#efe6d2",
    art: { kind: "photo", front: "/garments/flamey-tee-front.webp", back: "/garments/flamey-tee-back.webp", aspect: 1208 / 1016, design: "flamey-lit", model: "tee" },
    description: "Flamey keeps your streak lit. Now he can come on the run with you.",
    details: ["Soft cotton, regular fit", "Big Flamey front print", "Still Lit. on the back", "Printed to order"],
    sizes: ["S", "M", "L", "XL", "2XL"],
    variants: {},
  },
  {
    id: "flamey-run-crew",
    name: "Flamey Run Crew Long Sleeve",
    kind: "Cotton long sleeve",
    price: null,
    status: "later",
    colorName: "Black",
    swatch: "#161414",
    art: { kind: "photo", front: "/garments/flamey-run-crew-front.webp", back: "/garments/flamey-run-crew-back.webp", aspect: 1192 / 917, design: "flamey-crew", model: "longsleeve" },
    description: "A tiny Flamey on the chest and Flamey at full speed with his run crew across the back.",
    details: ["Soft cotton, regular fit", "Chest and back prints", "Printed to order"],
    sizes: ["S", "M", "L", "XL", "2XL"],
    variants: {},
  },
];

export const STATUS_LABEL: Record<Status, string> = {
  available: "Available now",
  soon: "Coming soon",
  later: "Coming later",
};

/** On sale right now: marked available AND at least one size can check out. */
export function isBuyable(product: Product): boolean {
  return product.sizes.some((s) => checkoutUrl(product, s) != null);
}

/** "Available now" only once checkout works; until then an available piece
 *  reads "Dropping soon" so the label never promises a button that's off. */
export function statusLabel(product: Product): string {
  if (product.status === "available" && !isBuyable(product)) return "Dropping soon";
  return STATUS_LABEL[product.status];
}

export function checkoutUrl(product: Product, size: string): string | null {
  const variant = product.variants[size];
  if (product.status !== "available" || !SHOPIFY_DOMAIN || !variant) return null;
  return `https://${SHOPIFY_DOMAIN}/cart/${variant}:1`;
}

export function formatPrice(price: number | null): string {
  return price == null ? "" : `$${price}`;
}
