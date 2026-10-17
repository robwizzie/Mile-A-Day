// A page that sets its own `openGraph` loses the root card (Next replaces the
// object rather than merging it), so this segment re-exports it.
export { default, alt, size, contentType } from "../opengraph-image";
