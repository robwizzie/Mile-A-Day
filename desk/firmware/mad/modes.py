# Mile A Day desk counter - the full-screen dashboard styles:
# ARCADE (endless runner), CAMPFIRE, RACE (today vs yesterday) and CLOCK.
import math
import random
from mad.gfx import (fit, fit_icon, miles_text, particles, BLACK, MAROON_DIM, MAROON, RED, WHITE, FAR, SPARK, GREEN, LOG, upper_name,
                     FL_YELLOW, FL_GOLD, FL_ORANGE, FL_DEEP, WATER, WATER_LIGHT,
                     F5, F3, FB, ICONS, text_width, draw_text, ink, draw_box, blit,
                     fill, draw_icon, icon_width, commas, short, num, ease, ease_out)

ARCADE_SPEED = 24.0       # world scroll, pixels per second
ARCADE_GAP = 96           # pixels between obstacles (a coin sits halfway)
# Obstacles: the runner clears hurdles, Flamey hops over water drops.
HURDLE = ("#####", "#...#", "#...#", "#...#")
DROP = ("..#..", ".###.", "#####", ".###.")
HUD_LABEL = {3: "ACTIVE/WK", 4: "STREAK", 8: "TOKENS", 9: "BADGES", 10: "FRIENDS"}


def bits(b, x, y, name, color):
    """An icon in one flat colour (no special flame/coin colouring)."""
    w, rows = ICONS[name]
    for yy, r in enumerate(rows):
        for xx in range(w):
            if r & (1 << (w - 1 - xx)):
                px, py = x + xx, y + yy
                if 0 <= px < 64 and 0 <= py < 32:
                    b[px, py] = color


# =================== ARCADE ===================
def arcade(app, b, now, t):
    """An endless-runner game: the mascot runs (or Flamey hops) along a
    scrolling track, jumps hurdles (Flamey: water drops) and grabs a coin
    between each one. Every coin puts the next stat on the score bar."""
    d = t * ARCADE_SPEED
    fill(b, 0, 0, 64, 32, BLACK)
    mx = 6
    for k in range(7):                               # stars (slow parallax)
        sx = int((k * 23 + 64 - d * 0.15) % 70) - 3
        sy = 10 + (k * 5) % 9
        if 0 <= sx < 64:
            b[sx, sy] = MAROON_DIM if k % 2 else FAR
    dec = None
    if app.look:
        from mad import decor as dec
    if not (dec and dec.arcade_ground(app, b, d)):
        fill(b, 0, 30, 64, 31, MAROON)               # ground + moving dashes
        for x in range(64):
            if int(x + d) % 8 < 3:
                b[x, 31] = MAROON_DIM
    jump, jp = 0.0, 0.0
    t0 = 70 + ARCADE_GAP / 2 + 64 - (mx + 8)         # distance at the first coin grab
    coins = int((d - t0) // ARCADE_GAP) + 1 if d >= t0 else 0
    base = int((d - 70) // ARCADE_GAP)
    for k in range(base - 1, base + 3):
        if k < 0:
            continue
        ox = 70 + k * ARCADE_GAP - d + 64            # obstacle screen x
        if -6 < ox < 64 and dec and dec.arcade_obstacle(app, b, int(ox), k):
            pass
        elif -6 < ox < 64:
            shape = HURDLE if app.mascot == 0 else DROP
            for yy, row in enumerate(shape):
                for xx, ch in enumerate(row):
                    px, py = int(ox) + xx, 26 + yy
                    if ch == "#" and 0 <= px < 64:
                        b[px, py] = (RED if yy == 0 else WHITE) if app.mascot == 0 \
                            else (WATER_LIGHT if yy < 2 else WATER)
        p = ox - (mx + 4)                            # jump over it smoothly
        if -10 < p < 14:
            h = math.sin(math.pi * (14 - p) / 24) * 6
            if h > jump:
                jump, jp = h, p
        cx = ox + ARCADE_GAP / 2                     # the coin after it
        if mx + 8 < cx < 64 and dec and dec.arcade_coin(app, b, int(cx), now):
            pass
        elif mx + 8 < cx < 64:
            cxi = int(cx)
            w = (2, 1, 0, 1)[int(now * 6) % 4]       # spinning coin
            for yy in range(5):
                for xx in range(-w, w + 1):
                    if 0 <= cxi + xx < 64:
                        edge = abs(xx) == w or yy in (0, 4)
                        b[cxi + xx, 16 + yy] = FL_GOLD if edge else FL_YELLOW
    f = app.mascot_frame(now)                        # runner: real jump poses
    if app.mascot == 0 and jump > 0.6:
        f = app.run_jump[1 if jump > 4.2 else (0 if jp > 2 else 2)]
    y = int(round(30 - f.height - jump))
    if app.mascot == 1 and jump == 0:                # Flamey hops as he goes
        y -= int(round(abs(math.sin(t * math.pi * 2.2)) * 2))
    app.draw_mascot(b, f, mx + (0 if app.mascot == 0 else 3), y, now)
    if dec:
        dec.arcade_turkey(app, b, now, t)
    last = 70 + (coins - 1) * ARCADE_GAP + ARCADE_GAP / 2 - d + 64 if coins else -99
    since = (mx + 8 - last) / ARCADE_SPEED
    if coins and since < 0.35:                       # coin grabbed: sparkle
        r = int(since * 20) + 1
        for ddx, ddy in ((r, 0), (-r, 0), (0, r), (0, -r)):
            px, py = mx + 8 + ddx, 17 + ddy
            if 0 <= px < 64 and 8 < py < 32:
                b[px, py] = SPARK
    order = (0,) + app.order                         # score bar: one stat per coin
    i = order[coins % len(order)]
    frac = ease_out(since / 0.8) if coins and since < 0.8 else 1.0
    ic = app_icon(i)
    label, col = app.stat_label(i)
    if i != 11:
        label = HUD_LABEL.get(i, label)
    elif app.mile_done():
        label = "DONE"
    txt = app.stat_text(i, frac)
    if i == 12:                                      # goal: miles to go / target
        txt, label, col = short(app.value(12)), "TO " + app.stat_text(12), RED
    fill(b, 0, 0, 64, 8, BLACK)
    draw_icon(b, 1, 0, ic)
    x = draw_text(b, 2 + icon_width(ic), 0, txt, WHITE) + 2    # 3 px gap after it
    # The label goes right-aligned in what's left; a shorter word if it
    # won't fit, and if even that is too long it scrolls in its own space.
    for lab in (label, HUD_SHORT.get(label, label.split(" ")[0])):
        lo, hi = ink(lab, F3)
        if hi - lo <= 63 - x:
            draw_text(b, 63 - (hi - lo) - lo, 1, lab, col, F3)
            break
    else:
        fit(b, x, 63, 1, label, col, F3, now)
    fill(b, 0, 8, 64, 9, MAROON_DIM)


HUD_SHORT = {"MILE TODAY?": "RUN!", "DAYS DONE": "DAYS", "TOTAL MI": "MI", "MI TODAY": "TODAY",
             "ACTIVE/WK": "ACTIVE", "OUT NOW": "OUT",
             "RUNS TODAY": "RUNS", "RUNS ALL TIME": "RUNS"}


def app_icon(i):
    from mad.app import STATS
    return STATS[i][1]


# =================== CAMPFIRE ===================
def fire(b, cx, base, t, h=14, half=6):
    """A pixel campfire (runner mode): flickering columns, hot at the bottom."""
    for dx in range(-half, half + 1):
        top = h * (1 - abs(dx) / (half + 1.5)) * (0.75 + 0.25 * math.sin(t * 11 + dx * 1.9))
        top = int(top + (1 if (dx + int(t * 9)) % 4 == 0 else 0))
        for k in range(top):
            u = k / max(1, top)
            b[cx + dx, base - k] = (FL_DEEP if u < 0.25 else FL_ORANGE if u < 0.55
                                   else FL_GOLD if u < 0.8 else FL_YELLOW)


def campfire(app, b, now, t):
    """Night sky, logs, Flamey as the campfire. More miles today = more embers."""
    fill(b, 0, 0, 64, 32, BLACK)
    dt = min(0.1, max(0.0, now - getattr(app, "_cf_last", now)))
    app._cf_last = now
    for k in range(9):                                # twinkling stars
        sx, sy = (k * 29 + 5) % 62 + 1, (k * 7) % 11
        if (int(now * 2) + k) % 5:
            b[sx, sy] = FAR if k % 3 == 0 else MAROON_DIM
    cx = 11
    if app.mascot:                                    # Flamey sits on the logs
        f = app.mascot_frame(now, big=True)
        top = 27 - f.height
        app.draw_mascot(b, f, cx - f.width // 2, top, now)
        fill(b, 3, 27, 20, 29, LOG)                   # crossed logs, in front
        fill(b, 1, 29, 22, 31, LOG)
        for x, y in ((1, 29), (21, 29), (3, 27), (19, 27)):
            b[x, y] = FL_DEEP                         # glowing log ends
    else:                                             # the runner warms his hands
        cx = 16
        fire(b, cx, 27, now, 12, 5)
        fill(b, 11, 27, 22, 29, LOG)                  # fire logs
        fill(b, 10, 29, 23, 31, LOG)
        b[10, 29] = b[22, 29] = FL_DEEP
        fill(b, 0, 27, 9, 29, LOG)                    # his log seat
        b[0, 27] = MAROON
        blit(b, app.run_sit, -5, 13, skip=BLACK)
        top = 15
    fill(b, 0, 31, 23, 32, MAROON_DIM)               # warm glow on the ground
    if app.look:
        from mad import decor
        decor.campfire_snowcaps(app, b)
    miles = num(app.stats, "miles_today") if app.stats else 0
    rate = 1.5 + min(10.0, miles / 8.0)               # embers per second
    if random.random() < rate * dt:
        particles(app, b, dt, [cx + random.uniform(-4, 4), float(top + 2),
                                  random.uniform(-3, 3), random.uniform(-14, -7),
                                  random.uniform(0.8, 1.6), 0], gravity=-2)
    else:
        particles(app, b, dt, gravity=-2)
    fill(b, 23, 0, 24, 32, BLACK)                     # embers stay by the fire
    fill(b, 24, 0, 64, 32, BLACK)
    # right: miles today (big), then me / out now, alternating
    v = app.stat_text(1)
    draw_box(b, 24, 64, 1, v, WHITE, FB if text_width(v, FB) <= 40 else F5)
    draw_box(b, 24, 64, 12, "MI TODAY", RED, F3)
    fill(b, 30, 17, 58, 18, MAROON_DIM)
    pick = [i for i in (11, 7, 3) if i in app.order or i == 3]
    i = pick[int(t // 6) % len(pick)]
    app.draw_stat_line(b, i, 19, 1.0, 24, 64)      # label ends on the last row


# =================== RACE ===================
def race(app, b, now, t):
    """Today vs this time yesterday: two lanes, two racers."""
    fill(b, 0, 0, 64, 32, BLACK)
    c = app.stats or {}
    today, yday = num(c, "miles_today"), num(c, "miles_yesterday_same_time")
    top = max(today, yday, 1.0)
    run = ease(t / 2.2)
    d = t * (18 if t > 2.2 else 10)
    for lane, (label, v, y, lit) in enumerate((("TODAY", today, 0, True),
                                               ("YDAY", yday, 16, False))):
        draw_text(b, 1, y + 1, label, RED if lit else FAR, F3)
        txt = short(v) + " MI"
        if not lit and int(t // 3.5) % 2 and t > 2.2:      # the gap, every other beat
            gap = today - yday
            txt = ("+" if gap >= 0 else "-") + short(abs(gap)) + (" AHEAD" if gap >= 0 else " BEHIND")
            col = GREEN if gap >= 0 else RED
        else:
            col = WHITE if lit else FAR
        f = F5 if text_width(txt) <= 40 else F3
        lo, hi = ink(txt, f)
        draw_text(b, 63 - (hi - lo) - lo, y + (0 if f is F5 else 1), txt, col, f)
        g = y + 15                                          # track
        for x in range(64):
            if int(x + d) % 6 < 3:
                b[x, g] = MAROON_DIM if lit else (MAROON_DIM if x % 2 else BLACK)
        x = 1 + int(52 * (v / top) * run)
        bob = int(t * 8 + lane) % 2
        if lit and run < 1:                                 # speed lines while racing
            fill(b, max(0, x - 6), y + 10, max(0, x - 1), y + 11, MAROON)
        if app.mascot:
            if lit:
                draw_icon(b, x, y + 8 - bob, "streak")
            else:
                bits(b, x, y + 8 - bob, "streak", MAROON)
        else:
            bits(b, x, y + 8 - bob, "running", WHITE if lit else FAR)
    if today >= yday and t > 2.2 and int(t * 2) % 2:        # leader sparkle
        x = 1 + int(52 * today / top)
        if x + 6 < 64:
            b[x + 6, 7] = SPARK


# =================== CLOCK ===================
def clock(app, b, now, t):
    """Mile-A-Day clock: time, and either MILE DONE or the time left today.
    The night style (dimmed, mascot asleep)."""
    fill(b, 0, 0, 64, 32, BLACK)
    app.draw_mascot_corner(b, now)
    fill(b, 19, 1, 20, 16, MAROON_DIM)
    s = app.local_seconds(now)
    if s is None:
        draw_box(b, 20, 64, 4, "--:--", WHITE)
    else:
        h, m = int(s // 3600), int(s % 3600 // 60)
        hh, mm = str(h % 12 or 12), "%02d" % m
        w = text_width(hh, FB) + 4 + text_width(mm, FB)
        x = 20 + (44 - w) // 2
        x = draw_text(b, x, 1, hh, WHITE, FB)
        if int(s) % 2 == 0:                              # blinking colon
            fill(b, x + 1, 3, x + 3, 5, RED)
            fill(b, x + 1, 7, x + 3, 9, RED)
        draw_text(b, x + 4, 1, mm, WHITE, FB)
        draw_box(b, 20, 64, 12, "AM" if h < 12 else "PM", MAROON if app.night else RED, F3)
    fill(b, 0, 17, 64, 18, MAROON)
    streak = int(app.value(11))
    if app.mile_done():
        w = 7 + text_width("MILE DONE")
        x = (64 - w) // 2
        draw_icon(b, x, 20, "check")
        draw_text(b, x + 7, 20, "MILE DONE", WHITE)
        draw_box(b, 0, 64, 27, "%d DAY STREAK" % streak, GREEN, F3)
        return
    if s is None:
        return
    left = int((86400 - s) // 60)
    txt = ("%dH %02dM LEFT" % (left // 60, left % 60)) if left >= 60 else "%dM LEFT" % left
    urgent = left < 120
    col = (RED if int(now * 2) % 2 else WHITE) if urgent else WHITE
    draw_box(b, 0, 64, 19, txt, col, F5 if text_width(txt) <= 63 else F3)
    draw_box(b, 0, 64, 27, ("KEEP %d GOING" % streak) if streak else "RUN YOUR MILE", RED, F3)


# =================== LIVE (I'm out running) ===================
def live(app, b, now, t):
    """Shown on its own while the owner is out on a tracked run: name, the
    mascot running, live miles easing up between polls, a bar to one mile."""
    fill(b, 0, 0, 64, 32, BLACK)
    me = app.me or {}
    dt = min(0.1, max(0.0, now - getattr(app, "_lv_last", now)))
    app._lv_last = now
    target = float(me.get("live_miles") or 0)
    app.live_shown += (target - app.live_shown) * min(1.0, dt * 1.5)
    if abs(target - app.live_shown) < 0.005:
        app.live_shown = target
    name = upper_name(me.get("username"))
    walk = me.get("live_kind") == "walk"
    fit(b, 0, 64, 1, name, WHITE, t=t)
    draw_box(b, 0, 64, 9, "IS WALKING" if walk else "IS RUNNING", RED, F3)
    d = t * (12 if walk else 30)          # a walk: the track rolls by slower
    fill(b, 0, 30, 64, 31, MAROON)
    for x in range(64):
        if int(x + d) % 8 < 3:
            b[x, 31] = MAROON_DIM
    f = app.mascot_frame(now * 0.5 if walk else now)
    x = 6
    y = 31 - f.height                    # feet on the track, head clear of the text
    if app.mascot:
        y -= int(round(abs(math.sin(t * math.pi * (1.2 if walk else 2.4)))))
    if not walk:
        for k, (dy, ln) in enumerate(((19, 6), (22, 9), (25, 5))):   # speed lines
            fill(b, x - ln - 1 + (k % 2), dy, x - 1 + (k % 2), dy + 1, MAROON_DIM)
    blit(b, f, x, y, skip=BLACK)
    v = app.live_shown
    done = v >= 0.95
    txt = miles_text(v, 36, F5, 7 if done else 0)
    if done:
        fit_icon(b, 28, 64, 17, "check", txt, WHITE, t=t)
    else:
        fit(b, 28, 64, 17, txt, WHITE, t=t)
    fill(b, 33, 27, 59, 29, MAROON_DIM)              # progress toward the mile
    fill(b, 33, 27, 33 + int(26 * min(1.0, v)), 29, GREEN if done else RED)
