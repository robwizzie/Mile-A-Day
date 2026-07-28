// Legacy probe path — older iOS versions fall back to the domain root when
// /.well-known/ misses. Same payload, one source of truth.
export { GET } from "../.well-known/apple-app-site-association/route";
