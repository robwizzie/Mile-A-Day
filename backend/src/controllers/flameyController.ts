import { Request, Response } from "express";
import { flameySkinsPayload } from "../services/flameySkins.js";

/** True when If-None-Match names `etag` (weak or strong, list or `*`). */
function matchesEtag(header: string | undefined, etag: string): boolean {
  if (!header) return false;
  return header
    .split(",")
    .map((t) => t.trim().replace(/^W\//, ""))
    .some((t) => t === "*" || t === etag);
}

/**
 * GET /flamey/skins?format=N — every skin the client's renderer (format N,
 * default 1) can draw. ETag = skins version + effective format; a matching
 * If-None-Match is a bodiless 304. The body is gzipped once at first request
 * and served pre-compressed (the app-wide compression() middleware skips a
 * response that already has a Content-Encoding).
 */
export async function getFlameySkins(req: Request, res: Response) {
  const raw = req.query.format;
  let format = 1;
  if (raw !== undefined) {
    if (typeof raw !== "string" || !/^\d{1,4}$/.test(raw) || Number(raw) < 1) {
      res.status(400).json({ error: "invalid_format" });
      return;
    }
    format = Number(raw);
  }

  const payload = flameySkinsPayload(format);
  res.setHeader("ETag", payload.etag);
  res.setHeader("Cache-Control", "private, no-cache");
  res.setHeader("Vary", "Accept-Encoding");

  if (matchesEtag(req.get("if-none-match"), payload.etag)) {
    res.status(304).end();
    return;
  }

  res.setHeader("Content-Type", "application/json; charset=utf-8");
  if (/\bgzip\b/i.test(req.get("accept-encoding") ?? "")) {
    res.setHeader("Content-Encoding", "gzip");
    res.setHeader("Content-Length", payload.gzipped.length);
    res.end(payload.gzipped);
  } else {
    // compression() may still deflate/br this; it drops Content-Length if so.
    res.setHeader("Content-Length", payload.body.length);
    res.end(payload.body);
  }
}
