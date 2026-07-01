// Apple App Site Association — required for universal links so
// https://mileaday.run/u/<username> opens the iOS app directly.
//
// Served as a route handler (not a public/ file) to guarantee the
// application/json content type with no file extension, which is what
// Apple's CDN validator expects.
//
// Format: "<TeamID>.<BundleID>" — team + bundle confirmed from the app's
// provisioning profile.
const APP_ID = 'NS237SS5KD.org.robertwiscount.Mile-A-Day'

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
