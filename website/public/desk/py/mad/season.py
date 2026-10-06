# Mile A Day desk counter - seasonal looks, painted onto the mascot frames
# in place (and undone when the season ends):
#   HALLOWEEN    (Oct 25-31): jack-o'-lantern Flamey; pumpkin-head runner
#   SANTA        (Dec 1-26):  Santa hats
#   NEWYEAR      (Dec 31-Jan 1): scenery only (fireworks)
#   VALENTINE    (Feb 13-14): rosy-cheeked Flamey; pink headband runner
#   STPATRICK    (Mar 16-17): green Flamey + leprechaun hat; green cap runner
#   JULY4        (Jul 3-4):   red-and-white striped top hats
#   THANKSGIVING (the Wed + Thu of Thanksgiving): pilgrim hats
#   ANNIV        (MAD_BIRTHDAY / MAD_ANNIVERSARY in settings.toml): party hats
# ...worn over the owner's own Flamey's Closet look (mad/closet.py).
from mad.gfx import (RED, MAROON, WHITE, FAR, GREEN, FL_ORANGE, FL_GOLD, FL_DEEP,
                     FL_TONGUE, GREEN_THEME, set_theme)

EYE, GLINT, MOUTH = 21, 22, 20
BODY = 18                     # the even orange behind Flamey's face

# Jack-o'-lantern faces: triangle eyes (with the same soft catch-light so he
# stays friendly, never spooky) and a happy carved grin with one tooth gap.
PUMPKIN = {
    17: {"y": 9,
         "open": [".E...E.",
                  "WEE.WEE",
                  ".......",
                  "E.....E",
                  ".EE.EE.",
                  "..EEE.."],
         "blink": [".......",
                   "EEE.EEE",
                   ".......",
                   "E.....E",
                   ".EE.EE.",
                   "..EEE.."]},
    24: {"y": 13,
         "open": ["..E....E..",
                  ".WEE..WEE.",
                  "EEEE..EEEE",
                  "..........",
                  ".E......E.",
                  "..EE.EEE..",
                  "...EEEE...",
                  ".........."],
         "blink": ["..........",
                   "..........",
                   "EEEE..EEEE",
                   "..........",
                   ".E......E.",
                   "..EE.EEE..",
                   "...EEEE...",
                   ".........."]},
}

# Hats sized to sit on Flamey's head: the white brim rests where the
# flame tip widens into his head (rows 7-8 big, 4-5 small), the red cone
# replaces the tip and flops to the right into a white pom-pom.
# R red, D shadow fold, W white, F dim white (underside of the brim).
SANTA = {
    17: {"cx": 5, "rows": [
        ".....RR....",
        "....RRRRR..",
        "...RRRRDRWW",
        "...RRRRR.WW",
        "..WWWWWWW..",
        "..FFFFFFF..",
    ]},
    24: {"cx": 8, "rows": [
        ".......RR.......",
        "......RRRRR.....",
        ".....RRRRRRRR...",
        ".....RRRRRRDRR..",
        "....RRRRRRR..WW.",
        "....RRRRRRR..WW.",
        "....RRRRRRRR....",
        "...WWWWWWWWWW...",
        "...FFFFFFFFFF...",
    ]},
}
UNCLE_SAM = {    # July 4th: red and white striped top hat, gold band
    17: {"cx": 5, "rows": ["...RRRRR...", "...WWWWW...", "...RRRRR...", "...YYYYY...",
                           "..WWWWWWW..", "..FFFFFFF.."]},
    24: {"cx": 8, "rows": [".....RRRRRR.....", ".....WWWWWW.....", ".....RRRRRR.....",
                           ".....WWWWWW.....", ".....RRRRRR.....", ".....WWWWWW.....",
                           ".....YYYYYY.....", "...WWWWWWWWWW...", "...FFFFFFFFFF..."]},
}
PILGRIM = {      # Thanksgiving: dark hat with a gold buckle
    17: {"cx": 5, "rows": ["...........", "...FFFFF...", "...FFFFF...", "...DYYYD...",
                           "..FFFFFFF..", "..DDDDDDD.."]},
    24: {"cx": 8, "rows": ["................", "................", ".....FFFFFF.....",
                           ".....FFFFFF.....", ".....FFFFFF.....", ".....DYDDYD.....",
                           ".....FFFFFF.....", "...FFFFFFFFFF...", "...DDDDDDDDDD..."]},
}
LEPRECHAUN = {   # St. Patrick's: green top hat, white buckle
    17: {"cx": 5, "rows": ["...........", "...GGGGG...", "...GGGGG...", "...DWWWD...",
                           "..GGGGGGG..", "..DDDDDDD.."]},
    24: {"cx": 8, "rows": ["................", ".....GGGGGG.....", ".....GGGGGG.....",
                           ".....GGGGGG.....", ".....GGGGGG.....", ".....DWDDWD.....",
                           ".....GGGGGG.....", "...GGGGGGGGGG...", "...DDDDDDDDDD..."]},
}
PARTY = {        # Mile A Day's birthday: striped party hat with a pom
    17: {"cx": 5, "rows": [".....W.....", ".....R.....", "....YYY....", "....RRR....",
                           "...WWWWW...", "..RRRRRRR.."]},
    24: {"cx": 8, "rows": [".......WW.......", ".......RR.......", "......YYYY......",
                           "......RRRR......", ".....WWWWWW.....", ".....RRRRRR.....",
                           "....YYYYYYYY....", "...RRRRRRRRRR...", "...YYYYYYYYYY..."]},
}
HATS = {"SANTA": SANTA, "JULY4": UNCLE_SAM, "THANKSGIVING": PILGRIM,
        "STPATRICK": LEPRECHAUN, "ANNIV": PARTY}
HAT_C = {"R": RED, "D": MAROON, "W": WHITE, "F": FAR, "G": GREEN, "Y": FL_GOLD,
         "K": FL_DEEP}
# The runner's little head gets a cap: (cap colour, accent colour) per look.
CAPS = {"SANTA": (RED, WHITE), "JULY4": (RED, WHITE), "THANKSGIVING": (FAR, FL_GOLD),
        "STPATRICK": (GREEN, WHITE), "ANNIV": (RED, FL_GOLD)}
# Jack-o'-lantern: his flame turns pumpkin orange and the tip becomes a stem.
STEM = {17: ["....GG.", "...GG.G"], 24: [".......GG.", "......GG.G", "......GG.."]}
PUMPKIN_TONE = {16: FL_ORANGE, 17: FL_ORANGE, 23: FL_ORANGE}   # yellows -> orange


def _set(saved, b, x, y, v):
    """Paint one pixel, remembering the old value as 3 bytes (x, y, old):
    a few thousand pixels of undo cost a few KB, not tens of KB of tuples."""
    if 0 <= x < b.width and 0 <= y < b.height:
        saved.extend((x, y, b[x, y]))
        b[x, y] = v


def _face(saved, b, size, frame_is_blink):
    face = PUMPKIN[size]
    fy = face["y"]
    rows = face["blink" if frame_is_blink else "open"]
    w = len(rows[0])
    xs = [x for y in range(fy, fy + len(rows)) for x in range(b.width)
          if b[x, y] in (EYE, GLINT)]
    if not xs:
        return
    fx = min(xs)
    width = max(xs) - fx + 1
    fx += (width - w) // 2                    # centre the new face on the old one
    for y in range(fy, fy + len(rows)):       # carve out the old face
        for x in range(b.width):
            if b[x, y] in (EYE, GLINT, MOUTH):
                _set(saved, b, x, y, BODY)
    for yy, row in enumerate(rows):
        for xx, ch in enumerate(row):
            if ch != ".":
                _set(saved, b, fx + xx, fy + yy, EYE if ch == "E" else GLINT)


def _centre(b, y):
    lit = [x for x in range(b.width) if b[x, y]]
    return (min(lit) + max(lit) + 1) // 2 if lit else b.width // 2


def _cheeks(saved, b, size):
    """Valentine's: two soft pink cheeks just under his eyes."""
    fy = PUMPKIN[size]["y"]
    xs = [x for y in range(fy, fy + 4) for x in range(b.width) if b[x, y] in (EYE, GLINT)]
    if not xs:
        return
    y = fy + (4 if size == 24 else 3)
    for x in (min(xs) - 1, min(xs), max(xs), max(xs) + 1) if size == 24 else (min(xs) - 1, max(xs) + 1):
        if 0 <= x < b.width and b[x, y] not in (0, EYE, GLINT, MOUTH):
            _set(saved, b, x, y, FL_TONGUE)


def _hat(saved, b, size, look="SANTA"):
    hat = HATS[look][size]
    rows = hat["rows"]
    x0 = _centre(b, len(rows) - 3) - hat["cx"]
    for y in range(len(rows)):                # the flame tip goes inside the hat
        for x in range(b.width):
            if b[x, y]:
                _set(saved, b, x, y, 0)
    for yy, row in enumerate(rows):
        for xx, ch in enumerate(row):
            if ch != ".":
                _set(saved, b, x0 + xx, yy, HAT_C[ch])


def _pumpkin_body(saved, b, size):
    for y in range(b.height):                 # pumpkin orange all over
        for x in range(b.width):
            v = PUMPKIN_TONE.get(b[x, y])
            if v is not None:
                _set(saved, b, x, y, v)
    stem = STEM[size]
    x0 = _centre(b, len(stem) + 1) - len(stem[0]) // 2
    for y in range(len(stem)):                # the flame tip becomes a stem
        for x in range(b.width):
            if b[x, y]:
                _set(saved, b, x, y, 0)
    for yy, row in enumerate(stem):
        for xx, ch in enumerate(row):
            if ch != ".":
                _set(saved, b, x0 + xx, yy, GREEN)


def _runner_head(saved, b, look):
    """The runner's head is 4x4 white pixels (columns 11-14). Halloween: an
    orange pumpkin head with a green stem and a carved eye. Santa: a red cap
    flopping back to a white pom-pom."""
    top = None
    for y in range(b.height):
        if any(b[x, y] == WHITE for x in range(11, 15)):
            top = y
            break
    if top is None:
        return
    if look == "HALLOWEEN":
        for y in range(top, min(b.height, top + 4)):
            for x in range(11, 15):
                if b[x, y] == WHITE:
                    _set(saved, b, x, y, FL_ORANGE)
        _set(saved, b, 14, top + 1, 21)              # carved eye, facing forward
        if top > 0:
            _set(saved, b, 12, top - 1, GREEN)       # stem
        else:
            _set(saved, b, 12, top, GREEN)
            _set(saved, b, 13, top, FL_ORANGE)
        return
    if look == "VALENTINE":                          # pink headband
        for x in range(11, 15):
            if top + 1 < b.height and b[x, top + 1] == WHITE:
                _set(saved, b, x, top + 1, FL_TONGUE)
        return
    cap, accent = CAPS[look]
    for x in range(10, 14):                          # cap on top...
        _set(saved, b, x, top, cap)
    if look == "SANTA":
        _set(saved, b, 9, top + 1, accent)           # ...flopping back to a pom
    elif look == "ANNIV":
        _set(saved, b, 12, top - 1 if top else top, accent)   # party-hat pom
    else:
        _set(saved, b, 12, top, accent)              # band / buckle / stripe


def apply(app, look, wear=None):
    """Dress the mascot frames: the season's `look` (None = normal) on top of
    `wear`, what the owner has on in the app's closet. Holiday looks
    win over the closet's hat and glasses; Halloween and St. Patrick's also
    over its colour."""
    wear = wear or {}
    key = (look, tuple(sorted(wear.items())))
    if key == getattr(app, "dressed", None):
        return
    for b, undo in getattr(app, "look_saved", ()):        # undo the last look
        for i in range(len(undo) - 3, -1, -3):
            b[undo[i], undo[i + 1]] = undo[i + 2]
    flames = list(app.flamey_m) + list(app.flamey_l)
    closet = None
    if wear:
        from mad import closet
    if getattr(app, "recolored", False):                  # tones back to normal
        _uncolor(flames)
        app.recolored = False
    costume = wear.get("costume") if look != "HALLOWEEN" else None
    theme = dict(GREEN_THEME) if look == "STPATRICK" else {}
    tones = None
    if closet and look not in ("HALLOWEEN", "STPATRICK") and costume not in ("pumpkin_suit", "ghost_sheet"):
        tones = closet.tones(wear.get("color"))
    if tones:
        theme.update(tones)
        closet.recolor(flames, True)
        app.recolored = True
    set_theme(theme or None)
    saved = []
    hat = look in HATS
    if not hat and wear.get("head") in (closet.SEASON_HAT if closet else ()):
        hat_look = closet.SEASON_HAT[wear["head"]]
    else:
        hat_look = look if hat else None
    dressed = look not in (None, "NEWYEAR") or wear
    if dressed:
        for size, frames in ((17, app.flamey_m), (24, app.flamey_l)):
            for k, b in enumerate(frames):
                undo = bytearray()
                if look == "HALLOWEEN" or costume == "pumpkin_suit":
                    _pumpkin_body(undo, b, size)
                    _face(undo, b, size, k == len(frames) - 1)
                elif costume == "ghost_sheet":
                    closet.ghost(undo, b, size)
                if tones:
                    closet.pattern(undo, b, size, wear.get("color"))
                if look == "VALENTINE":
                    _cheeks(undo, b, size)
                plain = look != "HALLOWEEN" and costume not in ("pumpkin_suit", "ghost_sheet")
                if hat_look:
                    if plain or hat:
                        _hat(undo, b, size, hat_look)
                elif closet and plain:
                    closet.head(undo, b, size, wear.get("head"))
                if closet and plain and look != "HALLOWEEN":
                    closet.eyes(undo, b, size, wear.get("eyes"))
                if costume == "astronaut_helmet":
                    closet.helmet(undo, b, size)
                saved.append((b, undo))
        for b in list(app.runner) + list(app.run_jump) + [app.run_sit]:
            undo = bytearray()
            if look and look != "NEWYEAR":
                _runner_head(undo, b, look)
            elif closet:
                closet.runner(undo, b, wear)
            saved.append((b, undo))
    app.look, app.look_saved, app.dressed = look, saved, key
    if closet:
        import sys
        import mad
        sys.modules.pop("mad.closet", None)         # dressed: free its tables
        try:
            delattr(mad, "closet")
        except Exception:            # (MicroPython raises KeyError here)
            pass


def _uncolor(frames):
    back = {7: 16, 8: 17, 9: 18, 10: 19, 11: 23, 12: 24}
    for b in frames:
        for y in range(b.height):
            for x in range(b.width):
                v = back.get(b[x, y])
                if v is not None:
                    b[x, y] = v
