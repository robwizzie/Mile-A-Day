# The phone remote's live preview: the desk's own code (mad/*), drawing the
# box's real feed into a 64x32 bitmap, handed to the page as RGB bytes.
import json
import displayio
from mad import gfx
from mad.app import App

FB = displayio.Bitmap(64, 32, 32)
APP = None
RGB = bytearray(64 * 32 * 3)
LOOK = [0, 1]          # the style / mascot the page asked for


def start(feed, style, mascot, anniv="", bday=""):
    global APP
    APP = App(FB, style, mascot)
    if len(anniv) == 10:
        APP.anniv, APP.anniv_year = anniv[5:], int(anniv[:4])
    if len(bday) == 10:
        APP.bday, APP.bday_year = bday[5:], int(bday[:4])
    APP.set_data(json.loads(feed), True, 0.0)
    APP.mode, APP.mode_start = "dash", 0.0      # skip the boot logo
    APP.shown_users = APP.target_users
    APP.queue = []                               # nothing pops up on open
    APP.last_remind = 1e9
    APP.apply_season()
    LOOK[0], LOOK[1] = style, mascot
    APP.style, APP.mascot = style, mascot


def feed(data, now):
    APP.set_data(json.loads(data), True, now)
    if (APP.style, APP.mascot) != (LOOK[0], LOOK[1]):   # the page decides the look
        APP.style, APP.mascot = LOOK[0], LOOK[1]
        APP.mode, APP.mode_start = "dash", now


def choose(style, mascot, now):
    LOOK[0], LOOK[1] = style, mascot
    APP.style, APP.mascot = style, mascot
    APP.mode, APP.mode_start = "dash", now
    APP.ev = None
    APP.queue = []


def sleep(awake, start, end, now):
    """Mirror the box: its sleep hours (-1 = never sleeps) and whether it's
    awake right now (it may have been woken). awake=2: force awake (the page
    is previewing a new look)."""
    APP.night_hours = None if start < 0 or end < 0 else (start, end)
    APP.wake_until = 1e12 if awake else 0
    APP._update_night(now)


def frame(now):
    APP.tick(now)
    pal = gfx.palette
    d = FB.d
    out = RGB
    j = 0
    for i in range(2048):
        c = pal[d[i]]
        out[j] = c >> 16
        out[j + 1] = (c >> 8) & 255
        out[j + 2] = c & 255
        j += 3
    import js
    return js.Uint8Array.new(out)
