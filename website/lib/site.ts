// Facts the whole site repeats. One copy each, so the footer, the support
// section and the release notes can't drift apart.

export const SITE_URL = "https://mileaday.run";
export const APP_STORE_URL =
  "https://apps.apple.com/us/app/mile-a-day/id6746970905";

// The same inbox the app's Help & Support screen opens
// (HelpAndSupportView.swift) and the privacy/terms pages list.
export const SUPPORT_EMAIL = "support@mileaday.run";
export const SUPPORT_MAILTO = `mailto:${SUPPORT_EMAIL}?subject=${encodeURIComponent("Mile A Day Support")}`;
