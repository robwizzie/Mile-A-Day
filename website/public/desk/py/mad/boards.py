# Mile A Day desk counter - the score boards: the friends' streak leaderboard,
# when people run (today by the hour), my last run replayed mile by mile, my
# personal records, the community ODOMETER style and the two-desk live race.
# Every number comes from the feed. Imported only while one is on screen.
import math
from mad.gfx import (fit, fit_icon, miles_text, BLACK, MAROON_DIM, MAROON, RED, WHITE, FAR, SPARK,
                     GREEN, FL_YELLOW, FL_GOLD, FL_ORANGE, HEAT_D, F5, F3, FB, glyph, text_width,
                     draw_text, ink, draw_box, fill, draw_icon, icon_width, commas, short, ease,
                     ease_out, upper_name, crown)

RANK_COL = (FL_GOLD, WHITE, FL_ORANGE, FAR, FAR, FAR)
FLAME3 = (".#.", "##.", "###", "#.#", "###")        # a tiny 3x5 flame for table rows


def _flame3(b, x, y):
    for yy, row in enumerate(FLAME3):
        for xx, ch in enumerate(row):
            if ch == "#":
                b[x + xx, y + yy] = FL_GOLD if yy < 2 else FL_ORANGE


def _clock(secs):
    secs = int(secs)
    h, m, s = secs // 3600, secs // 60 % 60, secs % 60
    return "%d:%02d:%02d" % (h, m, s) if h else "%d:%02d" % (m, s)


# ======================= friends' streak leaderboard =======================
def leaders(app):
    """Up to 5 rows to draw: the top 5, or the top 4 + me when I'm lower."""
    rows = [r for r in ((app.me and getattr(app, "leaders", None)) or ()) if isinstance(r, dict)]
    top = [r for r in rows if int(r.get("rank") or 99) <= 5]
    mine = [r for r in rows if r.get("me") and int(r.get("rank") or 99) > 5]
    if mine:
        top = top[:4] + mine[:1]
    return top[:5]


def my_rank(app):
    for r in (getattr(app, "leaders", None) or ()):
        if isinstance(r, dict) and r.get("me"):
            return int(r.get("rank") or 0)
    return 0


def leaders_card(app, b, frac=1.0, now=0.0):
    """An arcade high-score table: rank, name, streak + flame. My row lit."""
    rows = leaders(app)
    n = len(rows)
    y0 = (32 - (n * 6 - 1)) // 2
    for k, r in enumerate(rows):
        if frac < 1.0 and k > int(frac * (n + 0.5)):          # rows type in, arcade style
            break
        y = y0 + k * 6
        rank = int(r.get("rank") or 0)
        mine = bool(r.get("me"))
        if mine:
            fill(b, 0, y - 1, 64, y + 6, MAROON)
        col = RANK_COL[min(rank, 6) - 1] if rank else FAR
        rt = str(rank)
        draw_text(b, 6 - text_width(rt, F3), y, rt, (FL_YELLOW if int(now * 3) % 2 else FL_GOLD) if mine else col, F3)
        st = commas(int(r.get("streak") or 0))
        sw = text_width(st, F3)
        draw_text(b, 58 - sw, y, st, WHITE, F3)
        _flame3(b, 60, y)
        fit(b, 9, 55 - sw, y, upper_name(r.get("name"), 16), WHITE if mine else (col if rank == 1 else RED), F3, now)
    if rows and int(rows[0].get("rank") or 0) == 1 and frac >= 1.0:
        b[0, y0 + 2] = SPARK if int(now * 2) % 2 else FL_GOLD   # a glint by #1


def leaders_line(app, b, y, frac, x0, x1):
    r, n = my_rank(app), len(getattr(app, "leaders", None) or ())
    txt = "#%d" % r if r else "-"
    fit_icon(b, x0, x1, y, "streak", txt, WHITE)
    draw_box(b, x0, x1, y + 8, "FRIEND RANK", RED, F3)


# ======================= when people run (today, by hour) =======================
def _bins(app):
    h = [int(x or 0) for x in (getattr(app, "hours", None) or ())][:24]
    h += [0] * (24 - len(h))
    return [h[2 * k] + h[2 * k + 1] for k in range(12)]


def _peak_text(app):
    h = [int(x or 0) for x in (getattr(app, "hours", None) or ())][:24]
    if not any(h):
        return "NO RUNS YET", 0
    p = h.index(max(h))
    if 4 <= p <= 8:
        mood = "MORNING RUSH"
    elif 11 <= p <= 13:
        mood = "LUNCH RUNS"
    elif p >= 20 or p <= 1:
        mood = "NIGHT OWLS"
    else:
        mood = ""
    ap = "%d%s" % (p % 12 or 12, "AM" if p < 12 else "PM")
    return mood, ap


def hours_card(app, b, frac=1.0, now=0.0):
    """12 two-hour bars (Eastern), the current one lit; peak hour below."""
    bins = _bins(app)
    top = max(bins + [1])
    s = app.local_seconds(now)                     # (the boxes live on Eastern time too)
    cur = int(s // 7200) if s is not None else -1
    x = 3
    for k, v in enumerate(bins):
        h = int(round(14 * v / top * frac))
        if v and h < 1:
            h = 1
        if h:
            fill(b, x, 18 - h, x + 4, 18, RED if k == cur else HEAT_D)
            if k == cur and int(now * 2) % 2:
                fill(b, x, 18 - h, x + 4, 19 - h, FL_GOLD)
        else:
            fill(b, x, 17, x + 4, 18, MAROON_DIM)
        x += 5
    for k, lab in ((0, "12A"), (3, "6A"), (6, "12P"), (9, "6P")):
        draw_box(b, 3 + 5 * k - 4, 3 + 5 * k + 8, 20, lab, FAR, F3)
    mood, ap = _peak_text(app)
    txt = ("%s %s" % (mood, ap)).strip() if mood else ("BUSIEST %s" % ap if ap else "NO RUNS YET")
    fit(b, 0, 64, 26, txt, WHITE if mood else RED, F3, now)


def hours_line(app, b, y, frac, x0, x1):
    mood, ap = _peak_text(app)
    fit_icon(b, x0, x1, y, "running", ap or "-", WHITE)
    draw_box(b, x0, x1, y + 8, "BUSIEST HOUR", RED, F3)


# ======================= my last run, mile by mile =======================
def last_run(app):
    r = (app.me or {}).get("last_run")
    return r if isinstance(r, dict) else None


def splits_card(app, b, frac=1.0, now=0.0, run=None):
    """MY RUN 3.10 MI / one bar per full mile (taller = faster), the fastest
    in gold / BEST 7:50. `run`: a test run (its header says TEST)."""
    r = run or last_run(app)
    if not r:
        return
    miles = float(r.get("miles") or 0)
    secs = int(r.get("seconds") or 0)
    walk = r.get("kind") == "walk"
    sp = [int(x) for x in (r.get("splits") or ()) if isinstance(x, int) and x > 0][:20]
    who = "TEST" if run else ("MY WALK" if walk else "MY RUN")
    head = "%s %s MI" % (who, miles_text(miles, 40, F3).replace(" MI", ""))
    if not sp:                                     # under a mile: distance and time
        draw_box(b, 0, 64, 4, who, RED, F3)
        draw_box(b, 0, 64, 12, miles_text(miles * frac, 62), WHITE)
        if secs:
            draw_box(b, 0, 64, 22, _clock(secs), FAR, F3)
        return
    fit(b, 0, 64, 1, head, WHITE, F3, now)
    n = len(sp)
    bw = max(1, min(7, (60 - (n - 1)) // n))
    w = n * bw + (n - 1)
    x = (64 - w) // 2
    fast, slow = min(sp), max(sp)
    best = sp.index(fast)
    shown = frac * n
    for k, p in enumerate(sp):
        if k >= shown:
            break
        grow = min(1.0, shown - k)
        h = 13 if slow == fast else 5 + int(round(8 * (slow - p) / (slow - fast)))
        h = max(1, int(h * ease_out(grow)))
        col = FL_GOLD if k == best else RED
        fill(b, x, 21 - h, x + bw, 21, col)
        if k == best and grow >= 1.0 and int(now * 3) % 3 == 0:
            b[x + bw // 2, 21 - h] = SPARK                  # the fastest mile glows
        x += bw + 1
    fill(b, (64 - w) // 2, 21, (64 - w) // 2 + w, 22, MAROON_DIM)
    if frac >= 1.0 or shown > best + 1:
        t = "BEST " + _clock(fast)
        fit(b, 0, 64, 24, t, FL_GOLD, F5, now)


def splits_line(app, b, y, frac, x0, x1):
    r = last_run(app) or {}
    sp = [int(x) for x in (r.get("splits") or ()) if isinstance(x, int) and x > 0]
    txt = ("BEST " + _clock(min(sp))) if sp else miles_text(float(r.get("miles") or 0), x1 - x0 - 8)
    fit_icon(b, x0, x1, y, "running", txt, WHITE)
    draw_box(b, x0, x1, y + 8, "MY LAST RUN", RED, F3)


# ======================= my personal records =======================
def records(app):
    me = app.me or {}
    out = []
    fm = me.get("fastest_mile")
    if fm:
        out.append(("BEST MILE", _clock(fm)))
    lr = me.get("longest_run")
    if lr:
        out.append(("LONG RUN", "%.1f" % (int(float(lr) * 10) / 10)))
    ls = me.get("longest_streak")
    if ls:
        out.append(("TOP STREAK", commas(int(ls))))
    return out


def records_card(app, b, frac=1.0, now=0.0):
    rows = records(app)
    n = len(rows)
    if not n:
        return
    y0 = (32 - (n * 10 - 3)) // 2
    for k, (label, val) in enumerate(rows):
        y = y0 + k * 10
        f = F5 if text_width(label, F3) + 3 + text_width(val) <= 62 else F3
        draw_text(b, 1, y + (1 if f is F5 else 0), label, RED, F3)
        vw = text_width(val, f)
        draw_text(b, 63 - vw, y, val, FL_GOLD if k == 0 and frac >= 1.0 and int(now * 2) % 4 == 0 else WHITE, f)
        if k < n - 1:
            fill(b, 1, y + 8, 63, y + 9, MAROON_DIM)


def records_line(app, b, y, frac, x0, x1):
    rows = records(app)
    if rows:
        fit(b, x0, x1, y, "%s %s" % rows[0], WHITE)
    draw_box(b, x0, x1, y + 8, "MY RECORDS", RED, F3)


# ======================= goal ETA =======================
def goal_eta(app):
    """'IN 12 DAYS' at the community's real pace (last 7 full days), or None."""
    st = app.stats or {}
    try:
        per_day = float(st.get("miles_7d") or 0) / 7.0
    except (ValueError, TypeError):
        return None
    if per_day <= 0:
        return None
    left = app.value(12)
    days = left / per_day
    if days > 400:
        return None
    if days < 1:
        h = max(1, int(days * 24 + 0.5))
        return "IN %d HOUR%s" % (h, "" if h == 1 else "S")
    d = int(days + 0.5)
    return "IN %d DAY%s" % (d, "" if d == 1 else "S")


# ======================= ODOMETER style =======================
COMPARE = (
    (2790.0, "NJ TO LA %sX"),
    (24901.0, "AROUND EARTH %sX"),
    (26.2, "%s MARATHONS"),
    (238855.0, "%s%% TO THE MOON"),
)


def compare_text(total, k):
    d, fmt = COMPARE[k % len(COMPARE)]
    if "%%" in fmt:
        return fmt % ("%d" % int(100 * total / d))
    x = total / d
    if x >= 100:
        v = commas(int(x))
    elif x >= 10:
        v = "%d" % int(x)
    else:
        v = "%.1f" % (int(x * 10) / 10)
    return fmt % v


def _digit(b, x, y, ch, y0, y1, color):
    """One FB digit with its top at y, painted only on rows y0..y1-1."""
    w, o = glyph(FB, ch)
    data = FB[2]
    for py in range(FB[1]):
        yy = y + py
        if y0 <= yy < y1:
            bits = data[o + py]
            for px in range(w):
                if bits & (1 << (w - 1 - px)):
                    b[x + px, yy] = color


def odometer(app, b, now, t):
    """TOTAL MILES on rolling wheels. When real miles land, the wheels roll
    up to the new total (the lower wheel turning the next one over)."""
    fill(b, 0, 0, 64, 32, BLACK)
    total = int((app.stats or {}).get("total_miles") or 0)
    od = getattr(app, "_odo", None)
    if od is None or t < 0.05 and od[1] != total:
        od = [0, total, now, 2.6]                  # entering: roll up from 0
    elif od[1] != total:
        cur = od[0] + (od[1] - od[0]) * ease(min(1.0, (now - od[2]) / od[3]))
        od = [cur, total, now, 2.0 if total - cur < 50 else 2.6]
    app._odo = od
    u = min(1.0, (now - od[2]) / od[3])
    shown = od[0] + (od[1] - od[0]) * ease(u)
    n = max(6, len(str(total)))
    w = n * 9 - 1
    x0 = (64 - w) // 2
    fill(b, x0 - 2, 1, x0 + w + 2, 2, MAROON_DIM)          # the wheel housing
    fill(b, x0 - 2, 15, x0 + w + 2, 16, MAROON_DIM)
    lead = True
    for i in range(n):
        k = n - 1 - i                                       # 10^k place
        p = 10 ** k
        pos = shown / p
        whole = int(pos)
        frac = 0.0
        if k == 0:
            frac = pos - whole
        else:
            under = shown - whole * p                       # the lower wheels' reading
            if under > p - 1:
                frac = under - (p - 1)
        d = whole % 10
        lead = lead and whole == 0 and k > 0
        x = x0 + i * 9
        fill(b, x, 2, x + 8, 15, BLACK)
        col = FAR if lead else WHITE
        off = int(frac * 13)
        _digit(b, x, 3 - off, str(d), 2, 15, col)
        if off:
            _digit(b, x, 16 - off, str((d + 1) % 10), 2, 15, col)
        if i < n - 1:
            fill(b, x + 8, 2, x + 9, 15, MAROON_DIM)
    draw_box(b, 0, 64, 18, "TOTAL MILES", RED, F3)
    k = int(t // 4.0)
    fit(b, 0, 64, 25, compare_text(od[1], k), WHITE, F3, now)


# ======================= two desks, both out running =======================
def duel(app, b, now, t, v):
    """Me vs the other desk's owner, both on a tracked run: two lanes, real
    live distances, a crown on whoever's further."""
    r = app.rival or {}
    dt = min(0.1, max(0.0, now - getattr(app, "_dv_last", now)))
    app._dv_last = now
    target = float(r.get("live_miles") or 0)
    app._rv_shown = getattr(app, "_rv_shown", target)
    app._rv_shown += (target - app._rv_shown) * min(1.0, dt * 1.5)
    rv = app._rv_shown
    top = max(v, rv, 1.0)
    lead = 0 if v > rv + 0.005 else 1 if rv > v + 0.005 else -1
    names = (upper_name((app.me or {}).get("username"), 12), upper_name(r.get("name"), 12))
    walks = ((app.me or {}).get("live_kind") == "walk", r.get("live_kind") == "walk")
    for lane, (y, miles) in enumerate(((0, v), (16, rv))):
        fit(b, 1, 34, y + 1, names[lane], WHITE if lane == 0 else RED, F3, now)
        txt = miles_text(miles, 28, F5)
        lo, hi = ink(txt)
        draw_text(b, 63 - (hi - lo) - lo, y, txt, FL_GOLD if lane == lead else WHITE)
        g = y + 15
        d = t * (12 if walks[lane] else 26)
        for x in range(64):
            if int(x + d) % 6 < 3:
                b[x, g] = MAROON_DIM
        x = 1 + int(50 * min(1.0, miles / top))
        bob = int(t * 8 + lane) % 2
        if lane == 0 and app.mascot:
            draw_icon(b, x, y + 8 - bob, "streak")
        else:
            draw_icon(b, x, y + 8 - bob, "running", WHITE if lane == 0 else FAR)
        if lane == lead and int(now * 3) % 3 == 0:
            b[min(63, x + 7), y + 8 - bob] = SPARK          # the leader sparkles
