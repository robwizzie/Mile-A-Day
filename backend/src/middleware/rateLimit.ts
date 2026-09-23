// HTTP rate limiting.
//
// Two failure modes matter more than the abuse this stops, and every choice
// below is made against them:
//
// 1. ONE BUCKET FOR EVERYONE. Prod is Cloudflare → Coolify's reverse proxy →
//    this process. Keyed on the wrong address, every request looks like it
//    comes from the proxy (a private container IP) or from a Cloudflare edge
//    node (a PUBLIC IP shared by every user routed through that PoP), and the
//    first limiter to trip locks out the whole install base. So an IP is only
//    ever a key when it is believed to be the CLIENT's: `clientIp()` below
//    takes Cloudflare's CF-Connecting-IP when (and only when) the request
//    reached us through Cloudflare or through our own private proxy, and an
//    address that is private, loopback or itself Cloudflare's resolves to NO
//    key — the IP limiter then SKIPS the request (fails open). A misconfigured
//    proxy makes the IP limits a no-op, never a global lock.
//
// 2. SHIPPED CLIENTS' 429 HANDLING. Every build in the wild signs the user out
//    on ANY non-200 from /auth/refresh (TokenRefreshService → APIClient
//    .refreshOrSignOut), so the refresh limit is its own bucket and set far
//    above anything a real client does (a refresh happens when a 30-day access
//    token nears expiry, or once after a 401). Elsewhere a 429 surfaces the
//    body's `error` string to the user (APIError.rateLimited), so `error` is a
//    human sentence and the machine-readable half rides `code` /
//    `retry_after_seconds`. Every value is a STRING: some client paths decode
//    error bodies as [String: String], where one number fails the decode.
//
// Store: in-memory (express-rate-limit's MemoryStore). With more than one
// instance each keeps its own counts, so the effective limit is N× — it can
// only UNDER-limit, never lock anyone out early. Counts reset on deploy.
//
// Env:
//   RATE_LIMITS_DISABLED=1      kill switch (read per request, no restart)
//   TRUST_PROXY_HOPS=<n>        reverse proxies in front of Express (default 1)
//   RATE_LIMIT_<NAME>_MAX=<n>   per-limiter override of the max (read per request)
import type { Express, Request, Response, NextFunction, RequestHandler } from "express";
import { rateLimit, ipKeyGenerator } from "express-rate-limit";
import net from "node:net";
import type { AuthenticatedRequest } from "./auth.js";

// ---------------------------------------------------------------------------
// Client IP resolution
// ---------------------------------------------------------------------------

/**
 * `trust proxy` = a HOP COUNT, never `true`. `true` makes `req.ip` the leftmost
 * X-Forwarded-For entry, which the client writes — anyone could pick their own
 * bucket (or someone else's). A count trusts exactly the proxies we run: with
 * one (Coolify's Traefik), `req.ip` is the address that proxy saw connect.
 */
export function configureTrustProxy(app: Express): number {
  const raw = process.env.TRUST_PROXY_HOPS;
  const parsed = raw === undefined || raw === "" ? 1 : Number.parseInt(raw, 10);
  const hops = Number.isFinite(parsed) && parsed >= 0 ? parsed : 1;
  app.set("trust proxy", hops);
  return hops;
}

// Cloudflare's published edge ranges (https://www.cloudflare.com/ips/). An
// address in here is a PoP, shared by thousands of users — never a client.
const CLOUDFLARE_CIDRS = [
  "173.245.48.0/20",
  "103.21.244.0/22",
  "103.22.200.0/22",
  "103.31.4.0/22",
  "141.101.64.0/18",
  "108.162.192.0/18",
  "190.93.240.0/20",
  "188.114.96.0/20",
  "197.234.240.0/22",
  "198.41.128.0/17",
  "162.158.0.0/15",
  "104.16.0.0/13",
  "104.24.0.0/14",
  "172.64.0.0/13",
  "131.0.72.0/22",
  "2400:cb00::/32",
  "2606:4700::/32",
  "2803:f800::/32",
  "2405:b500::/32",
  "2405:8100::/32",
  "2a06:98c0::/29",
  "2c0f:f248::/32",
];

// Loopback, RFC1918, CGNAT's shared space, link-local, ULA — addresses that
// are either our own infrastructure or cannot identify one user.
const NON_CLIENT_CIDRS = [
  "0.0.0.0/8",
  "10.0.0.0/8",
  "100.64.0.0/10",
  "127.0.0.0/8",
  "169.254.0.0/16",
  "172.16.0.0/12",
  "192.168.0.0/16",
  "::1/128",
  "::/128",
  "fc00::/7",
  "fe80::/10",
];

function buildBlockList(cidrs: string[]): net.BlockList {
  const list = new net.BlockList();
  for (const cidr of cidrs) {
    const [addr, bits] = cidr.split("/");
    const type = net.isIPv6(addr) ? "ipv6" : "ipv4";
    list.addSubnet(addr, Number(bits), type);
  }
  return list;
}

const CLOUDFLARE = buildBlockList(CLOUDFLARE_CIDRS);
const NON_CLIENT = buildBlockList(NON_CLIENT_CIDRS);

function normalizeIp(ip: string | undefined | null): string | null {
  if (!ip) return null;
  let s = ip.trim();
  if (s.startsWith("::ffff:") && net.isIPv4(s.slice(7))) s = s.slice(7);
  return net.isIP(s) ? s : null;
}

function inList(list: net.BlockList, ip: string): boolean {
  return list.check(ip, net.isIPv6(ip) ? "ipv6" : "ipv4");
}

const isCloudflare = (ip: string) => inList(CLOUDFLARE, ip);
const isNonClient = (ip: string) => inList(NON_CLIENT, ip);

/**
 * The client's address, or null when we can't be confident we have it (the
 * IP limiters skip those requests rather than pool them into one bucket).
 *
 * CF-Connecting-IP is honoured only when the peer we trust (req.ip, after the
 * hop count) is Cloudflare or our own private proxy — a request that reaches
 * the origin directly from the internet cannot pick its bucket with a header.
 */
export function clientIp(req: Request): string | null {
  const peer = normalizeIp(req.ip ?? req.socket?.remoteAddress);
  if (!peer) return null;

  let candidate = peer;
  if (isCloudflare(peer) || isNonClient(peer)) {
    const header = req.headers["cf-connecting-ip"];
    const cf = normalizeIp(Array.isArray(header) ? header[0] : header);
    if (!cf) return null;
    candidate = cf;
  }
  if (isNonClient(candidate) || isCloudflare(candidate)) return null;
  return candidate;
}

// ---------------------------------------------------------------------------
// Limiters
// ---------------------------------------------------------------------------

export function rateLimitsDisabled(): boolean {
  const v = (process.env.RATE_LIMITS_DISABLED ?? "").trim().toLowerCase();
  return v === "1" || v === "true" || v === "on" || v === "yes";
}

type KeyMode = "ip" | "user";

interface LimiterSpec {
  /** Env suffix: RATE_LIMIT_<NAME>_MAX. Also the bucket prefix. */
  name: string;
  windowMs: number;
  max: number;
  key: KeyMode;
  /** The sentence a shipped client shows the user. */
  message: string;
}

function envMax(name: string, fallback: number): number {
  const raw = process.env[`RATE_LIMIT_${name}_MAX`];
  if (raw === undefined || raw === "") return fallback;
  const n = Number.parseInt(raw, 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

// IPv6: one subscriber usually holds a whole /56 or /64, so keying on the full
// address lets one phone rotate through buckets. /56 is the library default.
const IPV6_SUBNET = 56;

function ipKey(req: Request): string | null {
  const ip = clientIp(req);
  return ip ? ipKeyGenerator(ip, IPV6_SUBNET) : null;
}

/** userId when authenticated, else the client IP, else null (skip). */
function userKey(req: Request): string | null {
  const userId = (req as AuthenticatedRequest).userId;
  if (userId) return `u:${userId}`;
  const ip = ipKey(req);
  return ip ? `ip:${ip}` : null;
}

function makeLimiter(spec: LimiterSpec): RequestHandler {
  const resolveKey = spec.key === "user" ? userKey : ipKey;
  return rateLimit({
    windowMs: spec.windowMs,
    limit: () => envMax(spec.name, spec.max),
    // draft-6: separate RateLimit-Limit / -Remaining / -Reset headers, plus
    // Retry-After on the 429 itself.
    standardHeaders: "draft-6",
    legacyHeaders: false,
    skip: (req) => rateLimitsDisabled() || resolveKey(req) === null,
    keyGenerator: (req) => `${spec.name}:${resolveKey(req) ?? "none"}`,
    // Our key generator does its own proxy/IPv6 handling (see clientIp); the
    // library's checks would warn about things it can't see we handled.
    validate: {
      trustProxy: false,
      xForwardedForHeader: false,
      keyGeneratorIpFallback: false,
      ipv6SubnetOrKeyGenerator: false,
    },
    handler: (req: Request, res: Response, _next: NextFunction, options) => {
      const resetTime = (req as any).rateLimit?.resetTime as Date | undefined;
      const retryAfter = Math.max(
        1,
        Math.ceil(
          ((resetTime?.getTime() ?? Date.now() + options.windowMs) - Date.now()) / 1000,
        ),
      );
      res.setHeader("Retry-After", String(retryAfter));
      res.status(options.statusCode).json({
        error: spec.message,
        code: "rate_limited",
        limiter: spec.name.toLowerCase(),
        retry_after_seconds: String(retryAfter),
      });
    },
  });
}

const MIN = 60 * 1000;

/** Everything a limiter answers, for the check script and for docs. */
export const RATE_LIMIT_SPECS = {
  // POST /auth/signin (and the admin dashboard's Apple web sign-in). Per IP
  // because there is no user yet. A real person signs in a handful of times
  // per install; 30/15min leaves room for a carrier NAT sharing one address
  // across many phones while still stopping identity-token spraying.
  signin: {
    name: "SIGNIN",
    windowMs: 15 * MIN,
    max: 30,
    key: "ip",
    message: "Too many sign-in attempts. Please wait a few minutes and try again.",
  },
  // POST /auth/refresh and /auth/logout. SEPARATE and generous: a shipped
  // client that gets any non-200 from refresh SIGNS THE USER OUT. A real
  // install refreshes about once a month; 600/15min per IP (40/min) is far
  // beyond a carrier NAT's worth of phones and still bounds a flood.
  session: {
    name: "SESSION",
    windowMs: 15 * MIN,
    max: 600,
    key: "ip",
    message: "Too many requests. Please try again in a moment.",
  },
  // Every multipart upload: post media (incl. the FRONT & BACK twin — two
  // uploads per post), profile image, banner. 40/15min is a post every ~45s
  // with both frames, which no person sustains.
  upload: {
    name: "UPLOAD",
    windowMs: 15 * MIN,
    max: 40,
    key: "user",
    message: "You're uploading a lot of photos right now. Try again in a few minutes.",
  },
  // POST /posts (feed posts, stories, auto cards) and PUT /posts/:id/crew-photo.
  post: {
    name: "POST_CREATE",
    windowMs: 15 * MIN,
    max: 30,
    key: "user",
    message: "You're posting a lot right now. Try again in a few minutes.",
  },
  // Comments on posts and on raw workouts.
  comment: {
    name: "COMMENT",
    windowMs: 15 * MIN,
    max: 60,
    key: "user",
    message: "You're commenting a lot right now. Take a breather and try again in a bit.",
  },
  // Post/comment reports: each one lands in the moderation queue.
  report: {
    name: "REPORT",
    windowMs: 60 * MIN,
    max: 20,
    key: "user",
    message: "You've sent a lot of reports. Thanks — we'll review them. Try again later.",
  },
  // Backstop across every authenticated route. Must sit far above any real
  // client: a first-run import uploads 50-workout batches back to back (a few
  // thousand workouts = ~100 requests in a couple of minutes), plus feed,
  // widgets, background refresh and 5s buddy progress reports. 3000/10min is
  // 5 req/s sustained for ten minutes.
  global: {
    name: "GLOBAL",
    windowMs: 10 * MIN,
    max: 3000,
    key: "user",
    message: "Too many requests. Please try again in a moment.",
  },
} satisfies Record<string, LimiterSpec>;

export const signInLimiter = makeLimiter(RATE_LIMIT_SPECS.signin);
export const sessionLimiter = makeLimiter(RATE_LIMIT_SPECS.session);
export const uploadLimiter = makeLimiter(RATE_LIMIT_SPECS.upload);
export const postCreateLimiter = makeLimiter(RATE_LIMIT_SPECS.post);
export const commentLimiter = makeLimiter(RATE_LIMIT_SPECS.comment);
export const reportLimiter = makeLimiter(RATE_LIMIT_SPECS.report);
export const globalUserLimiter = makeLimiter(RATE_LIMIT_SPECS.global);
