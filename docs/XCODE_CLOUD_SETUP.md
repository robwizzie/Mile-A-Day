# Xcode Cloud setup (iOS CI)

The GitHub Actions workflow (`.github/workflows/ci.yml`) covers the backend
and website, but the iOS app can only be built by Xcode — so its merge safety
net is Xcode Cloud. This is configured in App Store Connect / Xcode, not in
the repo, which is why this is a checklist instead of a workflow file.

## One-time setup (~10 minutes, from Xcode)

1. Open the project in Xcode → **Product ▸ Xcode Cloud ▸ Create Workflow…**
2. Select the **"Mile A Day"** product. Xcode walks you through granting
   Xcode Cloud access to the `robwizzie/Mile-A-Day` GitHub repo (an App Store
   Connect prompt the first time).
3. Configure the first workflow:
   - **Name:** `PR Build`
   - **Environment:** latest released Xcode, latest iOS SDK.
   - **Start condition:** *Pull Request Changes* — build on every PR that
     touches `app/`. Add a **Files and Folders** condition: start only when
     files under `app/` change (skips backend/website-only PRs).
   - **Action:** *Build* the "Mile A Day" scheme for **iOS**. No archive, no
     signing needed for a plain build — this is the compile safety net.
4. Optional second workflow, same pattern: **Start condition** *Branch
   Changes* on `main`, **Action** *Archive* with TestFlight (internal
   distribution). That gives every merged change a TestFlight build
   automatically.

## Notes / gotchas

- Xcode Cloud reads the project directly from GitHub; the Watch App and
  Widget extension targets build as dependencies of the main scheme — make
  sure the shared scheme ("Mile A Day") is checked into the repo
  (`.xcodeproj/xcshareddata/xcschemes/`), which it already is.
- Xcode Cloud's free tier (25 compute hours/month) comfortably covers this
  project's PR volume.
- The build status lands on the GitHub PR as a check ("Xcode Cloud / PR
  Build") next to the Actions checks — treat a red iOS check exactly like a
  red backend check: don't merge.
- If a build needs the HealthKit entitlements to compile, it will — plain
  builds don't require provisioning. Only the optional TestFlight archive
  workflow needs signing, and Xcode Cloud manages those certificates itself.
