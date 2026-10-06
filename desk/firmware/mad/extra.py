# Mile A Day desk counter - the rarer scenes, imported only while one plays
# (and dropped again after): the New Year's Eve countdown, desk-to-desk
# messages, holiday greetings, new medals and (founder mode) new App Store
# reviews. Split out of fx.py to keep memory free.
import math
import random
from mad.gfx import (glyph, BLACK, MAROON_DIM, MAROON, RED, WHITE, FAR, SPARK, GREEN,
                     FL_YELLOW, FL_GOLD, FL_ORANGE, FL_DEEP, HEAT_L, HEAT_D, F5, F3, FB,
                     text_width, draw_text, draw_box, blit, fill, draw_icon, icon_width,
                     ease, ease_out)
from mad.fx import typed, particles, burst, mascot_at_left


def length(ev):
    kind = ev[0]
    if kind == "countdown":
        return countdown_length(ev)
    if kind in ("message", "comment"):
        return message_length(ev)
    if kind == "medal":
        w = rich_width(ev[1])
        return 7.5 if _medal_fit(ev[1]) else max(7.5, 1.4 + 2 * (46 + w) / SCROLL + 0.4)
    if kind == "review":
        w = rich_width(ev[2])
        return 7.5 if w <= 62 else max(7.5, 1.8 + 2 * (64 + w) / SCROLL + 0.4)
    return 7.5


# ---------------- New Year's Eve: the last 30 seconds ----------------
# Flamey: the FLAMEY DROP. He's the ball, ringed in chasing lights, sliding
# down the pole as the seconds run out; at midnight he lands, the screen
# flashes and he bounces under the fireworks.
# Runner: the MIDNIGHT SPRINT. He races the clock, speed lines growing, the
# finish tape slides in for the last 3 seconds and he bursts through it at
# midnight, leaping for joy under the fireworks.
# Both: a big countdown on the right (giant digits for the last 10 seconds),
# then HAPPY / NEW YEAR / 2027.
AFTER = 14.0          # how long the party runs after midnight


def draw_big(b, x, y, text, color, k=2):
    """FB digits scaled up k times (the last-10-seconds countdown)."""
    for ch in text:
        w, o = glyph(FB, ch)
        for yy in range(FB[1]):
            bits = FB[2][o + yy]
            for xx in range(w):
                if bits & (1 << (w - 1 - xx)):
                    fill(b, x + xx * k, y + yy * k, x + (xx + 1) * k, y + (yy + 1) * k, color)
        x += (w + 1) * k


def countdown_length(ev):
    return ev[1] + AFTER


def _ball_lights(b, cx, cy, rx, ry, now):
    for j in range(14):                       # chasing lights around the ball
        a = j * 6.283 / 14 + now * 2.2
        px, py = int(cx + math.cos(a) * rx + 0.5), int(cy + math.sin(a) * ry + 0.5)
        if 0 <= px < 64 and 0 <= py < 32 and b[px, py] == BLACK:
            b[px, py] = (FL_GOLD, WHITE, FL_YELLOW, RED)[(j + int(now * 6)) % 4]


def countdown(app, b, ev, t, now, dt):
    left = ev[1] - t                          # seconds to midnight
    year = ev[2]
    if left > 0:
        _count_phase(app, b, left, year, now, t, dt)
    else:
        _party_phase(app, b, -left, year, now, dt)


def _count_phase(app, b, left, year, now, t, dt):
    total = 30.0
    u = max(0.0, min(1.0, 1 - left / total))  # 0 -> 1 as midnight nears
    if app.mascot:                            # ---- the Flamey drop ----
        f = app.mascot_frame(now)             # medium Flamey is the ball
        cx = 11
        fill(b, cx, 0, cx + 1, 32, MAROON)    # the pole
        fill(b, cx - 3, 30, cx + 4, 32, FAR)  # its base
        y = int(-2 + u * (29 - f.height))
        _ball_lights(b, cx + 0.5, y + f.height / 2, f.width / 2 + 2, f.height / 2 + 1, now)
        blit(b, f, cx - f.width // 2, y, skip=BLACK)
    else:                                     # ---- the midnight sprint ----
        fill(b, 0, 30, 23, 31, MAROON)
        d = t * (30 + 50 * u)                 # he speeds up
        for x in range(23):
            if int(x + d) % 6 < 2:
                b[x, 31] = FL_GOLD
        f = app.runner[int(now / (0.075 - 0.03 * u)) % 8]
        x = 2
        for k, dy in enumerate((11, 14, 17, 20)):          # speed lines grow
            ln = int(2 + u * 7) - (k % 2) * 2
            if ln > 0:
                fill(b, max(0, x + 1 - ln), dy, x + 1, dy + 1, MAROON if k % 2 else MAROON_DIM)
        blit(b, f, x, 13, skip=BLACK)
        if left < 3.0:                        # the finish tape slides in
            tx = int(22 - (3.0 - left) / 3.0 * 3)
            for yy in range(13, 30):
                b[tx, yy] = WHITE if yy % 2 else RED
    fill(b, 23, 0, 24, 32, BLACK)
    secs = int(math.ceil(left))
    if secs > 10:
        draw_box(b, 24, 64, 4, "COUNTDOWN", RED, F3)
        draw_box(b, 24, 64, 11, str(secs), WHITE, FB)
        draw_box(b, 24, 64, 24, str(year - 1), FL_GOLD)
    else:
        frac = left - int(left)               # pulse on every tick
        col = FL_GOLD if secs % 2 else WHITE
        txt = str(secs)
        w = len(txt) * 16 - 2
        draw_big(b, 24 + (40 - w) // 2, 6, txt, col)
        if frac > 0.8:                        # a ring pops on each new second
            r = int((1 - frac) * 40) + 12
            for j in range(16):
                a = j * 6.283 / 16
                px, py = int(44 + math.cos(a) * r), int(16 + math.sin(a) * r * 0.7)
                if 24 <= px < 64 and 0 <= py < 32 and b[px, py] == BLACK:
                    b[px, py] = MAROON


def _party_phase(app, b, p, year, now, dt):
    if p < 0.25:                              # midnight flash
        fill(b, 0, 0, 64, 32, WHITE if p < 0.12 else FL_YELLOW)
        return
    if not app.popped:
        app.popped = True
        for x in (12, 32, 52):
            burst(app, x, 8, 24, 20, (FL_GOLD, WHITE, RED, FL_YELLOW))
    if random.random() < (0.3 if p < 8 else 0.12):          # fireworks
        burst(app, random.uniform(4, 60), random.uniform(2, 12), 18, 16,
              random.choice(((RED, WHITE), (FL_GOLD, FL_YELLOW), (RED, FL_GOLD),
                             (WHITE, FL_YELLOW), (GREEN, FL_GOLD))))
    particles(app, b, dt, gravity=10)
    if app.mascot:                            # Flamey lands big and bounces
        f = app.mascot_frame(now, big=True)
        hop = int(round(abs(math.sin(p * math.pi * 1.8)) * 3))
        blit(b, f, (22 - f.width) // 2, 32 - f.height - 1 - hop, skip=BLACK)
    else:                                     # the runner leaps for joy
        ph = (p * 1.6) % 1.0
        jump = math.sin(ph * math.pi) * 7
        f = app.run_jump[1] if jump > 2 else app.runner[int(now / 0.06) % 8]
        blit(b, f, 2, int(14 - jump), skip=BLACK)
        if jump < 0.5 and int(p * 1.6) != getattr(app, "_leap", -1):
            app._leap = int(p * 1.6)
            burst(app, 11, 29, 8, 10, (FL_GOLD, WHITE))
    typed(b, 23, 64, 2, "HAPPY", p - 0.3, FL_GOLD)
    typed(b, 23, 64, 11, "NEW YEAR", p - 0.7, WHITE, F3)
    if p > 1.4:
        col = FL_YELLOW if int(p * 4) % 2 else FL_GOLD
        draw_box(b, 23, 64, 18, str(year), col if p < 4 else WHITE, FB)


# ---------------- desk-to-desk message ----------------
TOKENS = {"[FIRE]": ("streak", RED), "[HEART]": ("heart", RED), "[CLAP]": ("hypes", WHITE),
          "[RUN]": ("running", WHITE)}
WAVE = (("#.#..", "#.#.#", "#####", ".###.", ".###."),
        ("..#.#", "#.#.#", "#####", ".###.", ".###."))


def _rich(text):
    """Split 'NICE MILE [FIRE]' into text runs and icon tokens."""
    out, i = [], 0
    while i < len(text):
        j = text.find("[", i)
        if j < 0:
            out.append(text[i:])
            break
        k = text.find("]", j)
        tok = text[j:k + 1] if k > j else ""
        if tok in TOKENS:
            if j > i:
                out.append(text[i:j])
            out.append(tok)
            i = k + 1
        else:
            out.append(text[i:j + 1])
            i = j + 1
    return out


def rich_width(text):
    w = 0
    for part in _rich(text):
        w += icon_width(TOKENS[part][0]) + 1 if part in TOKENS else text_width(part) + 1
    return max(0, w - 1)


def draw_rich(b, x, y, text, color=WHITE):
    for part in _rich(text):
        if part in TOKENS:
            name, col = TOKENS[part]
            if -10 < x < 64:
                draw_icon(b, x, y, name, col)
            x += icon_width(name) + 1
        else:
            if x < 64 and x + text_width(part) > 0:
                draw_text(b, x, y, part, color)
            x += text_width(part) + 1
    return x


SCROLL = 22.0         # px per second


def message_length(ev):
    return 1.0 + 2 * (41 + rich_width(ev[2])) / SCROLL + 0.4


def message(app, b, ev, t, now, dt):
    """FROM DAVE, then the message scrolls by twice while the mascot waves."""
    who, text = ev[1], ev[2]
    w = rich_width(text)
    if t > 1.0:
        x = int(64 - ((t - 1.0) * SCROLL) % (41 + w))
        draw_rich(b, x, 16, text)
    fill(b, 0, 0, 23, 32, BLACK)                    # the text slides out of view here
    x0 = mascot_at_left(app, b, now, t)
    hand = WAVE[int(now * 5) % 2] if (t % 4.0) < 2.4 else WAVE[0]
    for yy, row in enumerate(hand):                 # a little wave
        for xx, ch in enumerate(row):
            if ch == "#":
                b[17 + xx, 3 + yy] = WHITE
    head = who + " SAYS"
    if text_width(head, F3) > 64 - x0:
        head = who
    typed(b, x0, 64, 8, head, t - 0.2, RED, F3, 0.04)
    fill(b, x0 + 3, 13, 61, 14, MAROON_DIM)


# ---------------- a comment on a post I'm tagged in ----------------
BUBBLE = (".#####.", "#.....#", "#.....#", ".#####.", "..#....", ".#.....")


def comment(app, b, ev, t, now, dt):
    """DAVE / COMMENTED, then the comment scrolls by twice; a speech bubble
    by the mascot's head types its little dots."""
    who, text = ev[1], ev[2]
    w = rich_width(text)
    if t > 1.0:
        x = int(64 - ((t - 1.0) * SCROLL) % (41 + w))
        draw_rich(b, x, 19, text)
    fill(b, 0, 0, 23, 32, BLACK)                    # the text slides out of view here
    x0 = mascot_at_left(app, b, now, t)
    for yy, row in enumerate(BUBBLE):
        for xx, ch in enumerate(row):
            if ch == "#":
                b[16 + xx, 1 + yy] = WHITE
    for k in range(int(now * 3) % 4):               # . .. ... typing
        b[18 + k, 2] = FL_GOLD
    typed(b, x0, 64, 4, who, t - 0.2, RED, F3, 0.04)
    typed(b, x0, 64, 10, "COMMENTED", t - 0.2 - 0.04 * len(who), WHITE, F3, 0.04)
    fill(b, x0 + 3, 16, 61, 17, MAROON_DIM)


# ---------------- holiday morning greeting ----------------
HOLIDAY_TEXT = {
    "VALENTINE": ("HAPPY", "VALENTINE'S DAY"),
    "STPATRICK": ("LUCKY MILE", "HAPPY ST PAT'S"),
    "JULY4": ("HAPPY 4TH!", "OF JULY"),
    "THANKSGIVING": ("TURKEY TROT", "HAPPY THANKSGIVING"),
    "ANNIV": ("HAPPY BDAY", "MILE A DAY"),
}


def _anniv_text(app):
    """Two Mile A Day birthdays: the first commit (MAD_BIRTHDAY) and the
    App Store launch (MAD_ANNIVERSARY)."""
    md = (app.date or "")[5:10]
    try:
        year = int(app.date[:4])
    except (ValueError, TypeError):
        year = None
    if app.anniv and md == app.anniv and md != app.bday:
        yrs = year - app.anniv_year if year and app.anniv_year else 0
        return ("LAUNCH DAY", "%d YEAR%s LIVE!" % (yrs, "" if yrs == 1 else "S")
                if yrs > 0 else "ON THE APP STORE")
    yrs = year - app.bday_year if year and app.bday_year else 0
    return ("HAPPY BDAY", "MILE A DAY IS %d!" % yrs if yrs > 0 else "MILE A DAY")


def holiday(app, b, ev, t, now, dt):
    """Holiday morning: two lines of greeting, and below them the mascot
    chasing the holiday's friend (a heart, a clover, a flag, a turkey, a cake)."""
    from mad import decor
    look = ev[1]
    l1, l2 = HOLIDAY_TEXT.get(look, ("HAPPY", "HOLIDAYS"))
    if look == "ANNIV":
        l1, l2 = _anniv_text(app)
    if look == "THANKSGIVING" and text_width(l2, F3) > 62:
        l2 = "THANKSGIVING"
    f1 = F5 if text_width(l1) <= 62 else F3
    typed(b, 0, 64, 1 if f1 is F5 else 2, l1, t, FL_GOLD if look != "VALENTINE" else RED, f1)
    typed(b, 0, 64, 9, l2, t - 0.6, WHITE, F3, 0.04)
    d = t * 26
    for x in range(64):                             # the track
        b[x, 31] = MAROON if int(x + d) % 8 < 4 else MAROON_DIM
    f = app.mascot_frame(now)
    mx = int(-18 + 26 * ease_out(t / 1.2))
    my = 32 - f.height                   # feet on the track, head clear of the text
    if app.mascot:
        my -= int(round(abs(math.sin(t * math.pi * 2.4))))
    blit(b, f, mx, my, skip=BLACK)
    hx = int(70 - 34 * ease_out((t - 0.3) / 1.4))   # the friend runs ahead of him
    bob = int(round(abs(math.sin(t * math.pi * 3)) * 2))
    decor.holiday_friend(b, look, hx, 30 - bob, now)
    if random.random() < 0.15:
        burst(app, random.uniform(4, 60), random.uniform(16, 22), 4, 7)
    particles(app, b, dt, gravity=6)




# ---------------- a new medal (the owner's own) ----------------
# 13 x 16: a striped ribbon, a gold clasp and a gold medal with a white star.
MEDAL = ("....RWWWR....", "....RWWWR....", "....RWWWR....", ".....RWR.....",
         "....YYYYY....", "....KKKKK....", "..KKYYYYYKK..", ".KYYYYYYYYYK.",
         ".KYYYYSYYYYK.", "KYYYSSSSSYYYK", "KYYYYSSSYYYYK", "KYYYSSYSSYYYK",
         "KYYYYYYYYYYYK", ".KYYYYYYYYYK.", "..KKYYYYYKK..", "....KKKKK....")
MEDAL_C = {"R": RED, "W": WHITE, "Y": FL_GOLD, "S": WHITE, "K": FL_DEEP}
GOLD = (FL_GOLD, FL_YELLOW, FL_DEEP)


def _rows(b, x, y, rows, cmap):
    for yy, row in enumerate(rows):
        py = y + yy
        if 0 <= py < 32:
            for xx, ch in enumerate(row):
                if ch != "." and 0 <= x + xx < 64:
                    b[x + xx, py] = cmap[ch]


def shine(b, t, period=2.4, y0=0, y1=32):
    """A diagonal glint sweeping across everything gold."""
    p = (t % period) / 1.2
    if p > 1:
        return
    s = int(-32 + p * 128)
    for x in range(64):
        for k in range(3):
            y = s - x + k
            if y0 <= y < y1 and b[x, y] in GOLD:
                b[x, y] = SPARK if k == 1 else FL_YELLOW


def _split2(text):
    """Two balanced lines of the small font, or None."""
    if "[" in text or " " not in text:
        return None
    words = text.split(" ")
    best = None
    for i in range(1, len(words)):
        a, c = " ".join(words[:i]), " ".join(words[i:])
        w = max(text_width(a, F3), text_width(c, F3))
        if w <= 44 and (best is None or w < best[0]):
            best = (w, a, c)
    return best and best[1:]


def _medal_fit(name):
    return rich_width(name) <= 44 or _split2(name) is not None


def medal(app, b, ev, t, now, dt):
    """NEW MEDAL! - the medal drops in on its ribbon, its name beside it,
    and a gold shine runs across."""
    name = ev[1]
    x0, x1 = 18, 62
    if t > 0.9:
        w = rich_width(name)
        if w <= 44:
            if "[" in name:
                draw_rich(b, x0 + (x1 - x0 - w) // 2, 16, name)
            else:
                typed(b, x0, x1, 16, name, t - 0.9, WHITE, F5, 0.05)
        else:
            two = _split2(name)
            if two:
                typed(b, x0, x1, 14, two[0], t - 0.9, WHITE, F3, 0.04)
                typed(b, x0, x1, 21, two[1], t - 0.9 - 0.04 * len(two[0]), WHITE, F3, 0.04)
            else:
                x = int(64 - ((t - 0.9) * SCROLL) % (46 + w))
                draw_rich(b, x, 16, name)
                fill(b, 0, 10, x0, 32, BLACK)
    drop = int(round(-20 * (1 - ease_out(t / 0.8))))
    swing = int(round(math.sin(t * 7) * 1.5 * max(0.0, 1 - t / 1.6)))
    _rows(b, 3 + swing, 12 + drop, MEDAL, MEDAL_C)
    typed(b, 0, 64, 2, "NEW MEDAL!", t - 0.3, FL_GOLD)
    if 0.75 < t < 0.85 and not app.popped:
        app.popped = True
        burst(app, 9, 18, 16, 14, (FL_GOLD, FL_YELLOW, WHITE))
    if random.random() < 0.12:
        burst(app, random.uniform(20, 62), random.uniform(0, 8), 3, 6, (FL_GOLD, FL_YELLOW, WHITE))
    particles(app, b, dt, gravity=6)
    if t > 1.2:
        shine(b, t - 1.2)


# ---------------- founder mode: a new App Store review ----------------
STAR = ("...#...", "...#...", "#######", ".#####.", "..###..", ".##.##.", "##...##")


def review(app, b, ev, t, now, dt):
    """NEW REVIEW, the stars fill in one by one, and the title scrolls by."""
    stars, title = ev[1], ev[2]
    typed(b, 0, 64, 2, "NEW REVIEW", t, WHITE)
    for k in range(5):                              # 5 x 7 px + 4 x 3 px = 47 px
        on = k < stars and t > 0.8 + 0.2 * k
        pop = on and t < 0.95 + 0.2 * k            # each star hops as it lands
        _rows(b, 8 + k * 10, 11 - (1 if pop else 0), STAR, {"#": FL_GOLD if on else MAROON_DIM})
    if stars == 5 and 1.8 < t < 1.9 and not app.popped:
        app.popped = True
        burst(app, 32, 14, 20, 16, (FL_GOLD, FL_YELLOW, WHITE))
    particles(app, b, dt, gravity=8)
    if t > 1.8:
        shine(b, t - 1.8, 2.4, 10, 19)
    if t > 1.6 and title:
        w = rich_width(title)
        if w <= 62:
            draw_rich(b, (64 - w) // 2, 22, title)
        else:
            draw_rich(b, int(64 - ((t - 1.6) * SCROLL) % (64 + w)), 22, title)
