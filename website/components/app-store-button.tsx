import { APP_STORE_URL } from "@/lib/site";

const APPLE_LOGO =
  "M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z";

/** The one download button: a solid pill that reads on any panel colour. */
export function AppStoreButton({
  label = "Download on the App Store",
  tone = "light",
  className = "",
  place,
}: {
  label?: string;
  /** Where the button sits, for the site analytics (`app_store:<place>`). */
  place?: string;
  /** light = white pill (on colour); dark = near-black pill (on white). */
  tone?: "light" | "dark";
  className?: string;
}) {
  const colors =
    tone === "light"
      ? "bg-white text-[#16090c] hover:bg-white/90"
      : "bg-[#16090c] text-white hover:bg-black";
  return (
    <a
      href={APP_STORE_URL}
      data-track={place ? `app_store:${place}` : "app_store"}
      target="_blank"
      rel="noopener noreferrer"
      className={`inline-flex items-center gap-2.5 lift rounded-full px-6 py-3.5 text-[15px] font-semibold ${colors} ${className}`}
    >
      <svg
        className="h-[18px] w-[18px]"
        viewBox="0 0 24 24"
        fill="currentColor"
        aria-hidden="true"
      >
        <path d={APPLE_LOGO} />
      </svg>
      {label}
    </a>
  );
}
