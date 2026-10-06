# Mile A Day desk counter - my streak heatmap (the HEAT card and the
# Spotlight line). Small on its own so the rarer scenes in extra.py can be
# unloaded between events.
from mad.gfx import (MAROON_DIM, MAROON, RED, WHITE, FAR, FL_GOLD, HEAT_L, HEAT_D, F3,
                     draw_box, draw_text, fill)


# ---------------- my streak heatmap ----------------
def _dow_mon(date):
    """0 = Monday ... 6 = Sunday."""
    try:
        y, m, d = int(date[:4]), int(date[5:7]), int(date[8:10])
    except (ValueError, TypeError):
        return 6
    t = (0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4)
    if m < 3:
        y -= 1
    return ((y + y // 4 - y // 100 + y // 400 + t[m - 1] + d) % 7 + 6) % 7


def heat_color(mi):
    """Light for a mile, deeper the further you went (MAROON = 5+ miles)."""
    if mi == -1:
        return FL_GOLD                          # a streak token saved the day
    if mi < 0.95:
        return None
    return HEAT_L if mi < 1.5 else RED if mi < 3 else HEAT_D if mi < 5 else MAROON


def heat_card(app, b, frac=1.0, now=0.0):
    """GitHub-style: one square per day, weeks as columns (Mon at the top),
    today blinking in the last column."""
    days = (app.me or {}).get("days") or ()
    n = len(days)
    end = 9 * 7 + _dow_mon(app.date or "")
    shown = int(n * frac + 0.5)
    for a in range(n):                          # a = days ago
        i = n - 1 - a
        if i >= shown:
            continue
        col, row = divmod(end - a, 7)
        px, py = 2 + col * 4, 2 + row * 4
        c = heat_color(days[i])
        if a == 0 and int(now * 2) % 2:         # today blinks
            fill(b, px, py, px + 3, py + 3, WHITE if c is None else c)
            if c is not None:
                b[px + 1, py + 1] = WHITE
        elif c is None:
            b[px + 1, py + 1] = MAROON_DIM      # a missed day: just a faint dot
        else:
            fill(b, px, py, px + 3, py + 3, c)
    done = app.value(13)
    draw_box(b, 43, 64, 3, str(int(done * frac + 0.5)), WHITE)
    draw_box(b, 43, 64, 11, "OF %d" % n, FAR, F3)
    for k, c in enumerate((HEAT_L, RED, HEAT_D, MAROON)):   # legend: 1 mi .. 5+ mi
        fill(b, 45 + k * 4, 19, 48 + k * 4, 22, c)
    draw_text(b, 45, 25, "1", FAR, F3)
    draw_text(b, 55, 25, "5+", FAR, F3)


def heat_line(app, b, y, frac, x0, x1):
    """The Spotlight version: one 1-px column per day across the panel."""
    days = (app.me or {}).get("days") or ()
    n = len(days)
    x = x0 + (x1 - x0 - n) // 2
    blink = int(time_now() * 2) % 2
    for i, mi in enumerate(days):
        if i >= int(n * frac + 0.5):
            break
        c = heat_color(mi)
        if i == n - 1 and blink:
            c = WHITE
        if c is None:
            b[x + i, y + 6] = MAROON_DIM
        else:
            fill(b, x + i, y + 1, x + i + 1, y + 7, c)
    draw_box(b, x0, x1, y + 8, "LAST %d DAYS" % n, RED, F3)


def time_now():
    from mad.gfx import clock
    return clock()
