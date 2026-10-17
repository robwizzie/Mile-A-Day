// Everything the shop sells, in rack order. One file so a new drop is a new
// entry here and a garment image in public/garments/ — nothing else.

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
  | { kind: "photo"; front: string; back: string; aspect: number; /** Size vs the drawn pieces. */ scale?: number }
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
    art: { kind: "photo", front: "/garments/hoodie-front.webp", back: "/garments/hoodie-back.webp", aspect: 1210 / 1000, scale: 1.12 },
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
    art: { kind: "drawn", cut: "tee", color: "#f7f6f2", design: "daily-mile" },
    description:
      "A small MAD badge up front. On the back, the whole idea in three words and a week of checked-off days.",
    details: ["Soft cotton, regular fit", "MAD badge on the chest", "Big back print", "Printed to order"],
    sizes: ["S", "M", "L", "XL", "2XL"],
    variants: {},
  },
  {
    id: "extra-mile-long-sleeve",
    name: "Extra Mile Long Sleeve",
    kind: "Cotton long sleeve",
    price: null,
    status: "soon",
    colorName: "Burgundy",
    swatch: "#8b1538",
    art: { kind: "drawn", cut: "longsleeve", color: "#8b1538", design: "extra-mile" },
    description:
      "MAD on the chest, Go The Extra Mile down the sleeve, and a 1.00 mile with its route on the back. For the miles that start before sunrise.",
    details: ["Soft cotton, regular fit", "Chest, sleeve and back prints", "MAD burgundy", "Printed to order"],
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
    art: { kind: "drawn", cut: "tee", color: "#151515", design: "streak" },
    description: "The one rule on the front. The number everyone's chasing on the back.",
    details: ["Soft cotton, regular fit", "Front and back prints", "Printed to order"],
    sizes: ["S", "M", "L", "XL", "2XL"],
    variants: {},
  },
  {
    id: "run-club-tank",
    name: "Run Club Tank",
    kind: "Performance tank",
    price: null,
    status: "soon",
    colorName: "Heather",
    swatch: "#c4c4c0",
    art: { kind: "drawn", cut: "tank", color: "#c4c4c0", design: "run-club" },
    description: "A collegiate Mile A Day Run Club front for hot-weather miles. Light, quick-drying, made to move.",
    details: ["Lightweight performance knit", "Relaxed fit", "Front and back prints", "Printed to order"],
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
    art: { kind: "drawn", cut: "tee", color: "#efe6d2", design: "flamey-lit" },
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
    art: { kind: "drawn", cut: "longsleeve", color: "#161414", design: "flamey-crew" },
    description: "A tiny Flamey on the chest, his crew down the sleeve, and Flamey at full speed across the back.",
    details: ["Soft cotton, regular fit", "Chest, sleeve and back prints", "Printed to order"],
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
