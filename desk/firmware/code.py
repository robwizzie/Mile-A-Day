# Mile A Day desk counter. The app itself (the "mad" package) is built into
# this board's custom CircuitPython firmware, so it runs from flash and
# leaves the RAM free. Settings live in settings.toml; see mad/main.py in
# the source folder for everything they do.
import sys
sys.path.insert(0, ".frozen")      # the built-in app wins over any old /mad files

# Hot fix (works with older firmware builds too): dropping a module that was
# never loaded must not crash - MicroPython raises KeyError, not AttributeError.
import mad.app


def _unload(name):
    import mad
    sys.modules.pop("mad." + name, None)
    try:
        delattr(mad, name)
    except Exception:
        pass


mad.app.unload = _unload

# Hot fix (built into firmware from 2026-10-06 on): Flamey's whole flame shows
# in the evening; worry shows as trembling, burned-down colour and a sweat drop.
import math
from mad.app import App, DIM_NERVOUS, DIM_PANIC
from mad.gfx import BLACK, blit, FL_YELLOW, FL_GOLD, FL_ORANGE


def _draw_mascot(self, b, f, x, y, now, skip=BLACK):
    """Blit the mascot showing today's mood: when the mile isn't done in the
    evening Flamey trembles, his bright tones burn down and he sweats (the
    runner tires and sweats); once it's done Flamey roars with rising
    embers. (His whole flame always shows: a cut-off tip read as a bug.)"""
    m = self.mood(now)
    if self.mascot and m in ("nervous", "panic"):
        jit = ((0, 0, 1, 0, 0, -1)[int(now * 6) % 6] if m == "nervous"
               else (-1, 0, 1, 0)[int(now * 12) % 4])
        # a weaker flame: his bright yellows burn down to orange
        # (nervous) or deep red (panic) - like Flamey's health
        cmap = DIM_NERVOUS if m == "nervous" else DIM_PANIC
        for yy in range(f.height):
            py = y + yy
            if 0 <= py < 32:
                for xx in range(f.width):
                    v = f[xx, yy]
                    px = x + jit + xx
                    if v and 0 <= px < 64:
                        b[px, py] = cmap.get(v, v)
    else:
        blit(b, f, x, y, skip=skip)
    if m in ("nervous", "panic"):          # a little sweat drop
        sx = x + (f.width - 2 if self.mascot else 16)
        sy0 = y + (f.height // 3 if self.mascot else 1)
        q = (now % (0.9 if m == "nervous" else 0.6)) / (0.9 if m == "nervous" else 0.6)
        for dy in (0, 1):
            py = sy0 + int(q * 7) + dy
            if 0 <= sx < 64 and 0 <= py < 32 and q < 0.85:
                b[sx, py] = 26           # WATER_LIGHT
    elif m == "roar" and self.mascot:      # embers rising up both sides of him
        for k in range(6):
            ph = (now * 1.1 + k * 0.19) % 1.0
            side = -1 if k % 2 else 1
            ex = x + f.width // 2 + side * (f.width // 2 - 1 + int(ph * 3)) \
                + int(math.sin(now * 4 + k) * 1)
            ey = y + f.height // 2 - int(ph * (f.height // 2 + 4))
            if 0 <= ex < 64 and 0 <= ey < 32 and b[ex, ey] == BLACK:
                b[ex, ey] = FL_YELLOW if ph < 0.35 else FL_GOLD if ph < 0.7 else FL_ORANGE


App.draw_mascot = _draw_mascot

import mad.main                    # starts the counter
