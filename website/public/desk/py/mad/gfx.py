# Mile A Day desk counter - graphics: palette, fonts, icons, drawing helpers.
# (Compiled to mad/gfx.mpy for the board.)
import displayio
import bitmaptools

DEFAULT_URL = "https://mad.mindgoblin.tech/public/stats"
FEED_URL = "https://mad.mindgoblin.tech/display/feed"
REFRESH_SECONDS = 60     # public stats: the API caches for 60 s
FEED_SECONDS = 15        # personal feed (needs MAD_DISPLAY_KEY): the phone remote's taps land fast

# ---------- colors ----------
# Kept dim on purpose: the whole panel runs off one USB-C supply. Pure reds
# (any blue turns pink on this panel); white warmed up (blue LEDs run hot).
BLACK, MAROON_DIM, MAROON, RED, WHITE, FAR, SPARK = range(7)
palette = displayio.Palette(32)
palette[BLACK] = 0x000000
palette[MAROON_DIM] = 0x180000   # dividers
palette[MAROON] = 0x480000       # deep red: accents, underline
palette[RED] = 0x980000          # Mile A Day red: labels, highlights
palette[WHITE] = 0xA09070        # warm white: numbers, runner
palette[FAR] = 0x584C3C          # runner's far arm/leg: dim white (depth)
palette[SPARK] = 0xFFE0C0        # bright sparkle
# 7..15: startup logo (badge gradient, runner, speed lines, letter shadow)
for _i, _c in enumerate((0x500000, 0x400000, 0x300000, 0x220000, 0x140000,
                         0x0A0000, 0x902024, 0x3C0C0E, 0x080000)):
    palette[7 + _i] = _c
# 16..24: Flamey, in his app colours (healthy flame), dimmed for the panel
FL_YELLOW, FL_GOLD, FL_ORANGE, FL_DEEP, FL_TONGUE, FL_EYE, FL_GLINT, FL_GLOW, FL_BASE = range(16, 25)
for _k, _c in ((16, 0x8C852C), (17, 0x8C7016), (18, 0x8C5607), (19, 0x8C3809),
               (20, 0x8C3248), (21, 0x000000), (22, 0x857C72), (23, 0x8C884D),
               (24, 0x8C230E)):
    palette[_k] = _c
# 25..26: water drops (Flamey's Arcade obstacles)
WATER, WATER_LIGHT = 25, 26
palette[WATER] = 0x082050
palette[WATER_LIGHT] = 0x285890
GREEN = 27                       # "mile done" check
palette[GREEN] = 0x0C5A14
LOG = 28                         # campfire logs
palette[LOG] = 0x3C1806
# Streak heatmap: light for a mile, deeper red the further you went
# (MAROON is the deepest step). 29 and 31 are the two in-between shades.
HEAT_L = 29
palette[HEAT_L] = 0xC85840       # light coral: about a mile
HEAT_D = 31
palette[HEAT_D] = 0x680000       # deep red: 3-5 miles

PURPLE = 30                      # Halloween bats and candy wrappers
palette[PURPLE] = 0x401060

_BASE = [palette[_i] for _i in range(32)]
_ORIG = list(_BASE)
_DIM = [1.0]

# St. Patrick's Day: Flamey's flame (and every gold accent) turns green.
GREEN_THEME = {16: 0x58B030, 17: 0x3C9424, 18: 0x24781C, 19: 0x145C14, 23: 0x78C850,
               24: 0x0C4410}


def set_theme(overrides):
    """Swap some base colours for a holiday (None = the normal colours)."""
    for i, c in enumerate(_ORIG):
        _BASE[i] = c
    for i, c in (overrides or {}).items():
        _BASE[i] = c
    set_dim(_DIM[0])


def set_dim(f):
    """Scale every colour (night mode). Lit channels never round to black:
    the panel has 16 levels per channel, so keep at least the first one."""
    _DIM[0] = f
    for i, c in enumerate(_BASE):
        out = 0
        for sh in (16, 8, 0):
            v = (c >> sh) & 255
            if v:
                v = max(0x10, int(v * f))
            out |= v << sh
        palette[i] = out

# ---------- fonts ----------
# Fonts packed for memory: (characters, rows per glyph, data) where each glyph
# is one width byte then one byte of pixel bits per row (generated from the
# "#." drawings in the git history; a dict of tuples cost ~10 KB more RAM).
F5 = ("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ,.!-#/?:'+%_", 7, b'\x05\x0e\x11\x11\x1f\x11\x11\x11\x05\x1e\x11\x11\x1e\x11\x11\x1e\x05\x0e\x11\x10\x10\x10\x11\x0e\x05\x1e\x11\x11\x11\x11\x11\x1e\x05\x1f\x10\x10\x1e\x10\x10\x1f\x05\x1f\x10\x10\x1e\x10\x10\x10\x05\x0e\x11\x10\x17\x11\x11\x0f\x05\x11\x11\x11\x1f\x11\x11\x11\x03\x07\x02\x02\x02\x02\x02\x07\x05\x07\x02\x02\x02\x02\x12\x0c\x05\x11\x12\x14\x18\x14\x12\x11\x05\x10\x10\x10\x10\x10\x10\x1f\x05\x11\x1b\x15\x15\x11\x11\x11\x05\x11\x11\x19\x15\x13\x11\x11\x05\x0e\x11\x11\x11\x11\x11\x0e\x05\x1e\x11\x11\x1e\x10\x10\x10\x05\x0e\x11\x11\x11\x15\x12\r\x05\x1e\x11\x11\x1e\x14\x12\x11\x05\x0f\x10\x10\x0e\x01\x01\x1e\x05\x1f\x04\x04\x04\x04\x04\x04\x05\x11\x11\x11\x11\x11\x11\x0e\x05\x11\x11\x11\x11\x11\n\x04\x05\x11\x11\x11\x15\x15\x15\n\x05\x11\x11\n\x04\n\x11\x11\x05\x11\x11\n\x04\x04\x04\x04\x05\x1f\x01\x02\x04\x08\x10\x1f\x05\x0e\x11\x11\x11\x11\x11\x0e\x05\x04\x0c\x04\x04\x04\x04\x0e\x05\x0e\x11\x01\x02\x04\x08\x1f\x05\x1f\x02\x04\x02\x01\x11\x0e\x05\x02\x06\n\x12\x1f\x02\x02\x05\x1f\x10\x1e\x01\x01\x11\x0e\x05\x06\x08\x10\x1e\x11\x11\x0e\x05\x1f\x01\x02\x04\x08\x08\x08\x05\x0e\x11\x11\x0e\x11\x11\x0e\x05\x0e\x11\x11\x0f\x01\x02\x0c\x02\x00\x00\x00\x00\x00\x00\x00\x02\x00\x00\x00\x00\x00\x01\x02\x01\x00\x00\x00\x00\x00\x00\x01\x01\x01\x01\x01\x01\x01\x00\x01\x03\x00\x00\x00\x07\x00\x00\x00\x05\n\n\x1f\n\x1f\n\n\x05\x01\x01\x02\x04\x08\x10\x10\x05\x0e\x11\x01\x02\x04\x00\x04\x01\x00\x00\x01\x00\x01\x00\x00\x01\x01\x01\x00\x00\x00\x00\x00\x05\x00\x04\x04\x1f\x04\x04\x00\x05\x19\x19\x02\x04\x08\x13\x13\x05\x00\x00\x00\x00\x00\x00\x1f')  # 5x7, proportional
F3 = ("ACDEIKLMORSTUWYV0123456789BFGHJNPQXZ-!:()'_/,. ?+", 5, b'\x03\x02\x05\x07\x05\x05\x03\x03\x04\x04\x04\x03\x03\x06\x05\x05\x05\x06\x03\x07\x04\x06\x04\x07\x01\x01\x01\x01\x01\x01\x03\x05\x05\x06\x05\x05\x03\x04\x04\x04\x04\x07\x03\x05\x07\x05\x05\x05\x03\x02\x05\x05\x05\x02\x03\x06\x05\x06\x05\x05\x03\x03\x04\x02\x01\x06\x03\x07\x02\x02\x02\x02\x03\x05\x05\x05\x05\x07\x03\x05\x05\x05\x07\x05\x03\x05\x05\x02\x02\x02\x03\x05\x05\x05\x05\x02\x03\x07\x05\x05\x05\x07\x03\x02\x06\x02\x02\x07\x03\x06\x01\x02\x04\x07\x03\x06\x01\x02\x01\x06\x03\x05\x05\x07\x01\x01\x03\x07\x04\x06\x01\x06\x03\x03\x04\x07\x05\x07\x03\x07\x01\x02\x02\x02\x03\x07\x05\x07\x05\x07\x03\x07\x05\x07\x01\x06\x03\x06\x05\x06\x05\x06\x03\x07\x04\x06\x04\x04\x03\x03\x04\x05\x05\x03\x03\x05\x05\x07\x05\x05\x03\x01\x01\x01\x05\x02\x03\x05\x07\x07\x07\x05\x03\x06\x05\x06\x04\x04\x03\x02\x05\x05\x07\x03\x03\x05\x05\x02\x05\x05\x03\x07\x01\x02\x04\x07\x03\x00\x00\x07\x00\x00\x01\x01\x01\x01\x00\x01\x01\x00\x01\x00\x01\x00\x02\x01\x02\x02\x02\x01\x02\x02\x01\x01\x01\x02\x01\x01\x01\x00\x00\x00\x03\x00\x00\x00\x00\x07\x03\x01\x01\x02\x04\x04\x01\x00\x00\x00\x01\x01\x01\x00\x00\x00\x00\x01\x01\x00\x00\x00\x00\x00\x03\x06\x01\x02\x00\x02\x03\x00\x02\x07\x02\x00')  # 3x5, small labels
FB = ('0123456789KM,. ', 10, b'\x07>cccccccc>\x07\x0c\x1c<\x0c\x0c\x0c\x0c\x0c\x0c?\x07>c\x03\x03\x06\x0c\x180`\x7f\x07>c\x03\x03\x1e\x03\x03\x03c>\x07\x06\x0e\x1e6f\x7f\x06\x06\x06\x06\x07\x7f``~\x03\x03\x03\x03c>\x07\x1e0``~cccc>\x07\x7f\x03\x03\x06\x0c\x0c\x18\x18\x18\x18\x07>ccc>cccc>\x07>cccc?\x03\x03\x06<\x07cflxpxlfcc\x07cw\x7fkcccccc\x02\x00\x00\x00\x00\x00\x00\x00\x03\x01\x02\x02\x00\x00\x00\x00\x00\x00\x00\x00\x03\x03\x03\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00')  # 7x10 bold digits for the hero numbers


def glyph(font, ch):
    """(width, offset of its first row in font[2]); unknown -> a space."""
    i = font[0].find(ch)
    if i < 0:
        i = font[0].find(" ")
    o = i * (font[1] + 1)
    return font[2][o], o + 1

def text_width(text, font=F5, gap=1):
    w = 0
    for ch in text:
        w += glyph(font, ch)[0] + gap
    return max(0, w - gap)

def draw_text(bmp, x, y, text, color, font=F5, gap=1, cx0=0, cx1=None):
    """Draw text with its top-left at (x, y); returns x after the text.
    Only columns cx0..cx1-1 are painted (a scrolling line's window)."""
    W, H = (bmp.width if cx1 is None else min(cx1, bmp.width)), bmp.height
    h, data = font[1], font[2]
    for ch in text:
        w, o = glyph(font, ch)
        for py in range(h):
            bits = data[o + py]
            yy = y + py
            if bits and 0 <= yy < H:
                for px in range(w):
                    if bits & (1 << (w - 1 - px)):
                        xx = x + px
                        if cx0 <= xx < W:
                            bmp[xx, yy] = color
        x += w + gap
    return x

def ink(text, font=F5, gap=1):
    """(first lit column, last lit column + 1) of the rendered text."""
    x, lo, hi = 0, None, 0
    for ch in text:
        w, o = glyph(font, ch)
        m = 0
        for r in font[2][o:o + font[1]]:
            m |= r
        if m:
            for px in range(w):
                if m & (1 << (w - 1 - px)):
                    lo = x + px if lo is None else lo
                    hi = max(hi, x + px + 1)
        x += w + gap
    return (lo or 0), hi

def draw_box(bmp, x0, x1, y, text, color, font=F5):
    """Center the lit pixels of `text` between columns x0..x1-1."""
    lo, hi = ink(text, font)
    draw_text(bmp, x0 + (x1 - x0 - (hi - lo)) // 2 - lo, y, text, color, font)

def clock():
    """Seconds, monotonic (time.monotonic on the board; ticks_ms where a
    MicroPython build has no monotonic, like the phone remote's preview)."""
    import time
    try:
        return time.monotonic()
    except AttributeError:
        return time.ticks_ms() / 1000


SCROLL_PX = 18.0          # px per second for a line that doesn't fit


def fit(bmp, x0, x1, y, text, color, font=F5, t=None, small=True):
    """Centre `text` in columns x0..x1-1. Too wide: the small font (one row
    lower, so it stays vertically centred), and if even that doesn't fit, it
    scrolls: shown from its start, glides left to its end, holds, repeats.
    Nothing is ever cut off. Returns the font used."""
    room = x1 - x0
    lo, hi = ink(text, font)
    if hi - lo <= room:
        draw_text(bmp, x0 + (room - (hi - lo)) // 2 - lo, y, text, color, font)
        return font
    if small and font is F5:
        lo, hi = ink(text, F3)
        y += 1
        font = F3
        if hi - lo <= room:
            draw_text(bmp, x0 + (room - (hi - lo)) // 2 - lo, y, text, color, font)
            return font
    if t is None:
        t = clock()
    over = hi - lo - room
    travel = over / SCROLL_PX
    ph = t % (travel + 2.4)
    off = 0 if ph < 1.2 else min(over, int((ph - 1.2) * SCROLL_PX))
    draw_text(bmp, x0 - lo - off, y, text, color, font, cx0=x0, cx1=x1)
    return font


def miles_text(v, room, font=F5, lead=0):
    """The most precise distance that fits `room` px (plus `lead` px for an
    icon): 1.23 MI, 1.2 MI, 1.2, then whole miles."""
    for fmt in ("%.2f MI", "%.1f MI", "%.1f", "%d"):
        txt = fmt % v
        if lead + text_width(txt, font) <= room:
            return txt
    return "%d" % v


def fit_icon(bmp, x0, x1, y, name, text, color, font=F5, t=None, icon_color=None):
    """An icon then text, centred together in x0..x1-1; when both don't fit,
    the text alone (fit() above), so a number is never cut or crowded."""
    iw = ICONS[name][0] + 2
    w = text_width(text, font)
    if iw + w <= x1 - x0:
        x = x0 + (x1 - x0 - iw - w) // 2
        draw_icon(bmp, x, y, name, icon_color if icon_color is not None else RED)
        draw_text(bmp, x + iw, y, text, color, font)
        return
    fit(bmp, x0, x1, y, text, color, font, t)


def draw_centered(bmp, cx, y, text, color, font=F5):
    draw_box(bmp, 0, 64, y, text, color, font)

def blit(dst, src, x, y, x1=0, y1=0, x2=None, y2=None, skip=None):
    """bitmaptools.blit with clipping (the C version rejects off-screen x/y)."""
    x2 = src.width if x2 is None else x2
    y2 = src.height if y2 is None else y2
    if x < 0:
        x1 -= x
        x = 0
    if y < 0:
        y1 -= y
        y = 0
    x2 = min(x2, x1 + dst.width - x)
    y2 = min(y2, y1 + dst.height - y)
    if not (x1 < x2 and y1 < y2 and x < dst.width and y < dst.height):
        return
    if skip is None:
        bitmaptools.blit(dst, src, x, y, x1=x1, y1=y1, x2=x2, y2=y2)
    else:
        try:
            bitmaptools.blit(dst, src, x, y, x1=x1, y1=y1, x2=x2, y2=y2,
                             skip_source_index=skip)
        except TypeError:   # older CircuitPython name
            bitmaptools.blit(dst, src, x, y, x1=x1, y1=y1, x2=x2, y2=y2,
                             skip_index=skip)

def fill(bmp, x1, y1, x2, y2, c):
    x1, y1 = max(0, x1), max(0, y1)
    x2, y2 = min(bmp.width, x2), min(bmp.height, y2)
    if x1 < x2 and y1 < y2:
        bitmaptools.fill_region(bmp, x1, y1, x2, y2, c)


# ---------- icons (7 rows) ----------
def _icon(rows):
    return (len(rows[0]), tuple(int(r.replace("#", "1").replace(".", "0"), 2) for r in rows))

ICONS = {
    "users": _icon(["..#..", ".###.", "..#..", "#####", ".###.", ".#.#.", ".#.#."]),
    "today": _icon(["#.#.#", ".###.", "##.##", "#...#", "##.##", ".###.", "#.#.#"]),
    "miles": _icon(["......", "...##.", "...###", "######", "######", "......", "......"]),
    "active": _icon(["....#", "...##", "#..#.", "##.#.", ".##..", "..#..", "....."]),
    "streak": _icon(["..#..", ".##..", ".###.", "#####", "##.##", "##.##", ".###."]),
    "hypes": _icon(["#.......#", ".#.#.#.#.", "..##.##..", ".###.###.", ".###.###.",
                    "..##.##..", "...#.#..."]),
    "photos": _icon([".....", ".##..", "#####", "#...#", "#.#.#", "#...#", "#####"]),
    "running": _icon(["...##", "...##", ".###.", "#.##.", "..#.#", ".#..#", "#...."]),
    "token": _icon([".###.", "#...#", "#.#.#", "#.#.#", "#.#.#", "#...#", ".###."]),
    "badge": _icon(["#...#", ".#.#.", "..#..", ".###.", "#####", "#####", ".###."]),
    "friends": _icon([".#...#.", "###.###", ".#...#.", "###.###", "###.###", ".#...#.", "#.#.#.#"]),
    "check": _icon([".....", "....#", "...##", "#.##.", "###..", ".#...", "....."]),
    "nudge": _icon(["..#..", "..#..", "..###", "#.###", "#####", ".####", "..##."]),
    "heart": _icon([".....", ".#.#.", "#####", "#####", ".###.", "..#..", "....."]),
}

def icon_width(name):
    return ICONS[name][0]

def draw_icon(bmp, x, y, name, color=RED, scale=1):
    w, rows = ICONS[name]
    if scale > 1:
        for yy, bits in enumerate(rows):
            for xx in range(w):
                if bits & (1 << (w - 1 - xx)):
                    fill(bmp, x + xx * scale, y + yy * scale, x + (xx + 1) * scale,
                         y + (yy + 1) * scale, color)
        return w * scale
    for yy, bits in enumerate(rows):
        for xx in range(w):
            if bits & (1 << (w - 1 - xx)):
                px, py = x + xx, y + yy
                if 0 <= px < bmp.width and 0 <= py < bmp.height:
                    if name == "streak":       # little flame: gold top, orange body
                        bmp[px, py] = FL_GOLD if yy < 3 else FL_ORANGE
                    elif name == "token":      # gold coin
                        bmp[px, py] = FL_GOLD
                    elif name == "check":
                        bmp[px, py] = GREEN
                    else:
                        bmp[px, py] = color
    return w

# ---------- numbers ----------
def commas(n):
    n = int(round(float(n)))
    s, out = str(abs(n)), ""
    while len(s) > 3:
        out = "," + s[-3:] + out
        s = s[:-3]
    return ("-" if n < 0 else "") + s + out

def short(n):
    n = float(n)
    if n < 1000:
        return str(int(round(n)))
    for div, suf in ((1e6, "M"), (1e3, "K")):
        if n >= div:
            v = n / div
            return ("%.1f" % v if v < 10 else str(int(round(v)))) + suf
    return str(int(n))

def num(stats, key):
    try:
        return float(stats.get(key) or 0)
    except (TypeError, ValueError):
        return 0.0

def ease(t):                 # smooth start and stop
    t = 0.0 if t < 0 else (1.0 if t > 1 else t)
    return t * t * (3 - 2 * t)

def ease_out(t):
    t = 0.0 if t < 0 else (1.0 if t > 1 else t)
    return 1 - (1 - t) ** 3

# ---------- art from mad_art.py (one base-32 digit per pixel) ----------
def art_bitmap(rows, w=None, h=None):
    w = w or len(rows[0])
    h = h or len(rows)
    b = displayio.Bitmap(w, h, len(palette))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            v = int(ch, 32)
            if v:
                b[x, y] = v
    return b


def upper_name(s, n=30):
    """A username as the panel fonts can draw it."""
    s = (s or "FRIEND").upper()
    out = "".join(c if (c in F5[0]) else "_" if c in "-." else "" for c in s)
    return (out or "FRIEND")[:n]


# ---------- particles (embers and confetti) ----------
def particles(app, b, dt, spawn=None, gravity=14):
    """[x, y, vx, vy, life, kind]: kind 0 = ember (cools yellow->red),
    1 = confetti (keeps a colour index in slot 6)."""
    if spawn:
        app.particles.append(spawn)
    alive = []
    for p in app.particles:
        p[0] += p[2] * dt
        p[1] += p[3] * dt
        p[3] += gravity * dt
        p[4] -= dt
        x, y = int(p[0]), int(p[1])
        if p[4] > 0 and 0 <= x < 64 and -4 <= y < 32:
            if y >= 0:
                if p[5]:
                    b[x, y] = p[6]
                else:
                    b[x, y] = (FL_YELLOW if p[4] > 1.0 else FL_GOLD if p[4] > 0.6
                               else FL_ORANGE if p[4] > 0.3 else FL_DEEP)
            alive.append(p)
    app.particles = alive
