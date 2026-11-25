# Mile A Day desk counter - laundry: the owner's washer and dryer (smart plugs
# under each one tell the server how much power it draws; the feed says what
# it's doing). Three things, loaded only when there's laundry to show:
#   badge()  - a tiny machine in the top-right corner of any style while one
#              runs (its drum turns) or waits to be emptied (it glows green)
#   screen() - the LAUNDRY style: both machines, what they're doing, time left
#   scene()  - "WASHER DONE!" with the mascot, once, when a load finishes
import math
from mad.gfx import (BLACK, MAROON_DIM, MAROON, RED, WHITE, FAR, SPARK, GREEN, WATER, WATER_LIGHT,
                     FL_YELLOW, FL_GOLD, FL_ORANGE, F5, F3, fill, draw_box, fit, text_width)

NAMES = {"w": "WASHER", "d": "DRYER"}
RUNNING = ("fill", "wash", "rinse", "drain", "spin", "dry", "cool", "tumble")
WORD = {"fill": "FILLING", "wash": "WASHING", "rinse": "RINSING", "drain": "DRAINING",
        "spin": "SPINNING", "dry": "DRYING", "cool": "COOLING", "tumble": "TUMBLING",
        "done": "DONE!", "idle": "FREE", "offline": "OFFLINE"}
# Points on a ring of radius 3 (the door), in order round it.
RING3 = ((0, -3), (1, -3), (2, -2), (3, -1), (3, 0), (3, 1), (2, 2), (1, 3), (0, 3), (-1, 3),
         (-2, 2), (-3, 1), (-3, 0), (-3, -1), (-2, -2), (-1, -3))
RING1 = ((0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1))


def machines(app):
    """[(key, info)] for the machines that have a plug, washer first."""
    lw = app.laundry or {}
    return [(k, lw[k]) for k in ("w", "d") if isinstance(lw.get(k), dict)]


def busy(app):
    """Machines worth a corner badge: running, or done and waiting."""
    return [(k, v) for k, v in machines(app) if v.get("s") in RUNNING or v.get("s") == "done"]


def _px(b, x, y, c):
    if 0 <= x < b.width and 0 <= y < b.height:
        b[x, y] = c


def _speed(s):
    return 9.0 if s == "spin" else 5.0 if s in ("dry", "cool", "tumble") else 2.5 if s in ("wash", "rinse") else 0.8


def badge(app, b, now):
    """7x7 machine in the top-right corner (two machines take turns)."""
    act = busy(app)
    if not act:
        return
    k, v = act[int(now / 3.0) % len(act)]
    s = v.get("s")
    x0, y0 = 57, 0
    fill(b, x0 - 1, y0, 64, y0 + 8, BLACK)          # a black edge keeps it readable
    done = s == "done"
    pulse = done and (now % 1.4) < 0.9
    body = GREEN if pulse else (MAROON if done else FAR)
    fill(b, x0, y0, x0 + 7, y0 + 1, body)
    fill(b, x0, y0 + 6, x0 + 7, y0 + 7, body)
    fill(b, x0, y0, x0 + 1, y0 + 7, body)
    fill(b, x0 + 6, y0, x0 + 7, y0 + 7, body)
    cx, cy = x0 + 3, y0 + 3
    if done:                                         # a little check mark inside
        for dx, dy in ((-1, 0), (0, 1), (1, 0), (1, -1)):
            _px(b, cx + dx, cy + dy, WHITE if pulse else GREEN)
        return
    hot = k == "d" and s == "dry"
    a = int(now * _speed(s)) % 8
    for i, (dx, dy) in enumerate(RING1):             # the drum turning
        c = (WATER_LIGHT if k == "w" else (FL_GOLD if hot else WHITE)) if (i - a) % 8 < 2 else \
            (WATER if k == "w" else (FL_ORANGE if hot else FAR))
        _px(b, cx + dx, cy + dy, c)


def big_machine(b, cx, y0, key, s, now):
    """13x12 washer or dryer, the drum doing what the machine does."""
    x0 = cx - 6
    run = s in RUNNING
    done = s == "done"
    off = s == "offline"
    edge = MAROON_DIM if off else (GREEN if done and (now % 1.4) < 0.9 else FAR)
    fill(b, x0, y0, x0 + 13, y0 + 1, edge)
    fill(b, x0, y0 + 11, x0 + 13, y0 + 12, edge)
    fill(b, x0, y0, x0 + 1, y0 + 12, edge)
    fill(b, x0 + 12, y0, x0 + 13, y0 + 12, edge)
    fill(b, x0 + 1, y0 + 3, x0 + 12, y0 + 4, MAROON_DIM)       # control panel line
    _px(b, x0 + 2, y0 + 1, RED if run else MAROON)              # knob
    _px(b, x0 + 3, y0 + 1, RED if run else MAROON)
    if run:                                                     # display lights
        _px(b, x0 + 10, y0 + 1, GREEN if int(now * 2) % 2 else MAROON)
    dcx, dcy = cx, y0 + 7
    hot = key == "d" and s == "dry"
    ring = FL_ORANGE if hot and int(now * 6) % 3 else (WATER_LIGHT if key == "d" and s == "cool" else
                                                        (MAROON if off else WHITE if run else FAR))
    for dx, dy in RING3[::2]:                                   # the door
        _px(b, dcx + dx, dcy + dy, ring)
    for dx, dy in ((1, -3), (3, 1), (-1, 3), (-3, -1)):
        _px(b, dcx + dx, dcy + dy, ring)
    if done:                                                    # clean and sparkling
        for dx, dy in ((-1, 0), (0, 1), (1, 0), (2, -1)):
            _px(b, dcx + dx, dcy + dy, GREEN)
        if (now % 1.0) < 0.5:
            _px(b, dcx - 2, dcy - 2, SPARK)
        return
    if not run:
        return
    a = now * _speed(s)
    if key == "w":                                              # water sloshing
        lvl = 0 if s in ("spin", "drain") else 1 if s == "fill" and int(now) % 2 else 0
        for dx in (-2, -1, 0, 1, 2):
            wy = dcy + 1 + lvl + (1 if abs(dx) == 2 else 0) - (1 if int(a + dx) % 4 == 0 and s != "spin" else 0)
            if s != "spin":
                _px(b, dcx + dx, wy, WATER)
                _px(b, dcx + dx, wy + 1, WATER)
        if s in ("wash", "rinse", "fill"):                      # bubbles
            _px(b, dcx + int(math.sin(a) * 2), dcy - 1 - int(a) % 2, WATER_LIGHT)
        if s == "spin":                                         # a blur going round
            for k in range(3):
                dx, dy = RING1[(int(a) + k * 3) % 8]
                _px(b, dcx + dx * 2, dcy + dy * 2, WATER_LIGHT if k else WHITE)
    else:                                                       # clothes tumbling
        cols = (RED, FL_GOLD, WATER_LIGHT)
        for k in range(3):
            ang = a * 0.7 + k * 2.1
            _px(b, dcx + int(round(math.cos(ang) * 1.6)), dcy + int(round(math.sin(ang) * 1.6)), cols[k])
        if hot:                                                 # warm air rising
            _px(b, dcx + (int(now * 3) % 3) - 1, y0 + 1, FL_YELLOW if int(now * 4) % 2 else FL_ORANGE)


def time_text(v, room):
    """(text, colour) under a machine: time left, how long ago, or nothing."""
    from mad.gfx import ink
    s = v.get("s")
    m, left = int(v.get("m") or 0), int(v.get("l") if v.get("l") is not None else -1)
    if s == "done":
        return ("%dM AGO" % m if m < 60 else "%dH AGO" % (m // 60)), RED
    if s in RUNNING:
        if left < 0:
            return "%dM IN" % m, FAR
        for fmt in ("%dM LEFT", "%d LEFT", "%dM"):
            txt = fmt % left
            lo, hi = ink(txt, F3)
            if hi - lo <= room:
                break
        return txt, (WHITE if v.get("ok") else FAR)       # dim: just an estimate
    return "", RED


def screen(app, b, now, t):
    """LAUNDRY: each machine with a plug gets its half of the screen."""
    fill(b, 0, 0, 64, 32, BLACK)
    ms = machines(app)
    if not ms:
        draw_box(b, 0, 64, 12, "NO LAUNDRY", RED, F3)
        return
    w = 64 // len(ms)
    for i, (k, v) in enumerate(ms):
        x0, x1 = i * w, (i + 1) * w
        if i:
            fill(b, x0, 1, x0 + 1, 31, MAROON_DIM)
            x0 += 1
        s = v.get("s") or "idle"
        big_machine(b, (x0 + x1) // 2, 0, k, s, now)
        word = WORD.get(s, s.upper())
        col = GREEN if s == "done" else MAROON if s == "offline" else WHITE if s in RUNNING else FAR
        fit(b, x0 + 1, x1 - 1, 13, word, col, F5, t)
        tt, tc = time_text(v, x1 - x0 - 2)
        if tt:
            fit(b, x0 + 1, x1 - 1, 21, tt, tc, F3, t)
        draw_box(b, x0, x1, 27, NAMES[k], RED, F3)


def scene(app, b, ev, t, now, dt):
    """WASHER / DONE! / TOOK 42M, the mascot hopping, the machine sparkling."""
    from mad.fx import typed, mascot_at_left, burst
    from mad.gfx import particles
    key, took = ev[1], ev[2]
    x0 = mascot_at_left(app, b, now, t)
    big_machine(b, 56, 1, key, "done", now)
    if t > 0.7 and not app.popped:                       # sparkles off the clean door
        app.popped = True
        burst(app, 56, 7, n=12, speed=12, colors=(GREEN, SPARK, WATER_LIGHT, FL_GOLD))
    particles(app, b, dt, gravity=10)
    typed(b, x0, 49, 4, NAMES.get(key, "LAUNDRY"), t - 0.2, RED, F3)
    typed(b, x0, 49, 11, "DONE!", t - 0.7, GREEN)
    if took and took > 0:
        typed(b, x0, 64, 23, "TOOK %dM" % took, t - 1.5, FAR, F3)
    else:
        typed(b, x0, 64, 23, "EMPTY ME!", t - 1.5, FAR, F3)
