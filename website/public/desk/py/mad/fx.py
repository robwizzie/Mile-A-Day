# Mile A Day desk counter - alerts and celebrations. Each scene draws one
# frame for time t; after its length the mascot wipes the dashboard back in.
import math
import random
from mad.gfx import (fit, fit_icon, miles_text, particles, BLACK, MAROON_DIM, MAROON, RED, WHITE, FAR, SPARK, GREEN,
                     FL_YELLOW, FL_GOLD, FL_ORANGE, FL_DEEP, WATER_LIGHT, PURPLE, FL_TONGUE,
                     HEAT_L, HEAT_D, F5, F3, FB,
                     ICONS, text_width, draw_text, ink, draw_box, blit, fill, draw_icon,
                     icon_width, short, num, commas, ease, ease_out, upper_name)

CONFETTI = (RED, WHITE, FL_GOLD, FL_YELLOW, MAROON)


# ---------------- helpers ----------------
# (particles() lives in mad/gfx.py: the Campfire style uses it too)


SEASON_CONFETTI = {"SANTA": (RED, WHITE, GREEN, FL_GOLD),
                   "HALLOWEEN": (FL_ORANGE, FL_YELLOW, PURPLE, WHITE),
                   "VALENTINE": (RED, FL_TONGUE, WHITE),
                   "STPATRICK": (GREEN, FL_GOLD, WHITE),
                   "JULY4": (RED, WHITE, FL_GOLD),
                   "THANKSGIVING": (FL_ORANGE, RED, FL_GOLD, FL_DEEP),
                   "ANNIV": (RED, WHITE, FL_GOLD, GREEN, PURPLE)}


def burst(app, x, y, n=14, speed=14, colors=CONFETTI):
    if colors is CONFETTI:                    # seasonal confetti colours
        colors = SEASON_CONFETTI.get(getattr(app, "look", None), CONFETTI)
    for _ in range(n):
        a = random.uniform(0, 6.283)
        s = random.uniform(0.4, 1.0) * speed
        app.particles.append([x, y, math.cos(a) * s, math.sin(a) * s * 0.8 - 3,
                              random.uniform(0.6, 1.2), 1, random.choice(colors)])


def typed(b, x0, x1, y, text, t, color, font=F5, rate=0.06):
    """Type `text` on from time 0, centred (by its finished width) in x0..x1."""
    k = int(t / rate) if t > 0 else 0
    if k <= 0:
        return
    lo, hi = ink(text, font)
    if hi - lo > x1 - x0:                    # too long to type in place: scroll it
        fit(b, x0, x1, y, text, color, font, t, small=False)
        return
    draw_text(b, x0 + (x1 - x0 - (hi - lo)) // 2 - lo, y, text[:k], color, font)


def name_font(name, room):
    return F5 if text_width(name) <= room else F3


def mascot_at_left(app, b, now, t, hop=True):
    """The mascot standing at the left edge; returns the first free column."""
    f = app.mascot_frame(now, big=True)
    y = (32 - f.height) // 2 + (1 if app.mascot == 0 else 0)
    if hop and app.mascot:
        y -= int(round(abs(math.sin(t * math.pi * 1.4)) * 2))
    app.draw_mascot(b, f, (22 - f.width) // 2, y, now)   # centred in columns 0..21
    return 23


def shake(app, dx, dy=0):
    """Shift the whole frame (screen shake)."""
    if dx or dy:
        s = app.scratch
        blit(s, app.fb, 0, 0)
        fill(app.fb, 0, 0, 64, 32, BLACK)
        blit(app.fb, s, dx, dy)


def three_lines(b, x0, t, a, b_, c, ca=WHITE, cb=RED, cc=RED):
    """Name / verb / object, typed one after another (rows 2, 11, 20)."""
    room = 64 - x0
    typed(b, x0, 64, 4 if name_font(a, room) is F3 else 3, a, t, ca, name_font(a, room))
    typed(b, x0, 64, 12, b_, t - 0.06 * len(a) - 0.1, cb)
    typed(b, x0, 64, 21, c, t - 0.06 * (len(a) + len(b_)) - 0.2, cc)


# ---------------- dispatcher ----------------
def play(app, now):
    ev = app.ev
    t = now - app.mode_start
    dt = min(0.1, max(0.0, now - app._last))
    app._last = now
    kind = ev[0]
    if kind == "user":
        scene, length = (flamey_party, 9.0) if app.mascot else (runner_party, 9.2)
    else:
        scene, length = SCENES[kind]
        if kind == "atrisk":
            length = atrisk_length(ev)
        elif kind in LAZY:
            from mad import extra                   # rarer scenes, loaded on demand
            scene = getattr(extra, kind)
            length = extra.length(ev)
    if t > length:
        app.finish_wipe(now, t, length)
        return
    fill(app.fb, 0, 0, 64, 32, BLACK)
    scene(app, app.fb, ev, t, now, dt)


# ---------------- nudge: a finger pokes the mascot, the screen shakes ----------------
FINGER = (
    "........#####RR",
    "#########ooo#RR",
    "#ooooooooooo#RR",
    "#########ooo#RR",
    "........#ooo#RR",
    "........#ooo#RR",
    "........#####..",
)


def draw_finger(b, x, y):
    for yy, row in enumerate(FINGER):
        for xx, ch in enumerate(row):
            px = x + xx
            if ch != "." and 0 <= px < 64:
                b[px, y + yy] = WHITE if ch == "#" else (FAR if ch == "o" else RED)


def nudge(app, b, ev, t, now, dt):
    name = ev[1]
    x0 = mascot_at_left(app, b, now, t, hop=t > 2.2)
    tip = x0 - 2                                    # where the finger touches
    if t < 2.2:
        if t < 0.8:
            fx = int(64 - (64 - tip) * ease(t / 0.8))
        elif t < 1.6:                               # poke, poke
            ph = (t - 0.8) / 0.4 % 1.0
            fx = tip + int(round(abs(math.sin(ph * math.pi)) * 4))
        else:
            fx = int(tip + (64 - tip) * ease((t - 1.6) / 0.6))
        draw_finger(b, fx, 12)
        if 0.8 < t < 1.6:
            ph = (t - 0.8) / 0.4 % 1.0
            if ph < 0.35 or ph > 0.9:               # impact: little lines + shake
                for ddx, ddy in ((-1, -3), (1, -4), (-1, 9), (1, 10)):
                    px = tip + ddx
                    if 0 <= px < 64:
                        b[px, 12 + ddy] = SPARK
                shake(app, (-2, 2, -1, 1)[int(t * 30) % 4])
        return
    three_lines(b, x0, t - 2.2, name, "NUDGED", "YOU!")
    if t > 4.3 and not app.mile_done():             # ...and what it means
        fill(b, x0, 21, 64, 28, BLACK)
        col = WHITE if int(t * 3) % 2 else RED
        draw_box(b, x0, 64, 21, "GO RUN!", col)


# ---------------- hype: clapping hands + confetti ----------------
HAND = (      # left hand, palm facing right ('o' shade, '+' cuff); right = mirror
    "...#.#.", "..##.##", "..#####", "..#####", ".######", "#o#####", "#oo####",
    "#oo####", ".o#####", "..o####", "...o###", "...+++.", "...+++.",
)


def clap_hands(b, cx, y, opening, squash=0):
    """Two hands meeting at column cx, hinged at the wrists: `opening` 0..1
    swings the fingertips apart (a real clap is a swing, not a slide)."""
    n = len(HAND) - 1
    for yy, row in enumerate(HAND):
        off = int(round(opening * (1.5 + 4.5 * (n - yy) / n))) - squash
        for xx, ch in enumerate(row):
            if ch == ".":
                continue
            c = WHITE if ch == "#" else (FAR if ch == "o" else RED)
            lx = cx - 7 + xx - off          # left hand (palm on its right edge)
            rx = cx + 7 - xx + off          # right hand mirrored
            for px in (lx, rx):
                if 0 <= px < 64 and 0 <= y + yy < 32:
                    b[px, y + yy] = c


def clap_rays(b, cx, y, k):
    """Impact lines bursting from the top of the clap (k = frames since)."""
    col = FL_YELLOW if k == 0 else FL_GOLD
    r0 = 2 + k
    for dx, dy in ((0, -1), (-1, -1), (1, -1), (-2, 0), (2, 0)):
        for r in (r0, r0 + 1):
            px, py = cx + dx * r, y + dy * r
            if 0 <= px < 64 and 0 <= py < 32:
                b[px, py] = col


def hype(app, b, ev, t, now, dt):
    name = ev[1]
    cx, hy = 11, 11
    period = 0.5
    if t < 3.5:
        u = (t % period) / period
        if u < 0.28:                                  # swing shut, accelerating
            v = u / 0.28
            opening, squash = 1 - v * v, 0
        elif u < 0.4:                                 # CLAP
            opening, squash = 0.0, 1
        else:                                         # ease back open
            opening, squash = ease_out((u - 0.4) / 0.6), 0
        k = int(t // period)
        if squash and k != getattr(app, "_clap", -1):
            app._clap = k
            burst(app, cx, hy, 10, 16)
        jolt = 1 if squash else 0
        clap_hands(b, cx, hy - jolt, opening, squash)
        if 0.28 <= u < 0.5:
            clap_rays(b, cx, hy - 1, int((u - 0.28) / 0.07))
        if squash:
            shake(app, 0, 0)
    else:                                             # hold, hands together
        clap_hands(b, cx, hy, 0.12)
        if random.random() < 0.25:
            burst(app, random.uniform(24, 62), random.uniform(0, 8), 3, 6)
    particles(app, b, dt)
    three_lines(b, 23, t - 0.5, name, "HYPED", "YOU!", WHITE, FL_GOLD, FL_GOLD)


# ---------------- a friend is out running (or walking) ----------------
def friend(app, b, ev, t, now, dt):
    name, miles = ev[1], ev[2]
    walk = len(ev) > 3 and ev[3]
    typed(b, 0, 64, 1, name, t, WHITE, name_font(name, 62))
    if app.popped and int(t / 1.5) % 2:              # they've hit their mile
        draw_box(b, 0, 64, 9, "MILE DONE!", GREEN, F3)
    else:
        typed(b, 0, 64, 9, "IS WALKING" if walk else "IS RUNNING", t - 0.06 * len(name) - 0.1, RED, F3)
    d = t * (12 if walk else 30)         # a walk: the track rolls by slower
    fill(b, 0, 30, 64, 31, MAROON)
    for x in range(64):
        if int(x + d) % 8 < 3:
            b[x, 31] = MAROON_DIM
    f = app.mascot_frame(now * 0.5 if walk else now)
    x = int(-18 + 24 * ease_out(t / 1.0))
    y = 31 - f.height                    # feet on the track, head clear of the text
    if app.mascot:
        y -= int(round(abs(math.sin(t * math.pi * (1.2 if walk else 2.4)))))
    if not walk:
        for k, (dy, ln) in enumerate(((19, 6), (22, 9), (25, 5))):   # speed lines
            fill(b, x - ln - 1 + (k % 2), dy, x - 1 + (k % 2), dy + 1, MAROON_DIM)
    blit(b, f, x, y, skip=BLACK)
    if t > 1.2:
        v = miles * ease_out((t - 1.2) / 1.0)
        done = v >= 1.0                              # a full mile, no early check
        if done and not app.popped:                  # counting past 1.00: confetti!
            app.popped = True
            burst(app, 46, 20, 22, 15, (GREEN, FL_GOLD, WHITE))
        txt = miles_text(v, 36, F5, 7 if done else 0)
        if done:
            fit_icon(b, 28, 64, 17, "check", txt, WHITE, t=t, icon_color=GREEN)
        else:
            fit(b, 28, 64, 17, txt, WHITE, t=t)
        fill(b, 33, 27, 59, 29, MAROON_DIM)          # progress toward their mile
        fill(b, 33, 27, 33 + int(26 * min(1.0, v)), 29, GREEN if done else RED)
    particles(app, b, dt, gravity=8)


# ---------------- reminder: today's mile isn't done yet ----------------
def time_left(app, now):
    s = app.local_seconds(now)
    if s is None:
        return ""
    m = int((86400 - s) // 60)
    return "%dH %02dM" % (m // 60, m % 60) if m >= 60 else "%dM LEFT" % m


def reminder(app, b, ev, t, now, dt):
    x0 = mascot_at_left(app, b, now, t)
    s = app.local_seconds(now) or 0
    late = s >= 18 * 3600
    typed(b, x0, 64, 3, "MILE", t, WHITE)
    col = (WHITE if int(t * 3) % 2 else RED) if late and t > 1 else RED
    typed(b, x0, 64, 12, "TODAY?", t - 0.35, col)
    if t > 1.2:
        draw_box(b, x0, 64, 21, time_left(app, now), WHITE if not late else FL_GOLD,
                 F5 if text_width(time_left(app, now)) <= 64 - x0 else F3)


# ---------------- mile done: break the tape, check, streak +1 ----------------
def finish_line(app, b, t, now, dt):
    """The mascot sprints in and breaks the finish tape (first 2 s)."""
    if True:
        fill(b, 0, 30, 64, 31, MAROON)
        tape = 46
        f = app.mascot_frame(now)
        x = int(-18 + (64 + 20) * (t / 1.7))
        if x + f.width - 4 < tape:                   # tape still up
            for y in range(10, 30):
                if y % 2 == 0:
                    b[tape, y] = WHITE
                else:
                    b[tape, y] = RED
        else:                                        # snapped: two ends flutter
            if not app.popped:
                app.popped = True
                burst(app, tape, 18, 22, 18)
            k = int(now * 8) % 2
            for i in range(5):
                if 0 <= tape - 1 - i < 64:
                    b[tape - 1 - i // 2 - k, 10 + i] = RED
                    b[tape + 1 + i // 2 + k, 29 - i] = RED
        fill(b, tape - 1, 6, tape + 2, 8, FAR)       # finish post tops
        y = 30 - f.height
        if app.mascot:
            y -= int(round(abs(math.sin(t * math.pi * 2.5)) * 3))
        blit(b, f, x, y, skip=BLACK)
        particles(app, b, dt)


def mile(app, b, ev, t, now, dt):
    streak = ev[1]
    if t < 2.0:
        finish_line(app, b, t, now, dt)
        return
    if random.random() < 0.3:
        burst(app, random.uniform(4, 60), -1, 2, 5)
    particles(app, b, dt, gravity=8)
    pop = ease_out((t - 2.0) / 0.35)
    if pop > 0.5:
        draw_icon(b, 4, 9, "check", GREEN, scale=2)  # 10x14, centred top to bottom
    typed(b, 16, 64, 1, "MILE", t - 2.2, WHITE)
    typed(b, 16, 64, 9, "DONE!", t - 2.5, GREEN)
    if t > 3.3:
        r = ease((t - 3.3) / 0.9)
        n = int(max(0, streak - 1) + (1 if streak else 0) * r + 0.5)
        txt = str(n)
        w = 7 + text_width(txt)
        x = 16 + (48 - w) // 2
        draw_icon(b, x, 17, "streak")
        draw_text(b, x + 7, 17, txt, FL_YELLOW if r >= 1 else WHITE)
        draw_box(b, 16, 64, 26, "DAY STREAK", RED, F3)


# ---------------- milestone: fireworks ----------------
def milestone(app, b, ev, t, now, dt):
    what, value = ev[1], ev[2]
    if random.random() < (0.12 if t < 5.5 else 0.03):
        burst(app, random.uniform(6, 58), random.uniform(3, 14), 16, 15,
              random.choice(((RED, WHITE), (FL_GOLD, FL_YELLOW), (RED, FL_GOLD))))
    particles(app, b, dt, gravity=10)
    typed(b, 0, 64, 3, "MY MILESTONE" if what == "streak" else "MILESTONE", t, FL_GOLD, F3)
    v = value * ease_out((t - 0.4) / 1.4)
    s = str(int(v)) if value < 10000 else short(v)
    if text_width(s, FB) > 62:
        s = short(v)
    draw_box(b, 0, 64, 10, s, WHITE if t > 1.8 else FL_GOLD, FB)
    if what == "streak":
        if value % 365 == 0:
            yrs = value // 365
            label, font = "%d YEAR%s STREAK!" % (yrs, "" if yrs == 1 else "S"), F3
        else:
            label, font = "DAY STREAK!", F5
        typed(b, 0, 64, 22 if font is F5 else 23, label, t - 1.8, RED, font)  # ends row 28
        return
    typed(b, 0, 64, 22, "USERS!" if what == "users" else "MILES!", t - 1.8, RED)


def streak(app, b, ev, t, now, dt):
    milestone(app, b, ("milestone", "streak", ev[1]), t, now, dt)


# ---------------- a friend this board showed running just finished ----------------
def finished(app, b, ev, t, now, dt):
    name, miles = ev[1], ev[2]
    if t < 2.0:
        finish_line(app, b, t, now, dt)
        return
    if random.random() < 0.2:
        burst(app, random.uniform(4, 60), -1, 2, 5)
    particles(app, b, dt, gravity=8)
    typed(b, 0, 64, 3 if name_font(name, 62) is F5 else 4, name, t - 2.0, WHITE, name_font(name, 62))
    done = miles >= 1.0                  # DONE! only for a full mile
    if t > 2.0 + 0.06 * len(name):
        word = "DONE!" if done else "FINISHED"
        w = (7 if done else 0) + text_width(word)
        x = (64 - w) // 2
        if done:
            draw_icon(b, x, 12, "check")
        typed(b, x + (7 if done else 0), x + (7 if done else 0) + text_width(word), 12, word,
              t - 2.1 - 0.06 * len(name), GREEN if done else WHITE)
    if t > 3.4:
        v = miles * ease_out((t - 3.4) / 0.8)
        walk = len(ev) > 3 and ev[3]
        fit(b, 0, 64, 21, "%.1f MI %s" % (int(v * 10) / 10, "WALK" if walk else "RUN"), WHITE, t=t)


# ---------------- evening: friends whose streak is at risk ----------------
def sweat(app, b, t):
    """A little nervous sweat drop by the mascot's head (both mascots)."""
    f = app.flamey_l[0] if app.mascot else app.runner[0]
    x = (22 - f.width) // 2 + (f.width - 3 if app.mascot else 16)
    y0 = (32 - f.height) // 2 + (6 if app.mascot else 1)
    q = (t % 0.9) / 0.9
    if q < 0.85:
        y = y0 + int(q * 8)
        b[x, y] = WATER_LIGHT
        b[x, y + 1] = WATER_LIGHT


def atrisk_length(ev):
    return 3.6 + 1.8 * len(ev[2]) + 2.6


def atrisk(app, b, ev, t, now, dt):
    """N friends at risk -> each friend and their streak -> SEND HYPES!"""
    n, top = ev[1], ev[2]
    x0 = mascot_at_left(app, b, now, t)
    sweat(app, b, t)
    if t < 3.6:
        v = int(n * ease_out(t / 1.0) + 0.5)
        draw_box(b, x0, 64, 2, str(v), FL_GOLD, FB)
        typed(b, x0, 64, 14, "FRIENDS", t - 0.5, RED)
        typed(b, x0, 64, 23, "AT RISK", t - 1.0, RED)
        return
    k = int((t - 3.6) // 1.8)
    if k < len(top):
        name, st = top[k]
        u = t - 3.6 - k * 1.8
        typed(b, x0, 64, 8 if name_font(name, 64 - x0) is F5 else 9, name, u, WHITE,
              name_font(name, 64 - x0), 0.04)
        if u > 0.4:
            txt = str(st)
            w = 7 + text_width(txt)
            x = x0 + (64 - x0 - w) // 2
            draw_icon(b, x, 17, "streak")
            draw_text(b, x + 7, 17, txt, FL_GOLD)
        return
    draw_box(b, x0, 64, 8, "SEND", WHITE)
    draw_box(b, x0, 64, 17, "HYPES!", FL_GOLD if int(t * 3) % 2 else FL_YELLOW)


# ---------------- good morning (when night mode ends) ----------------
def sun(b, cx, cy, r, t):
    for yy in range(int(cy) - r, int(cy) + r + 1):
        for xx in range(int(cx) - r, int(cx) + r + 1):
            d = (xx - cx) ** 2 + (yy - cy) ** 2
            if d <= r * r and 0 <= xx < 64 and 0 <= yy < 32:
                b[xx, yy] = FL_GOLD if d > (r - 1.5) ** 2 else FL_YELLOW
    for k in range(8):
        a = k * math.pi / 4 + t * 0.7
        for rr in (r + 2, r + 3):
            px, py = int(cx + math.cos(a) * rr + 0.5), int(cy + math.sin(a) * rr + 0.5)
            if 0 <= px < 64 and 0 <= py < 32:
                b[px, py] = FL_ORANGE


def morning(app, b, ev, t, now, dt):
    """Sunrise in the middle of the panel, the sun climbs away, then the
    mascot says good morning (nothing crowds the text)."""
    if t < 2.4:
        rise = ease_out(t / 1.4)
        climb = ease((t - 1.6) / 0.8)
        cy = 40 - 24 * rise - 34 * climb
        fill(b, 0, 31, 64, 32, MAROON)                 # horizon
        sun(b, 32, cy, 8, t)
        if t < 2.0:
            return
    mascot_at_left(app, b, now, t)
    me = app.me or {}
    typed(b, 23, 64, 3, "GOOD", t - 2.3, WHITE)
    typed(b, 23, 64, 12, "MORNING", t - 2.6, FL_GOLD)
    if t < 5.0:
        name = upper_name(me.get("username"))
        typed(b, 23, 64, 21 if name_font(name, 41) is F5 else 22, name, t - 3.1, WHITE,
              name_font(name, 41))
    else:
        st = str(int(me.get("streak") or 0))
        w = 7 + text_width(st)
        x = 23 + (41 - w) // 2
        draw_icon(b, x, 21, "streak")
        draw_text(b, x + 7, 21, st, WHITE)


# ---------------- 1 year ago today ----------------
def yearago(app, b, ev, t, now, dt):
    miles, streak_now = ev[1], ev[2]
    if random.random() < 0.15:
        burst(app, random.uniform(4, 60), random.uniform(0, 6), 2, 4, (FL_GOLD, WHITE))
    particles(app, b, dt, gravity=4)
    typed(b, 0, 64, 1, "1 YEAR AGO TODAY", t, FL_GOLD, F3)
    if t < 1.2:
        return
    then = streak_now - 365
    top = ("DAY %d" % then) if then > 0 else "YOU DID"
    ic = "streak" if then > 0 else "today"
    w = 7 + text_width(top)
    x = (64 - w) // 2
    draw_icon(b, x, 8, ic)
    draw_text(b, x + 7, 8, top, WHITE)
    if t > 2.0:
        v = miles * ease_out((t - 2.0) / 0.9)
        draw_box(b, 0, 64, 17, "%.2f MI" % v, WHITE)
    if t > 3.4 and then > 0:
        draw_box(b, 0, 64, 26, "NOW DAY %d" % streak_now, RED, F3)


# ---------------- 9pm recap ----------------
def _line(b, y, icon, text, label, lcol=RED):
    iw = icon_width(icon)
    w = iw + 2 + text_width(text)
    x = (64 - w) // 2
    draw_icon(b, x, y, icon)
    draw_text(b, x + iw + 2, y, text, WHITE)
    draw_box(b, 0, 64, y + 8, label, lcol, F3)


def _recap_page(app, b, k, now):
    fill(b, 0, 0, 64, 32, BLACK)
    c, me = app.stats or {}, app.me or {}
    if k == 0:
        x0 = mascot_at_left(app, b, now, now)
        draw_box(b, x0, 64, 8, "TODAY'S", WHITE)
        draw_box(b, x0, 64, 17, "RECAP", RED)
    elif k == 1:
        done = app.mile_done()
        mi = float(me.get("miles_today") or 0)
        _line(b, 2, "check" if done else "today", "%.2f MI" % mi,
              "MY MILE: DONE" if done else "MY MILE: NOT YET", GREEN if done else RED)
        _line(b, 17, "streak", str(int(me.get("streak") or 0)), "MY STREAK")
    elif k == 2:
        _line(b, 2, "today", short(num(c, "miles_today")), "MI EVERYONE")
        _line(b, 17, "hypes", short(num(c, "hypes_today")), "HYPES TODAY")
    else:
        _line(b, 2, "badge", short(num(c, "badges_today")), "NEW BADGES")
        _line(b, 17, "friends", short(num(c, "new_friends_today")), "NEW FRIENDS")


def recap(app, b, ev, t, now, dt):
    page = 3.2
    k = min(3, int(t // page))
    u = t - k * page
    if u < 0.45 and k > 0:                           # slide the page up
        off = int(ease(u / 0.45) * 32)
        _recap_page(app, app.card_a, k - 1, now)
        _recap_page(app, app.card_b, k, now)
        blit(b, app.card_a, 0, -off)
        blit(b, app.card_b, 0, 32 - off)
    else:
        _recap_page(app, b, k, now)
    for j in range(4):                               # page dots
        b[58 + 2 * j - 1, 31] = WHITE if j == k else MAROON_DIM


# ---------------- new user (Flamey / runner) ----------------
def flamey_party(app, b, ev, t, now, dt):
    """Embers rise, Flamey floats up, glides aside, the count rolls over,
    he bobs under a fountain of embers."""
    old, new = ev[1], ev[2]
    f = app.mascot_frame(now, big=True)
    cx = (64 - f.width) // 2
    if t < 2.6:
        if random.random() < 0.8:                       # embers rise
            particles(app, b, dt, [random.uniform(4, 60), 32.0, random.uniform(-2, 2),
                                   random.uniform(-26, -14), random.uniform(0.9, 1.5), 0])
        else:
            particles(app, b, dt)
    if t < 0.6:
        return
    if t < 1.8:                                         # float up, settle
        u = (t - 0.6) / 1.2
        y = int(32 - (32 - 4) * ease_out(u) + 2 * math.sin(u * math.pi) * (1 - u))
        blit(b, f, cx, y, skip=BLACK)
        return
    home = 4
    if t < 2.6:                                         # glide to the left
        u = ease((t - 1.8) / 0.8)
        blit(b, f, int(cx + (home - cx) * u), 4, skip=BLACK)
        return
    bob = int(round(math.sin((t - 2.6) * math.pi * 1.6) * 1.5))
    blit(b, f, home, 4 + bob, skip=BLACK)
    if random.random() < 0.55:                          # ember fountain
        particles(app, b, dt, [home + f.width / 2 + random.uniform(-1, 1), 4.0 + bob,
                               random.uniform(-5, 9), random.uniform(-16, -9),
                               random.uniform(0.9, 1.4), 0])
    else:
        particles(app, b, dt)
    right = home + f.width + 1
    typed(b, right, 64, 1, "NEW", t - 2.6, WHITE, rate=0.07)
    typed(b, right, 64, 9, "USER!", t - 2.6 - 0.21, WHITE, rate=0.07)
    if t < 3.3:
        return
    r = ease((t - 3.3) / 1.0)                           # count rolls up
    n = int(old + (new - old) * r + 0.5)
    if r >= 1 and not app.popped:
        app.popped = True
        for _ in range(16):
            a = random.uniform(0, 6.28)
            app.particles.append([right + (64 - right) / 2, 21.0, math.cos(a) * 14,
                                  math.sin(a) * 10 - 4, random.uniform(0.6, 1.1), 0])
    draw_box(b, right, 64, 17, "#" + (str(n) if n < 100000 else short(n)),
             FL_YELLOW if r >= 1 else FL_ORANGE)
    typed(b, right, 64, 26, "WELCOME!", t - 4.6, RED, F3, 0.07)


def runner_party(app, b, ev, t, now, dt):
    old, new = ev[1], ev[2]
    if t < 0.9:                                         # shockwave rings
        for k, col in ((0, RED), (0.2, MAROON), (0.4, SPARK)):
            r = ease_out(max(0.0, t - k) / 0.5) * 40
            if r <= 0:
                continue
            for j in range(56):
                a = j * math.pi / 28
                x, y = int(32 + r * math.cos(a)), int(16 + r * 0.6 * math.sin(a))
                if 0 <= x < 64 and 0 <= y < 32:
                    b[x, y] = col
        return
    if t < 2.4:                                         # sprint across
        fill(app.card_b, 0, 0, 64, 32, BLACK)
        app.transition(app.card_b, app.card_b, (t - 0.9) / 1.5, now)
        return
    if random.random() < 0.5:
        burst(app, random.choice((8, 56)), random.uniform(5, 14), 6, 12, (SPARK, RED, MAROON))
    particles(app, b, dt)
    typed(b, 0, 64, 1, "NEW USER!", t - 2.4, WHITE, rate=0.07)
    r = ease((t - 3.2) / 1.0)
    n = int(old + (new - old) * r + 0.5)
    draw_box(b, 0, 64, 11, str(n) if n < 100000 else short(n), WHITE if r >= 1 else RED, FB)
    typed(b, 0, 64, 24, "WELCOME!", t - 4.6, RED, rate=0.07)


# ---------------- personal record ----------------
TROPHY = (
    ".GGGGGGGGGGG.",
    "G.GYYYYYYGG.G",
    "G.GYYYYYYGG.G",
    ".GGYYYYYYGGG.",
    "...GYYYYGG...",
    "....GYYGG....",
    ".....GGG.....",
    "......G......",
    "......G......",
    ".....GGG.....",
    "...OOOOOOO...",
    "...OGGGGGO...",
    "...OOOOOOO...",
)


def trophy(b, x, y):
    for yy, row in enumerate(TROPHY):
        for xx, ch in enumerate(row):
            if ch != ".":
                b[x + xx, y + yy] = {"G": FL_GOLD, "Y": FL_YELLOW, "O": FL_ORANGE}[ch]


def pr(app, b, ev, t, now, dt):
    """A gold trophy pops up; NEW PR! / what / the number."""
    what, value, head = ev[1], ev[2], ev[3]
    lift = int(round(10 * (1 - ease_out(t / 0.7))))
    trophy(b, 3, 9 + lift)                           # 13 tall: centred top to bottom
    if t > 0.7 and int(t * 6) % 3 == 0:              # glint on the cup
        b[6, 11] = SPARK
    if random.random() < 0.25:
        burst(app, random.uniform(20, 62), random.uniform(0, 6), 3, 6, (FL_GOLD, FL_YELLOW, WHITE))
    particles(app, b, dt, gravity=6)
    x0 = 18
    typed(b, x0, 64, 3, head, t - 0.6, FL_GOLD)
    typed(b, x0, 64, 13, what, t - 0.6 - 0.06 * len(head), RED, F3, 0.05)
    if t > 1.9:
        draw_box(b, x0, 64, 21, value, WHITE)


# ---------------- happy new year ----------------
def newyear(app, b, ev, t, now, dt):
    if random.random() < (0.16 if t < 7.0 else 0.04):
        burst(app, random.uniform(6, 58), random.uniform(3, 14), 18, 16,
              random.choice(((RED, WHITE), (FL_GOLD, FL_YELLOW), (RED, FL_GOLD),
                             (WHITE, FL_YELLOW))))
    particles(app, b, dt, gravity=10)
    typed(b, 0, 64, 3, "HAPPY NEW YEAR", t, FL_GOLD, F3)
    if t > 0.8:
        draw_box(b, 0, 64, 10, str(ev[1]), WHITE, FB)
    typed(b, 0, 64, 22, "LET'S GO!", t - 1.8, RED)


# Loaded from mad/extra.py only when one plays (keeps boot memory down).
LAZY = ("message", "holiday", "countdown", "medal", "review", "comment", "friendmile")

SCENES = {
    "message": (None, 20.0),
    "medal": (None, 8.0),
    "comment": (None, 20.0),
    "friendmile": (None, 9.0),
    "review": (None, 9.0),
    "holiday": (None, 7.5),
    "countdown": (None, 44.0),
    "nudge": (nudge, 6.8),
    "hype": (hype, 6.5),
    "friend": (friend, 6.5),
    "reminder": (reminder, 6.0),
    "mile": (mile, 7.5),
    "milestone": (milestone, 7.0),
    "recap": (recap, 12.8),
    "streak": (streak, 7.0),
    "finished": (finished, 7.0),
    "atrisk": (atrisk, 7.5),
    "morning": (morning, 8.0),
    "yearago": (yearago, 6.5),
    "pr": (pr, 7.0),
    "newyear": (newyear, 9.0),
}
