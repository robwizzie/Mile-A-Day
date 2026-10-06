# MILE A DAY desk counter - live dashboard
# CircuitPython 10.x, Adafruit Matrix Portal M4, 64x32 HUB75 panel.
#
# The "mad" package (this file: hardware, Wi-Fi, buttons; gfx: colours,
# fonts, icons; app: data + dashboard styles; modes: Arcade, Campfire, Race,
# Clock; fx/extra: alerts and celebrations; art: pixels from build_art.py)
# is frozen into the board's custom firmware. code.py on CIRCUITPY just
# starts it.
#
# Buttons on the back of the Matrix Portal:
#   UP   press -> next style: CLASSIC, SPOTLIGHT, ARCADE, BIG, CAMPFIRE,
#               RACE, CLOCK (Race and Clock need a display key)
#   DOWN press -> switch mascot: RUNNER <-> FLAMEY
#   UP   hold  -> demo: play every alert once
#   DOWN hold  -> play the stat show now
#   (at night the first press just wakes the screen up for 2 minutes)
# Seasonal looks switch by date on their own: jack-o'-lantern Flamey and a
# pumpkin-head runner Oct 25-31, Santa hats Dec 1-26, fireworks at New Year.
#   (with matching scenery on every screen: snow, sleigh, bats, candy corn...)
#   Plus Valentine's, St. Patrick's, July 4th, Thanksgiving, and Mile A Day's
#   two birthdays: MAD_BIRTHDAY = "YYYY-MM-DD" (the first commit) and
#   MAD_ANNIVERSARY = "YYYY-MM-DD" (the App Store launch).
# With a display key, Flamey wears what you've got on in the app's Flamey's
# Closet (colour, hat, glasses, costume), new medals get a party, and admin
# desks get a heads-up for each new App Store review.
#   MAD_SEASON = "OFF" turns them off; HALLOWEEN, SANTA, NEWYEAR, VALENTINE,
#   STPATRICK, JULY4, THANKSGIVING or ANNIV forces one (to preview it).
# Your choice is remembered through power cuts (stored in the board's
# non-volatile memory). Defaults can also be set in settings.toml:
#   MAD_STYLE = "SPOTLIGHT"     MAD_MASCOT = "FLAMEY"     MAD_NIGHT = "22-7"
#
# settings.toml also holds CIRCUITPY_WIFI_SSID / CIRCUITPY_WIFI_PASSWORD
# (2.4 GHz) and MAD_DISPLAY_KEY: this board's personal key (Admin ->
# Displays). With it the board shows its owner's mile, streak, nudges and
# hypes; without it, public community stats only. The key is only ever sent
# over HTTPS, in a header, to the Mile A Day API, and is never printed.
# Status light: blue = connecting, green = live, red = can't reach Wi-Fi/API.

RUN = __name__ in ("__main__", "mad.main")   # (the simulator imports it without running)
import os
import time
import board
import displayio
import framebufferio
import rgbmatrix
import gc

# The matrix needs one big contiguous buffer: grab it before anything else
# fragments memory (this was the MemoryError on boot).
MATRIX = None
DISPLAY = None
if RUN:
    displayio.release_displays()
    gc.collect()
    MATRIX = rgbmatrix.RGBMatrix(
        width=64, height=32, bit_depth=6,      # 6: fine enough steps to dim way down at night
        rgb_pins=[board.MTX_R1, board.MTX_G1, board.MTX_B1,
                  board.MTX_R2, board.MTX_G2, board.MTX_B2],
        addr_pins=[board.MTX_ADDRA, board.MTX_ADDRB, board.MTX_ADDRC,
                   board.MTX_ADDRD],
        clock_pin=board.MTX_CLK, latch_pin=board.MTX_LAT,
        output_enable_pin=board.MTX_OE,
    )
    DISPLAY = framebufferio.FramebufferDisplay(MATRIX, auto_refresh=False)
    # ...and the five 64x32 screen buffers (2 KB each, contiguous) while the
    # heap is still in one piece: "allocating 2048 bytes" failed here later.
    BUFS = [displayio.Bitmap(64, 32, 32) for _ in range(5)]
    gc.collect()

STAGE = ["IMPORT"]           # where we are, for the crash screen
# Imported after the matrix buffer is allocated (see above).
from mad.gfx import (palette, draw_text, F3, RED, WHITE, DEFAULT_URL, FEED_URL,
                     REFRESH_SECONDS, FEED_SECONDS)
try:
    from mad.app import App, STYLES, MASCOTS
except MemoryError as _e:
    App = None
    IMPORT_ERROR = _e

NVM_TAG = 0xAD


def load_choice():
    """(style, mascot): last button choice, else settings.toml, else defaults."""
    try:
        import microcontroller
        m = microcontroller.nvm
        if m is not None and m[0] == NVM_TAG and m[1] < len(STYLES) and m[2] < len(MASCOTS):
            return m[1], m[2]
    except Exception as e:
        print("nvm read:", e)
    style = (os.getenv("MAD_STYLE") or "CLASSIC").upper()
    mascot = (os.getenv("MAD_MASCOT") or "FLAMEY").upper()
    return (STYLES.index(style) if style in STYLES else 0,
            MASCOTS.index(mascot) if mascot in MASCOTS else 1)


def display_key():
    """MAD_DISPLAY_KEY if it looks like a real key, else None."""
    k = (os.getenv("MAD_DISPLAY_KEY") or "").strip()
    ok = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
    if len(k) == 48 and k.startswith("madk_") and all(c in ok for c in k[5:]):
        return k
    return None


def night_hours():
    """MAD_NIGHT = "22-7" (default) or "OFF" -> (start, end) minutes or None."""
    v = (os.getenv("MAD_NIGHT") or "22-7").strip().upper()
    if v in ("OFF", "NO", "0", ""):
        return None
    try:
        a, b = (int(x) % 24 for x in v.split("-"))
        return (a * 60, b * 60)
    except ValueError:
        return (22 * 60, 7 * 60)


def load_celebrated():
    """The last streak milestone this board celebrated (survives reboots)."""
    try:
        import microcontroller
        m = microcontroller.nvm
        if m is not None and m[0] == NVM_TAG:
            return m[3] << 8 | m[4]
    except Exception as e:
        print("nvm read:", e)
    return 0


def save_celebrated(n):
    try:
        import microcontroller
        if microcontroller.nvm is not None and microcontroller.nvm[0] == NVM_TAG:
            microcontroller.nvm[3:5] = bytes(((n >> 8) & 255, n & 255))
    except Exception as e:
        print("nvm write:", e)


def load_desk_rev():
    """The last phone-remote change this board applied (nvm bytes 5-6)."""
    try:
        import microcontroller
        m = microcontroller.nvm
        if m is not None and m[0] == NVM_TAG:
            return m[5] << 8 | m[6]
    except Exception as e:
        print("nvm read:", e)
    return 0


def save_desk_rev(n):
    try:
        import microcontroller
        if microcontroller.nvm is not None and microcontroller.nvm[0] == NVM_TAG:
            microcontroller.nvm[5:7] = bytes(((n >> 8) & 255, n & 255))
    except Exception as e:
        print("nvm write:", e)


def save_choice(style, mascot):
    try:
        import microcontroller
        if microcontroller.nvm is not None:
            microcontroller.nvm[0:3] = bytes((NVM_TAG, style, mascot))
    except Exception as e:
        print("nvm write:", e)


class Button:
    """Tap (released before HOLD) or hold (fires once while held)."""
    HOLD = 1.2

    def __init__(self, pin, Pull, DigitalInOut):
        self.io = DigitalInOut(pin)
        self.io.switch_to_input(pull=Pull.UP)
        self.down_at = None
        self.fired = False

    def poll(self, now):
        pressed = not self.io.value
        if pressed and self.down_at is None:
            self.down_at, self.fired = now, False
        elif pressed and not self.fired and now - self.down_at >= self.HOLD:
            self.fired = True
            return "hold"
        elif not pressed and self.down_at is not None:
            tap = not self.fired and now - self.down_at >= 0.03
            self.down_at = None
            return "tap" if tap else None
        return None

# =================== hardware + network (runs on the board) ===================
def main():
    import busio
    from digitalio import DigitalInOut, Pull

    if App is None:
        raise IMPORT_ERROR
    display = DISPLAY
    bmp = BUFS[0]
    root = displayio.Group()
    root.append(displayio.TileGrid(bmp, pixel_shader=palette))
    display.root_group = root
    gc.collect()
    style, mascot = load_choice()
    STAGE[0] = "APP"
    app = App(bmp, style, mascot, BUFS[1:])
    app.night_hours = app.night_default = night_hours()
    app.celebrated = load_celebrated()
    app.desk_rev = load_desk_rev()
    app.season_mode = (os.getenv("MAD_SEASON") or "AUTO").strip().upper()
    ann = (os.getenv("MAD_ANNIVERSARY") or "").strip()      # "YYYY-MM-DD" launch day
    if len(ann) == 10 and ann[4] == "-" and ann[7] == "-":
        app.anniv, app.anniv_year = ann[5:], int(ann[:4])
    bd = (os.getenv("MAD_BIRTHDAY") or "").strip()          # "YYYY-MM-DD" first commit
    if len(bd) == 10 and bd[4] == "-" and bd[7] == "-":
        app.bday, app.bday_year = bd[5:], int(bd[:4])
    gc.collect()
    print("free RAM:", gc.mem_free())
    STAGE[0] = "WIFI"

    def screen(msg):
        """Show a status line on the panel right away (used while connecting)."""
        print(msg)
        app.set_offline(msg)
        app.tick(time.monotonic())
        display.refresh()

    screen("STARTING")

    pixel = None
    try:
        import neopixel
        pixel = neopixel.NeoPixel(board.NEOPIXEL, 1, brightness=0.15)
    except Exception:
        pass

    def status(color):
        """The board's own little LED: green = fetched, red = trouble. Barely
        on at night."""
        if pixel:
            pixel[0] = tuple(c // 15 for c in color) if app.night else color

    btn_up = Button(board.BUTTON_UP, Pull, DigitalInOut)
    btn_down = Button(board.BUTTON_DOWN, Pull, DigitalInOut)

    ssid = os.getenv("CIRCUITPY_WIFI_SSID")
    password = os.getenv("CIRCUITPY_WIFI_PASSWORD")
    url = os.getenv("MAD_STATS_URL") or DEFAULT_URL
    feed_url = os.getenv("MAD_FEED_URL") or FEED_URL
    key = display_key()
    if key and not feed_url.startswith("https://"):
        print("MAD_FEED_URL is not https: the display key will not be sent")
        key = None
    if os.getenv("MAD_DISPLAY_KEY") and not key:
        print("MAD_DISPLAY_KEY looks wrong (expect madk_ + 43 characters)")
    net = {"esp": None, "requests": None, "key": key}

    def connect():
        import adafruit_connection_manager
        import adafruit_requests
        from adafruit_esp32spi import adafruit_esp32spi
        status((0, 0, 255))
        screen("WIFI...")
        if net["esp"] is None:
            spi = busio.SPI(board.SCK, board.MOSI, board.MISO)
            net["esp"] = adafruit_esp32spi.ESP_SPIcontrol(
                spi, DigitalInOut(board.ESP_CS), DigitalInOut(board.ESP_BUSY),
                DigitalInOut(board.ESP_RESET))
        esp = net["esp"]
        tries = 0
        while not esp.is_connected:
            try:
                esp.connect_AP(ssid, password, timeout_s=15)
            except (OSError, RuntimeError, ConnectionError) as e:
                tries += 1
                print("Wi-Fi attempt", tries, "failed:", e)
                if tries % 2 == 0:
                    # the Wi-Fi chip can get stuck after many restarts: reboot it
                    screen("RESET WIFI")
                    try:
                        esp.reset()
                    except Exception:
                        pass
                    time.sleep(2)
                if tries >= 4:
                    raise ConnectionError(wifi_diagnosis(esp))
                screen("WIFI RETRY %d" % tries)
                time.sleep(1)
        screen("WIFI OK")
        pool = adafruit_connection_manager.get_radio_socketpool(esp)
        ssl = adafruit_connection_manager.get_radio_ssl_context(esp)
        net["requests"] = adafruit_requests.Session(pool, ssl)

    def wifi_diagnosis(esp):
        """Say whether the network is visible, to tell 'not found' from 'bad password'."""
        try:
            seen = []
            for ap in esp.scan_networks():
                name = ap["ssid"] if isinstance(ap, dict) else ap.ssid
                seen.append(str(name, "utf-8") if isinstance(name, bytes) else name)
        except Exception as e:
            print("scan failed:", e)
            return "NO WIFI"
        print("Networks seen:", seen)
        if ssid not in seen:
            return "NETWORK NOT FOUND"
        return "WIFI PASSWORD?"

    def fetch():
        if net["requests"] is None:
            connect()
        if app.stats is None:
            screen("LOADING")
        headers = {"Accept": "application/json"}
        target = url
        if net["key"]:
            target = feed_url
            headers["Authorization"] = "Display " + net["key"]
            headers["X-Desk-State"] = app.state()     # what's on screen, for the phone remote
        r = net["requests"].get(target, headers=headers, timeout=15)
        try:
            if r.status_code in (401, 403) and net["key"]:
                # revoked or wrong: stop sending it, fall back to public stats
                print("display key rejected; showing public stats")
                net["key"] = None
                app.toast = ("KEY REJECTED", time.monotonic() + 4)
                raise OSError("KEY REJECTED")
            if r.status_code != 200:
                raise OSError("HTTP %d" % r.status_code)
            return r.json()
        finally:
            r.close()
            headers = None

    fails = 0
    next_fetch = 0
    have_wifi = bool(ssid and password and not ssid.startswith("your-"))
    if not have_wifi:
        app.set_offline("SET UP WI-FI")

    while True:
        now = time.monotonic()
        # only fetch when the screen is still, so animations never stutter
        if have_wifi and now >= next_fetch and app.quiet(now):
            try:
                gc.collect()
                STAGE[0] = "FETCH"
                data = fetch()
                STAGE[0] = "DATA"
                app.set_data(data, True, time.monotonic())
                data = None
                gc.collect()
                STAGE[0] = "RUN"
                status((0, 40, 0))
                fails = 0
            except Exception as e:
                print("Fetch error:", e)
                if isinstance(e, MemoryError):
                    raise                     # -> crash screen (shows free memory)
                fails += 1
                status((60, 0, 0))
                msg = str(e) if isinstance(e, ConnectionError) else "ERR " + str(e)
                app.set_offline(msg.upper()[:18])
                if fails >= 3:            # rebuild the connection next time
                    net["requests"] = None
                    if net["esp"]:
                        try:
                            net["esp"].reset()
                        except Exception:
                            pass
            every = FEED_SECONDS if net["key"] else REFRESH_SECONDS
            next_fetch = time.monotonic() + (every if fails == 0 else 20)

        now = time.monotonic()
        up, down = btn_up.poll(now), btn_down.poll(now)
        if app.save_needed:
            app.save_needed = False
            save_choice(app.style, app.mascot)      # (writes the nvm tag too)
            save_celebrated(app.celebrated)
            save_desk_rev(app.desk_rev)
        if (up or down) and app.wake(now):
            up = down = None                   # night: the press only wakes it
        if app.mode in ("dash", "show") and (up or down):
            if up == "tap":
                app.next_style(now)
            elif down == "tap":
                app.next_mascot(now)
            elif up == "hold":
                app.demo(now)
            elif down == "hold":
                app.start_show(now)
            if up == "tap" or down == "tap":
                save_choice(app.style, app.mascot)

        app.tick(time.monotonic())
        display.refresh()
        time.sleep(0.01)


def crash_screen(err):
    """Any crash: show the error on the panel, then restart in 30 s."""
    import supervisor
    print("CRASH:", repr(err))
    try:
        display = DISPLAY
        display.auto_refresh = True
        gc.collect()
        bmp = BUFS[0]
        bmp.fill(0)
        g = displayio.Group()
        g.append(displayio.TileGrid(bmp, pixel_shader=palette))
        display.root_group = g
        msg = (type(err).__name__ + " " + str(err)).upper()
        draw_text(bmp, 1, 0, "ERROR %s %dK" % (STAGE[0], gc.mem_free() // 1024), RED, F3)
        for i in range(4):
            draw_text(bmp, 1, 7 + i * 6, msg[i * 16:(i + 1) * 16], WHITE, F3)
    except Exception as e2:
        print("crash screen failed:", e2)
    time.sleep(30)
    supervisor.reload()


if RUN:
    try:
        main()
    except Exception as e:  # noqa
        crash_screen(e)
