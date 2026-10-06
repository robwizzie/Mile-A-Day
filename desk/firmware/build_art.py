"""Build the pixel art for the Mile A Day desk counter.

ONE runner model drives both:
  * the 8-frame animated runner (dashboard, stat show, celebration), and
  * the runner in the startup logo (frame LOGO_FRAME of the same cycle,
    drawn bigger and smooth).
Change the model here, run `python3 build_art.py`, and both stay in sync.
Output: mad_art.py (pre-rendered pixels, so the board does no heavy math).

The model is a pixel-art run cycle: every joint sits on a whole pixel, the
head and torso are a fixed stamp, and frames 4-7 are frames 0-3 with the legs
and arms swapped. So the stride is perfectly even (no limp) and nothing
changes thickness or shape between frames - only the limbs move.
"""
import math
import numpy as np
from PIL import Image, ImageDraw

# palette indexes (must match mad_app.py)
BLACK, MAROON_DIM, MAROON, RED, WHITE, FAR = 0, 1, 2, 3, 4, 5
LOGO_RUN, LOGO_SPEED, LOGO_SHADOW = 13, 14, 15

SPRITE_W, SPRITE_H = 18, 17
FRAMES = 8

# ---------------- the model (sprite pixels) ----------------
BODY = (                      # head + torso (hard forward lean), never changes
    "............##....",
    "...........####...",
    "...........####...",
    "............##....",
    "...........##.....",
    "..........###.....",
    ".........##.......",
    "........##........",
)
HIPS = ((8, 8), (9, 8))
# Skeleton points of the stamp (for the smooth logo render)
HIP_C, SHOULDER_C, HEAD_C, HEAD_R = (9.0, 9.0), (11.4, 5.6), (12.4, 2.9), 1.9

# Four poses; each gives two legs as (hip, knee, ankle, shoe pixels).
# Leg A runs contact -> down -> pass -> push-off; leg B runs heel-kick ->
# tuck -> knee-drive. Frames 4-7 swap which leg is near.
POSES = (
    # name,      leg A,                                    leg B,                  body bob (dy)
    ("contact", ((9, 9), (11, 12), (13, 15), ((13, 16), (14, 16))),
                ((8, 9), (6, 12), (3, 12), ((2, 13), (3, 13))), 0),
    ("down",    ((9, 9), (11, 12), (10, 15), ((10, 16), (11, 16))),
                ((8, 9), (6, 12), (3, 10), ((2, 10), (1, 10))), 1),
    ("pass",    ((8, 9), (9, 12), (8, 15), ((8, 16), (9, 16))),
                ((9, 9), (11, 11), (7, 12), ((6, 12), (5, 12))), 0),
    ("flight",  ((8, 9), (5, 11), (2, 12), ((1, 13), (2, 13))),
                ((9, 9), (13, 10), (11, 13), ((11, 14), (12, 14))), 0),
)
# Arms (shoulder, elbow, hand). Near/far arm per pose; swapped for frames 4-7.
ARMS = {
    "fwd": ((12, 6), (14, 8), (15, 6)),     # elbow driven forward, fist up at chin
    "fmid": ((12, 6), (13, 8), (15, 8)),
    "mid": ((11, 6), (11, 8), (13, 9)),
    "bmid": ((10, 6), (8, 8), (9, 10)),
    "back": ((10, 6), (7, 6), (6, 9)),       # elbow driven high behind
}
ARM_POSE = (("back", "fwd"), ("bmid", "fmid"), ("mid", "mid"), ("fwd", "back"))
LOGO_FRAME = 7                 # flight, near knee driving: the classic sprint silhouette


def frame_parts(i):
    """near leg, far leg, near arm, far arm, vertical offset for frame i."""
    _, A, B, dy = POSES[i % 4]
    na, fa = ARM_POSE[i % 4]
    if i >= 4:
        A, B, na, fa = B, A, fa, na
    return A, B, ARMS[na], ARMS[fa], dy


# ---------------- small sprite: crisp pixel strokes ----------------
def stroke(g, a, b, color, width, dy):
    (x0, y0), (x1, y1) = a, b
    n = max(abs(x1 - x0), abs(y1 - y0)) * 2 + 1
    steep = abs(y1 - y0) >= abs(x1 - x0)
    for k in range(n + 1):
        t = k / n
        x = int(round(x0 + (x1 - x0) * t))
        y = int(round(y0 + (y1 - y0) * t)) + dy
        for d in range(width):
            px, py = (x + d, y) if steep else (x, y + d)
            if 0 <= px < SPRITE_W and 0 <= py < SPRITE_H:
                g[py][px] = color


def sprite(i):
    return draw_pose(*frame_parts(i))


# Jump poses for Arcade (same body, limbs placed for a leap):
#   rise = push-off, back leg long, front knee driving, arms swinging up
#   tuck = top of the jump, both knees pulled up, arms high
#   land = coming down, front leg reaching for the ground, arms out
JUMPS = (
    (((8, 9), (6, 12), (3, 15), ((2, 16), (3, 16))),      # rise: near leg pushes
     ((9, 9), (13, 10), (13, 14), ((14, 14), (15, 14))),  # far knee drives
     ((12, 6), (14, 8), (16, 6)), ((10, 6), (8, 7), (6, 6)), 0),
    (((9, 9), (13, 10), (11, 13), ((11, 14), (12, 14))),  # tuck: near knee high
     ((8, 9), (11, 11), (8, 13), ((7, 13), (8, 13))),     # far knee tucked
     ((12, 6), (14, 6), (16, 4)), ((10, 6), (8, 5), (7, 3)), 0),
    (((9, 9), (12, 12), (13, 15), ((13, 16), (14, 16))),  # land: near leg reaches
     ((8, 9), (7, 12), (5, 14), ((4, 15), (5, 15))),
     ((12, 6), (14, 7), (16, 6)), ((10, 6), (7, 6), (5, 5)), 0),
)


# Sitting by the campfire (Campfire style, runner mascot), hand-placed pixels:
# same head and forward lean, sat on a log, both hands held out to the fire.
# 4 white, 5 dim white (far arm), 3 red (near leg), 2 maroon (far leg).
SIT_ROWS = (
    "..................",
    "..................",
    "..................",
    "..................",
    "............44....",
    "...........4444...",
    "...........4444...",
    "............44....",
    "...........44.555.",
    "..........444.....",
    ".........4444444..",
    "........44........",
    "........3333333...",
    "........2222223...",
    ".............33...",
    ".............33...",
    "............4444..",
)


def draw_pose(near, far, narm, farm, dy):
    g = [[0] * SPRITE_W for _ in range(SPRITE_H)]

    def leg(L, c, shoe_c):
        hip, knee, ankle, shoe = L
        stroke(g, (hip[0], hip[1] + dy), knee, c, 2, 0)   # hips bob, feet stay put
        stroke(g, knee, ankle, c, 2, 0)
        for x, y in shoe:
            if 0 <= x < SPRITE_W and 0 <= y < SPRITE_H:
                g[y][x] = shoe_c

    def arm(A, c):
        stroke(g, A[0], A[1], c, 1, dy)
        stroke(g, A[1], A[2], c, 1, dy)

    arm(farm, FAR)                       # back to front
    leg(far, MAROON, FAR)
    for y, row in enumerate(BODY):
        for x, ch in enumerate(row):
            if ch == "#" and 0 <= y + dy < SPRITE_H:
                g[y + dy][x] = WHITE
    for x, y in HIPS:
        g[y + dy][x] = RED
    leg(near, RED, WHITE)
    arm(narm, WHITE)
    return g


def sprite_frames():
    return [sprite(i) for i in range(FRAMES)]


# ---------------- logo runner: same pose, bigger, smooth ----------------
SS, COVER = 8, 0.45
W_TORSO, W_LEG, W_ARM, W_SHOE = 2.2, 1.9, 1.3, 1.4


def seg_dist(px, py, a, b):
    (ax, ay), (bx, by) = a, b
    dx, dy = bx - ax, by - ay
    L = dx * dx + dy * dy
    t = 0 if L == 0 else max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / L))
    return math.hypot(px - ax - t * dx, py - ay - t * dy)


def render_smooth(g, i, at, k, near_c, far_c, outline_c):
    """Frame i's skeleton as thick capsules, scaled by k, placed at `at`.
    Far-side arm/leg get far_c (depth), everything else near_c, and a dark
    outline separates the figure from what's behind it."""
    near, far, narm, farm, dy = frame_parts(i)
    c = lambda p: (at[0] + (p[0] + 0.5) * k, at[1] + (p[1] + 0.5 + dy) * k)
    raw = lambda p: (at[0] + p[0] * k, at[1] + (p[1] + dy) * k)

    def limbs(L, A):
        hip, knee, ankle, shoe = L
        return [(c(hip), c(knee), W_LEG), (c(knee), c(ankle), W_LEG),
                (c(shoe[0]), c(shoe[-1]), W_SHOE),
                (c(A[0]), c(A[1]), W_ARM), (c(A[1]), c(A[2]), W_ARM)]

    layers = [(far_c, limbs(far, farm)),
              (near_c, [(raw(HIP_C), raw(SHOULDER_C), W_TORSO),
                        (raw(HEAD_C), raw(HEAD_C), HEAD_R * 2)] + limbs(near, narm))]
    H, W = len(g), len(g[0])
    mask = [[False] * W for _ in range(H)]
    for color, caps in layers:
        for y in range(H):
            for x in range(W):
                if not g[y][x]:
                    continue                 # only inside the badge
                hit = 0
                for sy in range(SS):
                    for sx in range(SS):
                        qx, qy = x + (sx + .5) / SS, y + (sy + .5) / SS
                        for a, b, w in caps:
                            if seg_dist(qx, qy, a, b) <= w * k / 2:
                                hit += 1
                                break
                if hit / (SS * SS) >= COVER:
                    g[y][x] = color
                    mask[y][x] = True
    for y in range(H):                       # outline
        for x in range(W):
            if g[y][x] and not mask[y][x] and any(
                    0 <= y + v < H and 0 <= x + u < W and mask[y + v][x + u]
                    for u, v in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                g[y][x] = outline_c


LOGO_SCALE, LOGO_AT = 1.4, (38.5, 0.4)


def logo():
    W, H = 64, 24
    g = [[0] * W for _ in range(H)]

    def inside(x, y, r=5):
        cx = min(max(x, r), W - 1 - r)
        cy = min(max(y, r), H - 1 - r)
        return (x - cx) ** 2 + (y - cy) ** 2 <= r * r + 1

    for y in range(H):                          # badge: red -> black gradient
        for x in range(W):
            if inside(x, y):
                g[y][x] = 7 + min(5, int(y / H * 6))
    for y, x0, x1 in ((4, 26, 44), (10, 30, 47), (13, 22, 46), (16, 34, 44), (19, 28, 42)):
        for x in range(x0, x1):
            if g[y][x]:
                g[y][x] = LOGO_SPEED
    render_smooth(g, LOGO_FRAME, LOGO_AT, LOGO_SCALE, WHITE, FAR, LOGO_SHADOW)
    M = ["##.......##", "###.....###", "####...####", "##.##.##.##", "##..###..##",
         "##...#...##"] + ["##.......##"] * 6
    A = ["....##....", "...####...", "...####...", "..##..##..", "..##..##..", ".##....##.",
         ".##....##.", ".########.", "##......##", "##......##", "##......##", "##......##"]
    D = ["#######...", "########..", "##....###.", "##.....##.", "##......##", "##......##",
         "##......##", "##......##", "##.....##.", "##....###.", "########..", "#######..."]
    pix, x = set(), 3
    for L in (M, A, D):
        for r, row in enumerate(L):
            for c, ch in enumerate(row):
                if ch == "#":
                    pix.add((x + c, 6 + r))
        x += len(L[0]) + 3
    for px, py in pix:                          # drop shadow, like the icon bevel
        q = (px + 1, py + 1)
        if q not in pix and q[0] < W and q[1] < H and g[q[1]][q[0]] not in (0, WHITE, FAR):
            g[q[1]][q[0]] = LOGO_SHADOW
    for px, py in pix:
        g[py][px] = WHITE
    return g


# ================= FLAMEY (from the app's FlameBuddyFigure.swift) =================

FSS = 12   # supersample


def bez(p0, c1, c2, p1, n=24):
    out = []
    for i in range(n + 1):
        t = i / n
        a = (1 - t) ** 3
        b = 3 * (1 - t) ** 2 * t
        c = 3 * (1 - t) * t * t
        d = t ** 3
        out.append((a * p0[0] + b * c1[0] + c * c2[0] + d * p1[0],
                    a * p0[1] + b * c1[1] + c * c2[1] + d * p1[1]))
    return out


def quad(p0, c, p1, n=24):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t * t * p1[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t * t * p1[1])
            for t in (i / n for i in range(n + 1))]


def outer_path(rx, ry, w, h, wb):
    X = lambda v: rx + v * w
    Y = lambda v: ry + v * h
    P = lambda a, b: (X(a), Y(b))
    pts = []
    pts += bez(P(0.50 + wb * .10, .02), P(.35 + wb, .13), P(.27 - wb * .3, .25), P(.28 + wb * .35, .42))
    pts += bez(P(.28 + wb * .35, .42), P(.20, .36), P(.15, .46), P(.18 - wb * .2, .56))
    pts += bez(P(.18 - wb * .2, .56), P(.12, .61), P(.08, .66), P(.08, .72))
    pts += bez(P(.08, .72), P(.08, .90), P(.24, .98), P(.50, .98))
    pts += bez(P(.50, .98), P(.76, .98), P(.92, .90), P(.92, .72))
    pts += bez(P(.92, .72), P(.92, .55), P(.75 + wb, .48), P(.69 + wb * .25, .35))
    pts += bez(P(.69 + wb * .25, .35), P(.78, .20), P(.62, .11), P(.50 + wb * .10, .02))
    return pts


def inner_path(rx, ry, w, h, wb):
    X = lambda v: rx + v * w
    Y = lambda v: ry + v * h
    P = lambda a, b: (X(a), Y(b))
    pts = []
    pts += bez(P(.52 + wb * .20, .02), P(.35, .20), P(.37, .34), P(.32, .48))
    pts += bez(P(.32, .48), P(.22, .54), P(.18, .62), P(.18, .72))
    pts += bez(P(.18, .72), P(.18, .90), P(.34, .98), P(.50, .98))
    pts += bez(P(.50, .98), P(.66, .98), P(.82, .90), P(.82, .72))
    pts += bez(P(.82, .72), P(.82, .56), P(.62, .52), P(.60 + wb * .22, .38))
    pts += bez(P(.60 + wb * .22, .38), P(.72, .24), P(.60, .14), P(.52 + wb * .20, .02))
    return pts


def grad(colors, t):
    t = min(max(t, 0), 1) * (len(colors) - 1)
    i = min(int(t), len(colors) - 2)
    f = t - i
    return tuple(colors[i][k] * (1 - f) + colors[i + 1][k] * f for k in range(3))


OUTER = [(1, .95, .32), (1, .647, 0), (1, .22, .10)]      # healthy
INNER = [(1, .98, .44), (1, .65, .12)]
INNER_A = 0.82
EYE = (.20, .07, .04)
MOUTH = (.24, .04, .04)
TONGUE = (1, .42, .34)
TONGUE_LED = (1, .36, .52)   # pinker on the panel so it reads against orange


def wobble(p):
    return (math.sin(p) + 0.45 * math.sin(p * 2.3 + 1.7)) * 0.045


def render_rgb(S, wb=0.0, blink=False, face=True):
    """RGBA image of Flamey in an S x S square (app geometry), at S*FSS."""
    Z = S * FSS
    img = np.zeros((Z, Z, 4))
    # body frame: 0.82S x S, centred
    bw, bh = 0.82 * Z, Z
    bx, by = (Z - bw) / 2, 0
    m = Image.new("L", (Z, Z), 0)
    ImageDraw.Draw(m).polygon(outer_path(bx, by, bw, bh, wb), fill=255)
    om = np.asarray(m) > 127
    ys = np.arange(Z)[:, None] / Z
    for y in range(Z):
        c = grad(OUTER, y / Z)
        img[y, om[y], :3] = c
        img[y, om[y], 3] = 1
    # inner flame: 0.54S x 0.58S frame, centre +0.13S
    iw, ih = 0.54 * Z, 0.58 * Z
    ix, iy = (Z - iw) / 2, Z / 2 + 0.13 * Z - ih / 2
    m = Image.new("L", (Z, Z), 0)
    ImageDraw.Draw(m).polygon(inner_path(ix, iy, iw, ih, -wb * 0.6), fill=255)
    im_ = np.asarray(m) > 127
    for y in range(Z):
        sel = im_[y] & om[y]
        if sel.any():
            c = np.array(grad(INNER, (y - iy) / ih))
            img[y, sel, :3] = img[y, sel, :3] * (1 - INNER_A) + c * INNER_A
    if not face:
        return img
    d = Image.new("RGBA", (Z, Z), (0, 0, 0, 0))
    dr = ImageDraw.Draw(d)
    fy = Z / 2 + 0.18 * Z                      # face centre
    for sx in (-1, 1):                         # eyes
        ex = Z / 2 + sx * 0.145 * Z
        ew = 0.12 * Z
        eh = 0.018 * Z if blink else 0.155 * Z
        dr.ellipse([ex - ew / 2, fy - eh / 2, ex + ew / 2, fy + eh / 2],
                   fill=tuple(int(v * 255) for v in EYE) + (255,))
        if not blink:
            gx, gy = ex - ew / 2 + 0.024 * Z, fy - eh / 2 + 0.030 * Z
            r = 0.0175 * Z
            dr.ellipse([gx - r + r, gy - r + r, gx + r + r, gy + r + r], fill=(255, 255, 255, 235))
    # smile: 0.27S x 0.115S at face centre +0.13S
    mw, mh = 0.27 * Z, 0.115 * Z
    mx, my = Z / 2 - mw / 2, fy + 0.13 * Z - mh / 2
    sm = quad((mx, my), (mx + mw / 2, my + mh * 0.62), (mx + mw, my))
    sm += bez((mx + mw, my), (mx + mw - mw * .06, my + mh + mh * .34),
              (mx + mw * .06, my + mh + mh * .34), (mx, my))
    mm = Image.new("L", (Z, Z), 0)
    ImageDraw.Draw(mm).polygon(sm, fill=255)
    dr.polygon(sm, fill=tuple(int(v * 255) for v in MOUTH) + (255,))
    tw_, th_ = 0.11 * Z, 0.045 * Z
    tong = Image.new("RGBA", (Z, Z), (0, 0, 0, 0))
    ImageDraw.Draw(tong).rounded_rectangle([Z / 2 - tw_ / 2, my + mh - th_, Z / 2 + tw_ / 2, my + mh],
                                           radius=th_ / 2, fill=tuple(int(v * 255) for v in TONGUE) + (255,))
    tong = np.asarray(tong).copy()
    tong[np.asarray(mm) < 128] = 0
    face = np.asarray(d).astype(float) / 255
    a = face[..., 3:4]
    img[..., :3] = img[..., :3] * (1 - a) + face[..., :3] * a
    t = tong.astype(float) / 255
    ta = t[..., 3:4]
    img[..., :3] = img[..., :3] * (1 - ta) + t[..., :3] * ta
    return img


# LED palette: (sim index, colour shown) - Flamey's own colours
LED = {
    16: (1.00, .95, .32),    # top yellow
    17: (1.00, .80, .16),    # yellow-orange
    18: (1.00, .62, .05),    # orange
    19: (1.00, .40, .07),    # deep orange
    23: (1.00, .97, .55),    # inner glow
    24: (1.00, .25, .10),    # base red-orange
    21: (0.0, 0.0, 0.0),     # eyes / mouth (off pixel)
    20: TONGUE_LED,
    22: (.95, .88, .81),     # soft warm-white catch-light
}
DIM = 0.55


def flamey_palette_entries():
    out = {}
    for k, (r, g, b) in LED.items():
        s = DIM
        out[k] = (int(r * 255 * s) << 16) | (int(g * 255 * s) << 8) | int(b * 255 * s)
    return out


def flamey_sprite(H, phase=0.0, blink=False):
    """Panel sprite: H rows tall (the figure square), width trimmed.
    Body/inner flame/colours come from the app geometry; the face is a
    hand-placed pixel template at the app's proportions (at this size a
    straight shrink merges the eyes into the grin)."""
    img = render_rgb(H, wobble(phase), blink, face=H not in FACES)
    Z = H * FSS
    out = []
    feat = {21: np.array(EYE), 20: np.array(TONGUE), 22: np.array((1, 1, 1))}
    for y in range(H):
        row = []
        for x in range(H):
            blk = img[y * FSS:(y + 1) * FSS, x * FSS:(x + 1) * FSS]
            a = blk[..., 3].mean()
            if a < (0.62 if y >= H - 2 else 0.5):
                row.append(0)
                continue
            px = blk[blk[..., 3] > 0][:, :3]
            lum = px.mean(1)
            dark = (lum < 0.25).mean()
            white = (px.min(1) > 0.9).mean()
            pink = ((np.abs(px - np.array(TONGUE)).sum(1)) < 0.15).mean()
            if white > 0.30 and H >= 20:
                row.append(22)
            elif pink > 0.35 and dark < 0.5:
                row.append(20)
            elif dark > 0.40:
                row.append(21)
            else:
                c = px[lum >= 0.25].mean(0) if (lum >= 0.25).any() else px.mean(0)
                best = min((k for k in LED if k not in (20, 21, 22)),
                           key=lambda k: sum((c[i] - LED[k][i]) ** 2 for i in range(3)))
                row.append(best)
        out.append(row)
    # trim empty columns
    cols = [x for x in range(H) if any(out[y][x] for y in range(H))]
    x0, x1 = min(cols), max(cols) + 1
    out = [r[x0:x1] for r in out]
    face = FACES.get(H)
    if face:
        ry = int(H * 0.80)
        lit = [x for x in range(len(out[0])) if out[ry][x]]
        cx = (min(lit) + max(lit)) / 2
        rows = face["blink" if blink else "open"]
        fx = int(round(cx - (len(rows[0]) - 1) / 2))
        for yy, row in enumerate(rows):
            for xx, ch in enumerate(row):
                if ch != "." and 0 <= fx + xx < len(out[0]):
                    out[face["y"] + yy][fx + xx] = {"E": 21, "W": 22, "P": 20}[ch]
        out = finish(out, H)
    return out


# Faces at the app's proportions: eyes 0.12 x 0.155 of the figure at
# +-0.145 from centre, grin 0.27 wide just below, tongue in the grin,
# white catch-light top-left of each eye. One clear row between eyes and grin.
FACES = {
    # Big dark eyes (the app's 0.12 x 0.155 of his size) with ONE soft
    # warm-white catch-light on the upper-left edge, and a clean curved
    # smile that sits well inside his body (no tongue: at panel size it
    # reads as a smudge). One clear row between eyes and smile.
    17: {"y": 9,
         # too small for a readable tongue: a clean, clear smile instead
         "open": ["EE...EE",
                  "WE...WE",
                  "EE...EE",
                  ".......",
                  ".E...E.",
                  "..EEE.."],
         "blink": [".......",
                   ".......",
                   "EE...EE",
                   ".......",
                   ".E...E.",
                   "..EEE.."]},
    24: {"y": 13,
         "open": ["EEE....EEE",
                  "WEE....WEE",
                  "EEE....EEE",
                  "EEE....EEE",
                  "..........",
                  ".E......E.",
                  "..E....E..",
                  "...EEEE..."],
         "blink": ["..........",
                   "..........",
                   "EEE....EEE",
                   "..........",
                   "..........",
                   ".E......E.",
                   "..E....E..",
                   "...EEEE..."]},
}
DEEPER = {16: 17, 23: 17, 17: 18, 18: 19, 19: 24, 24: 24}


def finish(fr, H):
    """Even orange behind the face (so eyes and grin pop instead of a bright
    stripe running between them), then edge pixels one tone deeper so the
    flat colour bands read as a round, soft body."""
    out = [list(r) for r in fr]
    y0 = FACES[H]["y"] - 1
    for y in range(y0, len(out)):
        for x, v in enumerate(out[y]):
            if v in (16, 23, 17):
                out[y][x] = 18
    H_, W = len(out), len(out[0])
    shaded = [list(r) for r in out]
    for y in range(H_):
        for x in range(W):
            v = out[y][x]
            if v in DEEPER and any(not (0 <= x + u < W and 0 <= y + w < H_) or out[y + w][x + u] == 0
                                   for u, w in ((1, 0), (-1, 0), (0, 1))):
                shaded[y][x] = DEEPER[v]
    return shaded


def add_glints(g):
    """White catch-light in the top-left of each eye, at every size, so he
    always looks friendly (the app draws one on every open eye)."""
    H = len(g)
    seen = set()
    for y in range(int(H * 0.40), int(H * 0.80)):
        for x in range(len(g[0])):
            if g[y][x] == 21 and (x, y) not in seen:
                # flood the eye blob
                stack, blob = [(x, y)], []
                while stack:
                    p = stack.pop()
                    if p in seen:
                        continue
                    px, py = p
                    if not (0 <= py < H and 0 <= px < len(g[0])) or g[py][px] != 21:
                        continue
                    seen.add(p)
                    blob.append(p)
                    stack += [(px + 1, py), (px - 1, py), (px, py + 1), (px, py - 1)]
                if len(blob) < 3 or any(g[py][px] == 22 for px, py in blob):
                    continue
                if max(py for _, py in blob) - min(py for _, py in blob) < 1:
                    continue                 # a flat smile, not an eye
                top = min(py for _, py in blob)
                left = min(px for px, py in blob if py == top)
                g[top][left] = 22
    # neighbours that already had a glint count too
    return g


def flamey_frames(H):
    """8 flicker frames + 1 blink frame, like the app's 12 fps loop."""
    out = []
    for i in range(8):
        out.append(flamey_sprite(H, i / 8 * 2 * math.pi))
    out.append(flamey_sprite(H, 0.0, blink=True))
    W = max(len(f[0]) for f in out)
    return [[r + [0] * (W - len(r)) for r in f] for f in out]


B32 = "0123456789abcdefghijklmnopqrstuv"


def rows(g):
    return ["".join(B32[v] for v in r) for r in g]


if __name__ == "__main__":
    out = ['# GENERATED by build_art.py - edit the model there, not this file.',
           '# Runner, Flamey (8 frames + blink) and logo; one base-32 digit per pixel.',
           'RUN_W, RUN_H = %d, %d' % (SPRITE_W, SPRITE_H), 'RUNNER = (']
    jumps = [draw_pose(*j) for j in JUMPS]
    for f in sprite_frames():
        out.append("    (")
        out += ['        "%s",' % r for r in rows(f)]
        out.append("    ),")
    out.append(")")
    out.append("RUN_JUMP = (   # rise, tuck, land")
    for f in jumps:
        out.append("    (")
        out += ['        "%s",' % r for r in rows(f)]
        out.append("    ),")
    out.append(")")
    out.append("RUN_SIT = (")
    out += ['    "%s",' % r.replace(".", "0") for r in SIT_ROWS]
    out.append(")")
    for name, H in (("FLAMEY_M", 17), ("FLAMEY_L", 24)):
        out.append("%s = (" % name)
        for f in flamey_frames(H):
            out.append("    (")
            out += ['        "%s",' % r for r in rows(f)]
            out.append("    ),")
        out.append(")")
    out.append("LOGO = (")
    out += ['    "%s",' % r for r in rows(logo())]
    out.append(")")
    open("mad/art.py", "w").write("\n".join(out) + "\n")
    print("wrote mad/art.py")
