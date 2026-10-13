declare module "gifenc" {
  export function GIFEncoder(): { writeFrame(index: Uint8Array, w: number, h: number, opts?: { palette?: number[][]; delay?: number; repeat?: number }): void; finish(): void; bytes(): Uint8Array };
  export function quantize(rgba: Uint8Array | Uint8ClampedArray, maxColors: number): number[][];
  export function applyPalette(rgba: Uint8Array | Uint8ClampedArray, palette: number[][]): Uint8Array;
}
