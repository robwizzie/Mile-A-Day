// Apple App Site Association — required for universal links so
// https://mileaday.run/u/<username> opens the iOS app directly.
//
// Served as a route handler (not a public/ file) to guarantee the
// application/json content type with no file extension, which is what
// Apple's CDN validator expects.
//
// TODO(rob): replace TEAMID with the Apple Developer Team ID
// (developer.apple.com → Membership) and verify the bundle ID matches the
// Xcode target. Format: "<TeamID>.<BundleID>".
const APP_ID = 'TEAMID.com.mileaday'

export async function GET() {
  return Response.json({
    applinks: {
      details: [
        {
          appIDs: [APP_ID],
          components: [
            {
              '/': '/u/*',
              comment: 'Public profile share links',
            },
          ],
        },
      ],
    },
  })
}
