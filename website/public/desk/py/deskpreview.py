# The phone remote's live preview: the desk's own code (mad/*), drawing the
# box's real feed into a 64x32 bitmap, handed to the page as RGB bytes.
import json
import displayio
from mad import gfx
from mad.app import App

FB = displayio.Bitmap(64, 32, 32)
APP = None
RGB = bytearray(64 * 32 * 3)


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


def feed(data, now):
    APP.set_data(json.loads(data), True, now)


def choose(style, mascot, now):
    APP.style, APP.mascot = style, mascot
    APP.mode, APP.mode_start = "dash", now
    APP.ev = None
    APP.queue = []


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
