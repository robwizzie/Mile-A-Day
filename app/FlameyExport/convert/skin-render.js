// Draws a recorded skin layer (ops in body units — see RecContext.swift) on
// a canvas 2D context that is already transformed so 1 unit = u pixels and
// (0, 0) = the centre of Flamey's square. Shared by the match check and the
// Skin Builder; the Swift renderer implements the same rules.
//
// opts.blurScale / opts.shadowScale: canvas blur is σ, SwiftUI's radius isn't
// exactly σ — calibrated by the match check. opts.palette: token → colour.
(function (root) {
  function rgba(hex8) {
    const h = hex8.replace('#', '');
    const r = parseInt(h.slice(0, 2), 16), g = parseInt(h.slice(2, 4), 16), b = parseInt(h.slice(4, 6), 16);
    const a = h.length >= 8 ? parseInt(h.slice(6, 8), 16) / 255 : 1;
    return `rgba(${r},${g},${b},${a.toFixed(4)})`;
  }
  function withAlpha(hex8, k) {
    const h = hex8.replace('#', '');
    const a = (h.length >= 8 ? parseInt(h.slice(6, 8), 16) / 255 : 1) * k;
    return '#' + h.slice(0, 6) + Math.round(Math.max(0, Math.min(1, a)) * 255).toString(16).padStart(2, '0');
  }
  function colour(c, opts) {
    if (typeof c === 'string') return c;
    if (c && c.tok) {
      const base = opts && opts.palette && opts.palette[c.tok];
      if (!base) return c.fb;
      return withAlpha(base.length === 7 ? base + 'FF' : base, c.a ?? 1);
    }
    return '#000000FF';
  }
  function paintStyle(ctx, p, opts) {
    if (typeof p === 'string' || (p && p.tok)) return rgba(colour(p, opts));
    let g;
    if (p.lin) g = ctx.createLinearGradient(p.lin[0], p.lin[1], p.lin[2], p.lin[3]);
    else if (p.rad) g = ctx.createRadialGradient(p.rad[0], p.rad[1], p.rad[2], p.rad[0], p.rad[1], p.rad[3]);
    else if (p.conic) g = ctx.createConicGradient(p.conic[2] * Math.PI / 180, p.conic[0], p.conic[1]);
    else return 'black';
    for (const [t, c] of p.stops) g.addColorStop(Math.max(0, Math.min(1, t)), rgba(colour(c, opts)));
    return g;
  }
  const pathCache = new Map();
  function path(d) {
    let p = pathCache.get(d);
    if (!p) { p = new Path2D(d); pathCache.set(d, p); }
    return p;
  }
  function applyClips(ctx, rec, ids) {
    for (const id of ids || []) {
      const c = rec.clips[id];
      if (c.inv) {
        const p = new Path2D();
        p.rect(-50, -50, 100, 100);
        p.addPath(path(c.d));
        ctx.clip(p, 'evenodd');
      } else {
        ctx.clip(path(c.d), c.eo ? 'evenodd' : 'nonzero');
      }
    }
  }
  // Pixels per unit of the current transform (for filters, which are in px).
  function pxPerUnit(ctx) {
    const m = ctx.getTransform();
    return Math.sqrt(Math.abs(m.a * m.d - m.b * m.c));
  }
  function drawLayer(ctx, rec, opts = {}, images = {}) {
    if (!rec || !rec.ops) return;
    const k = pxPerUnit(ctx);
    for (const op of rec.ops) {
      ctx.save();
      applyClips(ctx, rec, op.clip);
      ctx.globalAlpha = (op.a ?? 1) * (opts.alpha ?? 1);
      for (const f of op.fx || []) {
        if (f.blur != null) ctx.filter = `blur(${f.blur * k * (opts.blurScale ?? 1)}px)`;
        if (f.shadow) {
          ctx.shadowColor = rgba(f.shadow[0]);
          ctx.shadowBlur = f.shadow[1] * k * (opts.shadowScale ?? 1);
          ctx.shadowOffsetX = f.shadow[2] * k;
          ctx.shadowOffsetY = f.shadow[3] * k;
        }
      }
      if (op.m) ctx.transform(op.m[0], op.m[1], op.m[2], op.m[3], op.m[4], op.m[5]);
      if (op.op === 'fill') {
        ctx.fillStyle = paintStyle(ctx, op.paint, opts);
        ctx.fill(path(op.d), op.eo ? 'evenodd' : 'nonzero');
      } else if (op.op === 'stroke') {
        ctx.strokeStyle = paintStyle(ctx, op.paint, opts);
        ctx.lineWidth = op.w;
        ctx.lineCap = op.cap || 'butt';
        ctx.lineJoin = op.join || 'miter';
        ctx.miterLimit = op.miter || 10;
        ctx.setLineDash(op.dash || []);
        ctx.lineDashOffset = op.phase || 0;
        ctx.stroke(path(op.d));
      } else if (op.op === 'image') {
        const img = images[op.src];
        if (img) ctx.drawImage(img, op.rect[0], op.rect[1], op.rect[2], op.rect[3]);
      }
      ctx.restore();
    }
  }
  const api = { drawLayer, rgba, colour };
  if (typeof module !== 'undefined') module.exports = api; else root.FlameySkinRender = api;
})(typeof window !== 'undefined' ? window : globalThis);
