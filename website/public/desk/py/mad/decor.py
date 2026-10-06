# Mile A Day desk counter - seasonal scenery for every screen.
#   SANTA     (Dec 1-26):  falling snow, Santa's sleigh + Rudolph flying by,
#                          twinkling string lights on the divider lines,
#                          Arcade: presents to jump, ornaments to collect,
#                          snowy ground. Campfire: snow-capped logs.
#   HALLOWEEN (Oct 25-31): bats flapping by, a moon over the sky scenes,
#                          candy-corn divider lines, Arcade: pumpkins and
#                          tombstones to jump, wrapped candy to collect.
#   NEWYEAR   (Dec 31-Jan 1): little fireworks popping in the background.
# Background bits (snow, bats, sleigh, fireworks, moon) are painted only on
# black pixels, so numbers and words always stay clear in front of them.
import math
from mad.gfx import (BLACK, MAROON_DIM, MAROON, RED, WHITE, FAR, GREEN, LOG, PURPLE, FL_TONGUE,
                     FL_YELLOW, FL_GOLD, FL_ORANGE, FL_DEEP, fill)

SLEIGH = (            # moving right: Santa in his sleigh, reins, Rudolph
    "...........A.A.",
    "..R........AB..",
    ".RW........BBBN",
    "RRRRFFFFBBBBB..",
    "YYYY....B...B..",
)
SLEIGH_C = {"B": FAR, "A": FL_DEEP, "R": RED, "W": WHITE, "F": MAROON, "Y": FL_GOLD, "N": RED}
BAT = (("B.....B", "BB.B.BB", "..BBB.."),       # wings up
       (".......", ".BBBBB.", "B.BBB.B"))       # wings down
PRESENT = ("..Y..", "XXYXX", "XXYXX", "XXYXX")
PUMPKIN = ("..G..", ".OOO.", "OOOOO", ".OOO.")
TOMB = (".FFF.", "FFFFF", "FDFDF", "FFFFF")
CANDY = ("P...P", "POOOP", "P...P")
# Holiday friends (the morning greeting chase, and Arcade collectibles).
HEART = (".RR.RR.", "RRRRRRR", "RRRRRRR", ".RRRRR.", "..RRR..", "...R...")
CLOVER = (".GG.GG.", "GGGGGGG", ".GGGGG.", "GGGGGGG", ".GG.GG.", "...G...", "....G..")
FLAG = ("WRRRRRR", "WWWWWWW", "WRRRRRR", "WWWWWWW", "WRRRRRR", "W......", "W......")
TURKEY = ("..ROY...", ".RROYY..", "RROOKKR.", "ROOKKKKY", ".OKKKKR.", "..KKKK..", "..Y..Y..")
CAKE = ("...Y...", "...W...", ".RRRRR.", ".WWWWW.", "RRRRRRR", "WWWWWWW", "RRRRRRR")
STAR = ("..Y..", ".YYY.", "YYYYY", ".YYY.", ".Y.Y.")
PIE = ("....K", "..KOO", "KKOOO", "OOOOO")
FRIEND_C = {"R": RED, "G": GREEN, "W": WHITE, "O": FL_ORANGE, "Y": FL_GOLD, "K": FL_DEEP,
            "P": FL_TONGUE}
FRIENDS = {"VALENTINE": HEART, "STPATRICK": CLOVER, "JULY4": FLAG,
           "THANKSGIVING": TURKEY, "ANNIV": CAKE}


def holiday_friend(b, look, x, base, now):
    """Draw the holiday's sprite standing on row `base`."""
    rows = FRIENDS.get(look)
    if not rows:
        return
    if look == "THANKSGIVING" and int(now * 8) % 2:      # turkey legs run
        rows = rows[:-1] + ("...Y.Y..",)
    if look == "JULY4":                                   # the flag waves
        k = int(now * 6) % 3
        rows = tuple(r[0] + (r[1:] if (i + k) % 3 else r[2:] + r[1]) for i, r in enumerate(rows))
    _sprite(b, x, base - len(rows) + 1, rows, FRIEND_C, False)


def _sprite(b, x, y, rows, colors, on_black=True):
    for yy, row in enumerate(rows):
        py = y + yy
        if not 0 <= py < 32:
            continue
        for xx, ch in enumerate(row):
            px = x + xx
            if ch != "." and 0 <= px < 64 and (not on_black or b[px, py] == BLACK):
                b[px, py] = colors[ch]


# ---------------- background (any screen) ----------------
def snow(b, now, n=16, colors=None):
    """Falling flakes (or leaves / confetti with `colors`), black pixels only."""
    for k in range(n):
        speed = 3.0 + (k * 7) % 5                  # px per second, varied
        y = int((k * 11 + now * speed) % 36) - 2
        x = int((k * 37 + math.sin(now * 0.8 + k) * (4.5 if colors else 2.5)) % 64)
        if 0 <= y < 32 and b[x, y] == BLACK:
            b[x, y] = (colors[k % len(colors)] if colors
                       else WHITE if k % 3 == 0 else FAR)


def hearts(b, now, n=4, x_max=64):
    """Little hearts floating up (Valentine's)."""
    for k in range(n):
        speed = 2.5 + k % 3
        y = 33 - int((k * 9 + now * speed) % 38)
        x = int((k * 17 + 5 + math.sin(now + k) * 2) % (x_max - 3))
        _sprite(b, x, y, ("R.R", "RRR", ".R."), {"R": RED if k % 2 else FL_TONGUE})


def rainbow(b, cx, cy, r=9):
    """A little rainbow arc (St. Patrick's Arcade sky)."""
    for band, col in enumerate((RED, FL_ORANGE, FL_YELLOW, GREEN, PURPLE)):
        rr = r - band
        for j in range(24):
            a = math.pi * j / 23
            px, py = int(cx + math.cos(a) * rr), int(cy - math.sin(a) * rr * 0.8)
            if 0 <= px < 64 and 0 <= py < 32 and b[px, py] == BLACK:
                b[px, py] = col


def sleigh(b, now, period=26.0, y=1):
    """Every `period` s Santa's sleigh crosses the sky, bobbing."""
    p = now % period
    if p > 6.0:
        return
    x = int(-16 + p / 6.0 * 82)
    _sprite(b, x, y + int(round(math.sin(p * 3) * 1.2)), SLEIGH, SLEIGH_C)
    if int(now * 4) % 2 == 0 and 0 <= x - 2 < 64 and 0 <= y + 2 < 32 \
            and b[x - 2, y + 2] == BLACK:
        b[x - 2, y + 2] = FL_YELLOW                 # a sparkle trailing behind


def bats(b, now, rows=(3, 9), x_max=64, period=14.0):
    """Two bats flutter across, right to left, every `period` s."""
    p = now % period
    if p > 5.0:
        return
    for k, (dy, lag) in enumerate(zip(rows, (0.0, 0.7))):
        q = p - lag
        if q < 0:
            continue
        x = int(x_max + 2 - q / 5.0 * (x_max + 16))
        y = dy + int(round(math.sin(q * 5 + k) * 2))
        rows_ = BAT[int(now * 8 + k) % 2]
        if x + 7 <= x_max or x_max == 64:
            _sprite(b, x, y, rows_, {"B": PURPLE})


def moon(b, x, y):
    for yy in range(-3, 4):
        for xx in range(-3, 4):
            d = xx * xx + yy * yy
            px, py = x + xx, y + yy
            if d <= 10 and 0 <= px < 64 and 0 <= py < 32 and b[px, py] == BLACK:
                b[px, py] = FAR if (xx + 1) ** 2 + (yy - 1) ** 2 > 3 else WHITE


def fireworks(b, now):
    for k in range(3):
        cyc = 1.6 + k * 0.3
        p = (now + k * 0.55) % cyc
        if p > 0.8:
            continue
        seed = int((now + k * 0.55) // cyc) * 7 + k * 13
        cx, cy = (seed * 23) % 56 + 4, (seed * 11) % 14 + 2
        r = 1 + p * 5
        col = (RED, FL_GOLD, WHITE, FL_YELLOW)[seed % 4]
        for j in range(8):
            a = j * math.pi / 4
            px, py = int(cx + math.cos(a) * r), int(cy + math.sin(a) * r * 0.8)
            if 0 <= px < 64 and 0 <= py < 32 and b[px, py] == BLACK:
                b[px, py] = col if p < 0.55 else MAROON


# ---------------- divider lines ----------------
DIVIDER = {      # (colours, run length, speed) for each holiday's divider line
    "VALENTINE": ((RED, FL_TONGUE, WHITE, FL_TONGUE), 2, 4),
    "STPATRICK": ((GREEN, GREEN, WHITE), 2, 3),
    "JULY4": ((RED, RED, WHITE, WHITE), 1, 6),
    "THANKSGIVING": ((FL_ORANGE, RED, FL_GOLD, FL_DEEP), 2, 2),
    "ANNIV": ((RED, FL_GOLD, GREEN, PURPLE, WHITE), 2, 5),
}


def lights(b, y, now, look):
    """Turn a divider row into string lights (Santa), candy corn (Halloween),
    or the holiday's colours."""
    pat = DIVIDER.get(look)
    for x in range(64):
        if b[x, y] in (MAROON, MAROON_DIM):
            if pat:
                cols, run, speed = pat
                b[x, y] = cols[((x + int(now * speed)) // run) % len(cols)]
            elif look == "NEWYEAR":                  # gold sparkle
                b[x, y] = (FL_GOLD, MAROON_DIM, WHITE, MAROON_DIM)[(x + int(now * 8)) % 4]
            elif look == "SANTA":
                if x % 3 == 1:
                    k = (x // 3 + int(now * 2)) % 3
                    b[x, y] = (RED, GREEN, FL_GOLD)[k]
                else:
                    b[x, y] = MAROON_DIM
            else:
                b[x, y] = (FL_YELLOW, FL_ORANGE, WHITE)[((x + int(now * 6)) // 2) % 3]


# ---------------- per screen ----------------
def backdrop(app, b, now, view):
    """Called after every frame (not the boot logo) while a season is on.
    `view` is the dashboard style on screen (7 = my live run), or -1 for
    alerts. Busy scenery only goes where there's open sky, so numbers and
    words never get cluttered."""
    look = app.look
    if look in DIVIDER:                              # the holidays
        if look == "THANKSGIVING":
            snow(b, now, 12, (FL_ORANGE, RED, FL_GOLD, FL_DEEP))   # falling leaves
        elif look == "ANNIV":
            snow(b, now, 18, (RED, FL_GOLD, GREEN, PURPLE, WHITE))  # confetti
        elif look == "JULY4":
            fireworks(b, now)
        elif look == "VALENTINE" and view in (2, 4, -1):
            hearts(b, now, 4, 23 if view == 4 else 64)
        if look == "STPATRICK" and view == 2:
            rainbow(b, 52, 21)
        if view in (0, 1, 3, 4, 6):
            lights(b, 17, now, look)
        elif view == 2:
            lights(b, 8, now, look)
        elif view in (5, 7):
            lights(b, 15, now, look)
            lights(b, 31, now, look)
            lights(b, 30, now, look)
        return
    if look == "NEWYEAR":
        fireworks(b, now)
        if view in (0, 1, 3, 4, 6):
            lights(b, 17, now, look)
        elif view == 2:
            lights(b, 8, now, look)
        return
    if look == "SANTA":
        snow(b, now)                                 # light snow, everywhere
        if view == 2:
            sleigh(b, now, y=11)                     # Arcade: Santa flies over
        if view in (5, 7):                           # snowy tracks
            snowy_track(b)
    elif look == "HALLOWEEN":
        if view == 2:                                # Arcade: moon + bats
            moon(b, 56, 14)
            bats(b, now, (11, 16))
        elif view == 4:                              # Campfire: moon + bats by the fire
            moon(b, 19, 3)
            bats(b, now, (1, 5), 23, 9.0)
        if view in (5, 7):
            lights(b, 15, now, look)
            lights(b, 31, now, look)
            lights(b, 30, now, look)
    if view in (0, 1, 3, 4, 6):                      # dividers: lights / candy corn
        lights(b, 17, now, look)
    elif view == 2:
        lights(b, 8, now, look)


def snowy_track(b):
    """Race lanes and the live-run track get a layer of snow."""
    for y in (15, 30, 31):
        for x in range(64):
            if b[x, y] in (MAROON, MAROON_DIM):
                b[x, y] = WHITE if y != 31 else FAR


# ---------------- Arcade hooks ----------------
def arcade_ground(app, b, d):
    if app.look == "SANTA":                          # snow on the track
        fill(b, 0, 30, 64, 31, WHITE)
        for x in range(64):
            b[x, 31] = FAR if int(x + d) % 8 < 3 else MAROON_DIM
        return True
    return False


def arcade_turkey(app, b, now, t):
    """Thanksgiving: the TURKEY TROT. A turkey runs ahead of the mascot."""
    if app.look != "THANKSGIVING":
        return
    x = 40 + int(math.sin(t * 0.7) * 6)
    holiday_friend(b, "THANKSGIVING", x, 29 - int(abs(math.sin(t * 9)) * 1), now)


def arcade_obstacle(app, b, x, k):
    """Return True if a seasonal obstacle was drawn at screen column x."""
    if app.look == "SANTA":
        _sprite(b, x, 26, PRESENT, {"Y": FL_GOLD, "X": RED if k % 2 else GREEN}, False)
        return True
    if app.look == "HALLOWEEN":
        if k % 2:
            _sprite(b, x, 26, PUMPKIN, {"G": GREEN, "O": FL_ORANGE}, False)
        else:
            _sprite(b, x, 26, TOMB, {"F": FAR, "D": BLACK}, False)
        return True
    return False


HOLIDAY_COIN = {"VALENTINE": (("R.R", "RRR", ".R."), 18), "STPATRICK": (CLOVER[:5], 16),
                "JULY4": (STAR, 16), "THANKSGIVING": (PIE, 17), "ANNIV": (CAKE[2:], 16)}


def arcade_coin(app, b, cx, now):
    """Ornament (Santa) or wrapped candy (Halloween) instead of a coin, or the
    holiday's collectible (heart, clover, star, pie, cake)."""
    hc = HOLIDAY_COIN.get(app.look)
    if hc:
        rows, y = hc
        bob = int(round(math.sin(now * 3) * 1))
        _sprite(b, cx - len(rows[0]) // 2, y + bob, rows, FRIEND_C, False)
        return True
    if app.look == "SANTA":
        bob = int(round(math.sin(now * 3) * 1))
        _sprite(b, cx - 2, 15 + bob, ("..Y..", ".RRR.", "RRWRR", "RRRRR", ".RRR."),
                {"Y": FL_GOLD, "R": RED, "W": WHITE}, False)
        return True
    if app.look == "HALLOWEEN":
        bob = int(round(math.sin(now * 3) * 1))
        _sprite(b, cx - 2, 17 + bob, CANDY, {"P": PURPLE, "O": FL_ORANGE}, False)
        return True
    return False


def campfire_snowcaps(app, b):
    """A little snow resting on the campfire logs."""
    if app.look != "SANTA":
        return
    for x in range(0, 23):
        if b[x, 27] == LOG and x % 2 == 0:
            b[x, 27] = WHITE
        if b[x, 29] == LOG and x % 3 == 0 and (x < 3 or x > 19):
            b[x, 29] = FAR
