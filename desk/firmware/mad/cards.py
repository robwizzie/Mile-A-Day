# Mile A Day desk counter - dashboard cards that live outside app.py: the
# "me" card and the community mile goal. Kept small and resident; the
# celebrations in mad/fx.py load only while one plays.
from mad.gfx import (fit, fit_icon, MAROON_DIM, RED, WHITE, GREEN, FL_GOLD, F5, F3, text_width, draw_text,
                     draw_box, fill, draw_icon, icon_width, short, commas, upper_name)


def name_font(name, room):
    return F5 if text_width(name) <= room else F3


# ---------------- the "me" card (stat rotation) ----------------
def me_card(app, b, frac=1.0):
    me = app.me or {}
    name = upper_name(me.get("username"))
    fit(b, 0, 64, 3, name, WHITE)
    done = app.mile_done()
    text = "MILE DONE" if done else "NOT YET"
    w = 7 + text_width(text)
    x = (64 - w) // 2
    draw_icon(b, x, 12, "check" if done else "today", RED)
    draw_text(b, x + 7, 12, text, GREEN if done else RED)
    s = int(app.value(11) * frac + 0.5)
    t = "%d DAY%s" % (s, "" if s == 1 else "S")
    w = 7 + text_width(t)
    x = (64 - w) // 2
    draw_icon(b, x, 21, "streak")
    draw_text(b, x + 7, 21, t, WHITE)


# ---------------- community mile goal ----------------
def _bar(b, x0, x1, y, h, frac):
    fill(b, x0, y, x1, y + h, MAROON_DIM)
    x = x0 + int((x1 - x0) * max(0.0, min(1.0, frac)))
    fill(b, x0, y, x, y + h, RED)
    if x0 < x < x1:
        fill(b, x, y, x + 1, y + h, FL_GOLD)


def goal_card(app, b, frac=1.0):
    """NEXT GOAL / bar / miles to go: three rows, 4 px margins, 3 px gaps."""
    target, f = app.goal()
    draw_box(b, 0, 64, 4, short(target) + " MI GOAL", WHITE)
    _bar(b, 6, 58, 14, 4, f * frac)
    left = app.value(12)
    t = commas(left) + " TO GO"
    if text_width(t) > 56:
        t = short(left) + " TO GO"
    draw_box(b, 0, 64, 21, t, RED)


def goal_line(app, b, y, frac, x0, x1):
    target, f = app.goal()
    txt = short(target) + " GOAL"
    w = icon_width("miles") + 2 + text_width(txt)
    x = x0 + (x1 - x0 - w) // 2
    draw_icon(b, x, y, "miles")
    draw_text(b, x + icon_width("miles") + 2, y, txt, WHITE)
    _bar(b, x0 + 6, x1 - 6, y + 9, 3, f * frac)
