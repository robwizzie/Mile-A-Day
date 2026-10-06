# Mile A Day desk counter - Flamey's Closet: whatever the owner has on in the
# app (colour, hat, glasses, costume) is painted onto the board's Flamey too,
# and the runner gets the matching hat and glasses. Imported only while
# dressing (season.apply), then dropped again to keep memory free.
from mad.gfx import (BLACK, MAROON_DIM, MAROON, RED, WHITE, FAR, SPARK, GREEN,
                     FL_YELLOW, FL_GOLD, FL_DEEP, FL_TONGUE, WATER, WATER_LIGHT, LOG,
                     PURPLE, HEAT_L)

EYE, GLINT = 21, 22
# His flame tones move to the startup logo's palette slots (free after boot),
# so a colour never touches the gold in text, trophies or medals.
REMAP = {16: 7, 17: 8, 18: 9, 19: 10, 23: 11, 24: 12}
# The app's colours, converted for the LEDs (a 1.6 gamma: dark app tones
# glow much brighter on an LED than on a phone, and blue runs hot), keeping
# every tone visible: (yellow, gold, body, deep, glow, base)
COLORS = {
    "ember": (0x8C2E11, 0x8C3E1A, 0x7F1000, 0x380000, 0x8C7147, 0x310000),
    "lime": (0x698521, 0x7F8C35, 0x477100, 0x123000, 0x888C59, 0x102A00),
    "ruby": (0x8C282B, 0x8C2B2C, 0x740010, 0x2F0000, 0x8C6652, 0x290000),
    "lavender": (0x766C69, 0x847D69, 0x625161, 0x342543, 0x8C8C69, 0x2E213C),
    "sunflower": (0x8C7D1C, 0x8C8020, 0x8C6500, 0x7E3500, 0x8C8A5A, 0x702F00),
    "mint": (0x43844C, 0x5D8C59, 0x107132, 0x003817, 0x7F8C64, 0x003114),
    "sapphire": (0x395E69, 0x3F5E69, 0x102269, 0x001030, 0x788269, 0x00002B),
    "violet": (0x614469, 0x6F5169, 0x3F1469, 0x150034, 0x837A69, 0x12002E),
    "rose": (0x8C4449, 0x8C5E55, 0x8C1C32, 0x510016, 0x8C7D63, 0x480014),
    "teal": (0x327A5A, 0x468260, 0x005841, 0x002823, 0x768C68, 0x002822),
    "arctic": (0x788469, 0x8C8C69, 0x697D69, 0x2D4D52, 0x8C8C69, 0x284449),
    "midnight": (0x286769, 0x111942, 0x000030, 0x000028, 0x7F8769, 0x000020),
    "phantom": (0x718861, 0x808C66, 0x537F59, 0x214040, 0x8C8C69, 0x1D3938),
    "sunset": (0x8C501F, 0x8C7120, 0x8C2B10, 0x6C1018, 0x8C834C, 0x240028),
    "aurora": (0x46834F, 0x358C41, 0x10673C, 0x13275E, 0x808C64, 0x321054),
    "ocean": (0x417F5B, 0x518C60, 0x006747, 0x00293C, 0x7E8C67, 0x000028),
    "lava_lamp": (0x8C4E10, 0x8C3E10, 0x78101B, 0x280016, 0x8C7C3E, 0x280016),
    "galaxy": (0x584469, 0x3F2B69, 0x13003E, 0x000028, 0x847D69, 0x000028),
    "candy": (0x8C6F60, 0x8C535A, 0x5F4669, 0x31605E, 0x8C8C69, 0x2B5554),
    "northern_lights": (0x308C48, 0x10184C, 0x00103C, 0x001030, 0x608C60, 0x000028),
    "gold": (0x8C7127, 0x8C8242, 0x805A00, 0x492600, 0x8C8A5C, 0x281D00),
    "prism": (0x8C7910, 0x8C4D10, 0x105664, 0x2F1859, 0x8C7F65, 0x681E30),
    "cosmic": (0x625369, 0x200038, 0x100030, 0x100028, 0x8C8C69, 0x100020),
    "eternal": (0x8C8C69, 0x8C8C69, 0x8C8552, 0x7E6423, 0x8C8C69, 0x704010),
}

# Letters: upper case paints always; lower case only over his body (never
# over his eyes), for bands and tinted lenses.
C = {"R": RED, "D": MAROON, "W": WHITE, "F": FAR, "G": GREEN, "Y": FL_GOLD,
     "S": FL_YELLOW, "K": FL_DEEP, "B": WATER_LIGHT, "N": WATER, "L": LOG,
     "P": PURPLE, "H": HEAT_L, "T": FL_TONGUE, "E": EYE, "Q": GLINT, "M": MAROON_DIM,
     "X": SPARK}

# ---- hats and glasses, one line each in ART below:
#   kind item size clear first_row rows (| between rows) A hat's first row is
# the top of the bitmap; "clear" hats replace his flame tip (the brim rests
# at rows 7-8 big, 4-5 small, like the holiday hats). His eyes are rows
# 13-16 (big) / 9-11 (small).
ART = """
H ball_cap 24 1 0 |||......RRRR......|.....RRWRRR.....|....RRRRRRRR....|....RRRRRRRR....|...DDDDDDDDDD...|....DDDDDDDD....
H ball_cap 17 1 0 ||....RRR....|...RRWRR...|..RRRRRRR..|..DDDDDDD..
H visor 24 0 9 rrrrrrrrrrrrrrrr|..DDDDDDDDDDDD..
H visor 17 0 6 rrrrrrrrrrr|.DDDDDDDDD.
H sweatband 24 0 10 rrrrrrrrrrrrrrrr|wwwwwwwwwwwwwwww
H sweatband 17 0 7 rrrrrrrrrrr
H beanie 24 1 0 .......WW.......|......WWWW......|......BBBB......|.....BBBBBB.....|....BBNBBNBB....|....BBNBBNBB....|....BBBBBBBB....|...WWWWWWWWWW...|...FFFFFFFFFF...
H beanie 17 1 0 .....W.....|....BBB....|...BNBNB...|...BBBBB...|..WWWWWWW..|..FFFFFFF..
H bucket_hat 24 1 0 |||......FFFF......|.....FFFFFF.....|.....FFFFFF.....|.....LLLLLL.....|...FFFFFFFFFF...|..FFFFFFFFFFFF..
H bucket_hat 17 1 0 ||....FFF....|...FFFFF...|...LLLLL...|.FFFFFFFFF.
H safari_hat 24 1 0 |||......YYYY......|.....YYYYYY.....|.....YYYYYY.....|.....LLLLLL.....|..YYYYYYYYYYYY..|.KKKKKKKKKKKKKK.
H safari_hat 17 1 0 ||....YYY....|...YYYYY...|...LLLLL...|KYYYYYYYYYK
H cowboy_hat 24 1 0 |||.....KK..KK.....|.....KKKKKK.....|.....KKKKKK.....|.....LLLLLL.....|K..KKKKKKKKKK..K|.KKKKKKKKKKKKKK.
H cowboy_hat 17 1 0 ||...K.K.K...|...KKKKK...|K..LLLLL..K|.KKKKKKKKK.
H aviator_cap 24 1 0 ||......KKKK......|.....KKKKKK.....|....KKKKKKKK....|....FBBFFBBF....|....FBBFFBBF....|...KKKKKKKKKK...|...KK......KK...
H aviator_cap 17 1 0 |....KKK....|...KKKKK...|..FBFKFBF..|..KKKKKKK..|..K.....K..
H headlamp_helmet 24 1 0 |||......YYYY......|.....YYXXYY.....|.....YYXXYY.....|....YYYYYYYY....|...YYYYYYYYYY...|...KKKKKKKKKK...
H headlamp_helmet 17 1 0 ||....YYY....|...YYXYY...|..YYYYYYY..|..KKKKKKK..
H crown 24 1 0 |||...Y...XX...Y...|...YY..YY..YY...|...YYYYYYYYYY...|...YYRYYYYRYY...|...YYYYYYYYYY...|...KKKKKKKKKK...
H crown 17 1 0 ||..Y..X..Y..|..YY.Y.YY..|..YRYYYRY..|..YYYYYYY..
H laurel_wreath 24 0 6 ..G..........G..|..GG........GG..|...GGggggggGG...
H laurel_wreath 17 0 4 .G.......G.|..GgggggG..
H viking_helmet 24 1 0 |W..............W|W..............W|WW....FFFF....WW|.WW..FFFFFF..WW.|..WWFFFFFFFFWW..|....FFFFFFFF....|...YYYYYYYYYY...|...KKKKKKKKKK...
H viking_helmet 17 1 0 W.........W|W...FFF...W|.W.FFFFF.W.|..WFFFFFW..|..YYYYYYY..|..KKKKKKK..
H directors_beret 24 1 0 ||||........D.......|....PPPPPPPP....|...PPPPPPPPPPP..|...PPPPPPPPPPPP.|....MMMMMMMM....
H directors_beret 17 1 0 |||.....D.....|..PPPPPPPP.|..MMMMMMM..
H heart_bopper 24 0 0 .RR.RR....RR.RR.|.RRRRR....RRRRR.|..RRR......RRR..|...R........R...|....F......F....|.....F....F.....|......F..F......|....RRRRRRRR....
H heart_bopper 17 0 0 R.R.....R.R|RRR.....RRR|.R.......R.|..F.....F..|...DDDDD...
H bunny_ears 24 0 0 ...WW......WW...|..WTW......WTW..|..WTW......WTW..|..WTW......WTW..|..WTW......WTW..|...WW......WW...|....W......W....|....WWWWWWWW....
H bunny_ears 17 0 0 .W.......W.|.WT.....TW.|.WT.....TW.|..W.....W..|..WWWWWWW..
E classic_shades 24 0 12 ..FFFFFFFFFFFF..|..EEEE....EEEE..|..EQEE....EQEE..|..EEEE....EEEE..|...EE......EE...
E classic_shades 17 0 8 .FFFFFFFFF.|.EEEE.EEEE.|.EQEE.EQEE.|..EE...EE..
E aviators 24 0 13 .YYYYYYYYYYYYYY.|.YLLLY....YLLLY.|.YKKY......YKKY.|..YY........YY..
E aviators 17 0 9 .YYYYYYYYY.|.YLKY.YKLY.|..YY...YY..
E round_specs 24 0 12 ...FFF....FFF...|..F...FFFF...F..|..F...F..F...F..|..F...F..F...F..|..F...F..F...F..|...FFF....FFF...
E round_specs 17 0 8 ..FF...FF..|.F..FFF..F.|.F..F.F..F.|.F..F.F..F.|..FF...FF..
E heart_glasses 24 0 12 ..RR.RR..RR.RR..|..RhhhRRRRhhhR..|..RhhhR..RhhhR..|...RhR....RhR...|....R......R....
E heart_glasses 17 0 8 RR.RR.RR.RR|RhhhRRRhhhR|RhhhR.RhhhR|.RhR...RhR.|..R.....R..
E star_glasses 24 0 11 ....Y......Y....|...YYY....YYY...|.YY...YYYY...YY.|..Y...Y..Y...Y..|..Y...Y..Y...Y..|..Y...Y..Y...Y..|...Y.Y....Y.Y...
E star_glasses 17 0 7 ..Y....Y...|..YY...YY..|YY..YYY..YY|.Y..Y.Y..Y.|.Y..Y.Y..Y.|..YY...YY..
E cyber_visor 24 0 13 .BBBBBBBBBBBBBB.|.BBWWWBBBBWWWBB.|.BBBBBBBBBBBBBB.|..NNNNNNNNNNNN..
E cyber_visor 17 0 9 .BBBBBBBBB.|BBWWBBBWWBB|.BBBBBBBBB.
E star_stickers 24 0 16 ..Y..........Y..|.YXY........YXY.|..Y..........Y..
E star_stickers 17 0 11 .Y.......Y.|YXY.....YXY|.Y.......Y.
"""


def _art(kind, item, size):
    """(clear, first row, rows) for this item and sprite size, or None.
    ART is one string constant: in the firmware it stays in flash."""
    if not item:
        return None
    i = ART.find("\n%s %s %d " % (kind, item, size))
    if i < 0:
        return None
    p = ART[i + 1:ART.find("\n", i + 1)].split()
    return int(p[3]), int(p[4]), p[5].split("|")


# The app's holiday hats are the board's holiday hats (mad/season.py).
SEASON_HAT = {"santa_hat": "SANTA", "leprechaun_hat": "STPATRICK", "star_hat": "JULY4",
              "countdown_hat": "ANNIV"}

# The runner's 4x4 head: (cap colour, accent) for hats; bands across his
# brow; one pixel of glasses where his eye is.
RUN_HAT = {"ball_cap": (RED, WHITE), "beanie": (WATER_LIGHT, WHITE), "bucket_hat": (FAR, LOG),
           "safari_hat": (FL_GOLD, LOG), "cowboy_hat": (FL_DEEP, FL_DEEP),
           "aviator_cap": (FL_DEEP, WATER_LIGHT), "headlamp_helmet": (FL_GOLD, SPARK),
           "crown": (FL_GOLD, RED), "viking_helmet": (FAR, WHITE),
           "directors_beret": (PURPLE, PURPLE), "santa_hat": (RED, WHITE),
           "leprechaun_hat": (GREEN, WHITE), "star_hat": (RED, WHITE),
           "countdown_hat": (RED, FL_GOLD)}
RUN_BAND = {"sweatband": RED, "visor": RED, "laurel_wreath": GREEN}
RUN_EYE = {"classic_shades": EYE, "aviators": WATER, "round_specs": FAR,
           "heart_glasses": RED, "star_glasses": FL_GOLD, "cyber_visor": WATER_LIGHT}


def _set(saved, b, x, y, v):
    if 0 <= x < b.width and 0 <= y < b.height:
        saved.extend((x, y, b[x, y]))
        b[x, y] = v


def _paint(saved, b, x0, y0, rows):
    for yy, row in enumerate(rows):
        y = y0 + yy
        for xx, ch in enumerate(row):
            if ch == ".":
                continue
            x = x0 + xx
            if ch.islower():
                if not (0 <= x < b.width and 0 <= y < b.height):
                    continue
                if b[x, y] in (0, EYE, GLINT):
                    continue
                ch = ch.upper()
            _set(saved, b, x, y, C[ch])


def _centre(b, y):
    lit = [x for x in range(b.width) if b[x, y]]
    return (min(lit) + max(lit) + 1) // 2 if lit else b.width // 2


def tones(color):
    """{palette slot: colour} for the app colour, or None (classic/unknown)."""
    t = COLORS.get(color)
    if not t:
        return None
    return dict(zip((7, 8, 9, 10, 11, 12), t))


# Colours with a pattern inside him: (rows from the top, letter) per size.
# Northern Lights: a mint and a pink aurora ribbon waving across his flame.
PATTERN = {"northern_lights": {24: ((3, "S"), (6, "T"), (9, "S")), 17: ((2, "S"), (5, "T"))}}


# ...and a light inner glow behind his smile, like the app's mint core:
# (first row, last row) of the lower face, per size.
FACE = {"northern_lights": {24: (17, 21), 17: (12, 14)}}


def pattern(saved, b, size, color):
    face = FACE.get(color, {}).get(size)
    if face:
        for y in range(face[0], face[1] + 1):
            lit = [x for x in range(b.width) if b[x, y]]
            if lit:
                for x in range(min(lit) + 2, max(lit) - 1):   # inside his outline
                    if b[x, y] == 9:
                        _set(saved, b, x, y, 7)
    rows = PATTERN.get(color, {}).get(size)
    if not rows:
        return
    for y0, ch in rows:
        v = 7 if ch == "S" else C[ch]               # 7 = the colour's own light tone
        for x in range(b.width):
            y = y0 + (0, 1, 1, 0, -1, -1)[x % 6]     # a gentle wave
            if 0 <= y < b.height and b[x, y] in (8, 9, 10):   # only on his flame, never his face
                _set(saved, b, x, y, v)


def recolor(frames, on):
    """Move his flame tones into the closet slots (on) or back (off)."""
    m = REMAP if on else {v: k for k, v in REMAP.items()}
    for b in frames:
        for y in range(b.height):
            for x in range(b.width):
                v = m.get(b[x, y])
                if v is not None:
                    b[x, y] = v


def head(saved, b, size, item):
    spec = _art("H", item, size)
    if not spec:
        return
    clear, y0, rows = spec
    x0 = _centre(b, 6 if size == 24 else 3) - (8 if size == 24 else 5)
    if clear:
        for y in range(len(rows)):            # the flame tip goes inside the hat
            for x in range(b.width):
                if b[x, y]:
                    _set(saved, b, x, y, 0)
    _paint(saved, b, x0, y0, rows)


def eyes(saved, b, size, item):
    spec = _art("E", item, size)
    if spec:
        _paint(saved, b, 0, spec[1], spec[2])


def ghost(saved, b, size):
    """Ghost sheet: a white sheet over his flame, eyes peeking out, a wavy hem."""
    for y in range(b.height):
        for x in range(b.width):
            v = b[x, y]
            if v in (16, 17, 18, 23, 7, 8, 9, 11):
                _set(saved, b, x, y, WHITE)
            elif v in (19, 24, 10, 12):
                _set(saved, b, x, y, FAR)
    bottom = max(y for y in range(b.height) for x in range(b.width) if b[x, y])
    for x in range(0, b.width, 3):            # the hem: little scallops
        _set(saved, b, x, bottom, 0)


def helmet(saved, b, size):
    """Astronaut: a glass bubble around his head, with a glint."""
    top = 13 if size == 24 else 9
    ring = []
    for y in range(top + 4):
        for x in range(b.width):
            if b[x, y]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                xx, yy = x + dx, y + dy
                if 0 <= xx < b.width and 0 <= yy < b.height and b[xx, yy]:
                    ring.append((x, y))
                    break
    for x, y in ring:
        _set(saved, b, x, y, WATER_LIGHT)
    if ring:
        x, y = min(ring, key=lambda p: (p[1], p[0]))
        _set(saved, b, x, y + 1, SPARK)


def runner(saved, b, look):
    """Hat / band / glasses on the runner's 4x4 head (columns 11-14)."""
    top = None
    for y in range(b.height):
        if any(b[x, y] == WHITE for x in range(11, 15)):
            top = y
            break
    if top is None:
        return
    h = look.get("head")
    if h in RUN_HAT:
        cap, accent = RUN_HAT[h]
        for x in range(10, 14):
            _set(saved, b, x, top, cap)
        if h in ("santa_hat",):
            _set(saved, b, 9, top + 1, accent)
        elif h in ("crown", "countdown_hat", "viking_helmet", "headlamp_helmet"):
            _set(saved, b, 12, top - 1 if top else top, accent)
        elif accent != cap:
            _set(saved, b, 12, top, accent)
        if h in ("ball_cap", "safari_hat", "cowboy_hat", "bucket_hat"):
            _set(saved, b, 14, top, cap)          # the brim, out front
    elif h in RUN_BAND:
        for x in range(11, 15):
            if top + 1 < b.height and b[x, top + 1] == WHITE:
                _set(saved, b, x, top + 1, RUN_BAND[h])
    elif h == "bunny_ears" and top >= 2:
        for y in (top - 2, top - 1):
            _set(saved, b, 11, y, WHITE)
            _set(saved, b, 13, y, WHITE)
    elif h == "heart_bopper" and top >= 1:
        _set(saved, b, 12, top - 1, RED)
    e = look.get("eyes")
    if e in RUN_EYE:
        _set(saved, b, 14, top + 1, RUN_EYE[e])
        _set(saved, b, 13, top + 1, RUN_EYE[e] if e != "round_specs" else FAR)
    if look.get("costume") == "pumpkin_suit":
        for y in range(top, min(b.height, top + 4)):
            for x in range(11, 15):
                if b[x, y] == WHITE:
                    _set(saved, b, x, y, 18)
