# Mile A Day desk counter - the App: data in, events out, dashboard styles,
# mascot transitions. Scenes live in mad/modes.py (Arcade, Campfire, Race,
# Clock) and mad/fx.py (celebrations and alerts).
import gc
import math
import displayio
from mad.gfx import (BLACK, MAROON_DIM, MAROON, RED, WHITE, FL_YELLOW, GREEN,
                     FL_GOLD, FL_ORANGE, FL_DEEP, palette, F5, F3, FB,
                     text_width, draw_text, ink, draw_box, draw_centered, blit,
                     fill, draw_icon, icon_width, commas, short, num, ease,
                     ease_out, art_bitmap, set_dim, upper_name)
LAZY = ("message", "holiday", "countdown", "medal", "review", "comment", "friendmile")   # scenes in extra.py
MODES = (2, 4, 5, 6, 7)       # styles drawn by mad/modes.py

STYLES = ("CLASSIC", "SPOTLIGHT", "ARCADE", "BIG", "CAMPFIRE", "RACE", "CLOCK")
CLOCK = 6
LIVE = 7                 # not a choice: shown while the owner is out running
MASCOTS = ("RUNNER", "FLAMEY")
BOOT_MIN = 3.0           # keep the logo up at least this long
DASH_SECONDS = 25        # Classic: still dashboard time between stat shows
T_TRANS = 1.7            # mascot wipe between screens
T_COUNT = 1.0            # number count-up
EVENT_GAP = 4.0          # dashboard time between two alerts
NIGHT_DIM = 0.35

# One vocabulary everywhere: an icon + a short label.
# (feed key, icon, short label). "me" = this board's owner.
STATS = (
    ("total_users", "users", "USERS"),             # 0
    ("miles_today", "today", "MI TODAY"),          # 1
    ("total_miles", "miles", "TOTAL MI"),          # 2
    ("active_7d", "active", "ACTIVE/WK"),          # 3
    ("longest_streak", "streak", "TOP STREAK"),    # 4
    ("total_hypes", "hypes", "HYPES"),             # 5
    ("photos_shared", "photos", "PHOTOS"),         # 6
    ("out_running_now", "running", "OUT NOW"),     # 7  (feed only)
    ("tokens_spent_today", "token", "TOKENS USED"),  # 8
    ("badges_today", "badge", "NEW BADGES"),       # 9
    ("new_friends_today", "friends", "NEW FRIENDS"),  # 10
    ("me", "streak", "MY STREAK"),                 # 11
    ("goal", "miles", "MILE GOAL"),                # 12 next community mile goal
    ("days", "streak", "LAST 64 DAYS"),            # 13 my streak heatmap
)
ME = 11
GOAL = 12
HEAT = 13
HOLIDAYS = ("VALENTINE", "STPATRICK", "JULY4", "THANKSGIVING", "ANNIV")
# Flamey's flame burning down when the mile still isn't done in the evening.
# (7..12 are the same tones in a Flamey's Closet colour.)
DIM_NERVOUS = {16: 17, 23: 17, 17: 18, 7: 8, 11: 8, 8: 9}
DIM_PANIC = {16: 18, 23: 18, 17: 18, 18: 19, 19: 24, 7: 9, 11: 9, 8: 9, 9: 10, 10: 12}
# Rotation order (feed-only stats drop out without a key; today's 0s skip).
ORDER = (1, ME, HEAT, 2, GOAL, 7, 3, 4, 8, 9, 10, 5, 6)


def next_day(date):
    """'YYYY-MM-DD' + 1 day (the board rolls its own date over at midnight
    instead of waiting up to 30 s for the next feed)."""
    try:
        y, m, d = int(date[:4]), int(date[5:7]), int(date[8:10])
    except (ValueError, TypeError):
        return date
    dim = (31, 29 if (y % 4 == 0 and (y % 100 or y % 400 == 0)) else 28, 31, 30, 31, 30,
           31, 31, 30, 31, 30, 31)[m - 1]
    d += 1
    if d > dim:
        d, m = 1, m + 1
        if m > 12:
            m, y = 1, y + 1
    return "%04d-%02d-%02d" % (y, m, d)


def _modes():
    from mad import modes
    return modes


def unload(name):
    """Drop a lazily imported mad.<name> module to give its RAM back."""
    import sys
    import mad
    sys.modules.pop("mad." + name, None)
    try:
        delattr(mad, name)
    except Exception:            # (MicroPython raises KeyError here)
        pass


def _dow(y, m, d):
    """Day of the week, 0 = Sunday (Sakamoto)."""
    t = (0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4)
    if m < 3:
        y -= 1
    return (y + y // 4 - y // 100 + y // 400 + t[m - 1] + d) % 7


def season_for(date, anniv=None, bday=None):
    """'YYYY-MM-DD' -> a look name or None. `anniv` = 'MM-DD' of the App
    Store launch, `bday` = 'MM-DD' of Mile A Day's first commit. (Lives
    here, not in mad/season.py, so plain days never load the season art.)"""
    try:
        y, mo, d = int(date[:4]), int(date[5:7]), int(date[8:10])
    except (ValueError, TypeError):
        return None
    if date[5:10] in (anniv, bday):
        return "ANNIV"
    if mo == 2 and d in (13, 14):
        return "VALENTINE"
    if mo == 3 and d in (16, 17):
        return "STPATRICK"
    if mo == 7 and d in (3, 4):
        return "JULY4"
    if mo == 11:
        turkey = 1 + (4 - _dow(y, 11, 1)) % 7 + 21      # 4th Thursday
        if d in (turkey - 1, turkey):
            return "THANKSGIVING"
    if mo == 10 and d >= 25:
        return "HALLOWEEN"
    if mo == 12 and d <= 26:
        return "SANTA"
    if (mo == 12 and d == 31) or (mo == 1 and d == 1):
        return "NEWYEAR"              # scenery only: fireworks in the background
    return None


def wear(fl):
    """The closet look from the feed: {slot: item id} or None."""
    if not isinstance(fl, dict):
        return None
    out = {}
    for k in ("color", "head", "eyes", "costume"):
        v = fl.get(k)
        if isinstance(v, str) and 0 < len(v) < 24:
            out[k] = v
    return out or None


def goal_step(total):
    return 5000 if total < 100000 else (10000 if total < 500000 else 50000)


def is_streak_milestone(s):
    """Days worth a party: every 50, every full year, and the first week/month."""
    return s > 0 and (s % 50 == 0 or s % 365 == 0 or s in (7, 30))
HUD_LABEL = {3: "ACTIVE/WK", 4: "STREAK", 8: "TOKENS", 9: "BADGES", 10: "FRIENDS"}


class App:
    def __init__(self, fb, style=0, mascot=1, bufs=None):
        """`bufs`: four 64x32 bitmaps code.py allocated at power-up, before
        memory fragments (each needs one contiguous 2 KB block)."""
        from mad import art
        self.fb = fb
        n = len(palette)
        if not bufs:
            bufs = [displayio.Bitmap(64, 32, n) for _ in range(4)]
        self.dash, self.card_a, self.card_b, self.scratch = bufs
        self.runner = [art_bitmap(f) for f in art.RUNNER]
        self.run_jump = [art_bitmap(f) for f in art.RUN_JUMP]   # rise, tuck, land
        self.run_sit = art_bitmap(art.RUN_SIT)                    # by the campfire
        self.flamey_m = [art_bitmap(f) for f in art.FLAMEY_M]
        self.flamey_l = [art_bitmap(f) for f in art.FLAMEY_L]
        for y, row in enumerate(art.LOGO):    # the logo goes straight onto the
            for x, ch in enumerate(row):       # screen: no 2 KB copy kept around
                fb[x, y] = int(ch, 32)
        del art
        import sys
        import mad
        sys.modules.pop("mad.art", None)       # free the art strings
        try:
            delattr(mad, "art")
        except Exception:            # (MicroPython raises KeyError here)
            pass
        self.style = style % len(STYLES)
        self.mascot = mascot % len(MASCOTS)
        self.stats = None
        self.me = None
        self.friends = ()
        self.feed = False
        self.live = False
        self.status_text = "CONNECTING"
        self.order = (1, 2, 3, 4, 5, 6)
        self.shown_users = self.target_users = self.users_seen = 0
        self.count_from = self.count_start = 0
        self.mode = "boot"
        self.mode_start = 0
        self.toast = None
        self.particles = []
        self.ev = None
        self.queue = []
        self.next_event_at = 0.0
        self.seen_alerts = None          # ids already shown (None = first feed)
        self.running_names = ()
        self.seen_running = {}           # name -> when we last saw them running
        self.seen_finished = None        # finished-session ids already shown
        self.celebrated = 0              # last streak milestone celebrated (nvm)
        self.save_needed = False
        self.greet_day = None
        self.last_risk = None
        self.at_risk = {}
        self.seen_msgs = None
        self.anniv = None                # "MM-DD" of the App Store launch (settings)
        self.anniv_year = None
        self.bday = None                 # "MM-DD" of Mile A Day's first commit (settings)
        self.bday_year = None
        self.closet = None               # what the owner's Flamey wears in the app
        self.recolored = False
        self.wearing = None
        self.seen_medals = None
        self.seen_reviews = None
        self.seen_comments = None
        self.seen_miles = None
        self.cheered = {}                # friend name -> when their run was celebrated
        self.desk_rev = 0                # last phone-remote change applied (nvm)
        self.night_default = (22 * 60, 7 * 60)   # settings.toml MAD_NIGHT (main.py sets it)
        self.seen_cmds = None
        self.ny_countdown = False
        self.season_mode = "AUTO"        # AUTO / OFF / HALLOWEEN / SANTA (settings.toml)
        self.look = None
        self.date = None
        self.live_shown = 0.0
        self.live_last = 0.0
        # clock (only with a display key: the feed carries the owner's time)
        self.clock = None                # (seconds since midnight, monotonic)
        self.night_hours = (22 * 60, 7 * 60)
        self.night = False
        self.wake_until = 0.0
        self.recap_day = None
        self.last_m = None
        self.last_remind = None
        self.sched_at = 0.0

    # ================= data in =================
    def set_data(self, data, live, now):
        """Public stats (dict of numbers) or the display feed
        ({community, me, friends_running, alerts})."""
        feed = "community" in data
        stats = data["community"] if feed else data
        first = self.stats is None
        old_miles = num(self.stats, "total_miles") if self.stats else 0
        prev_me = self.me
        self.stats, self.live, self.feed = stats, live, feed
        self.me = data.get("me") if feed else None
        self.friends = (data.get("friends_running") or ())[:3] if feed else ()
        self.at_risk = (data.get("friends_at_risk") or {}) if feed else {}
        if self.me:
            try:
                h, m, s = (int(x) for x in self.me.get("local_time", "").split(":"))
                self.clock = (h * 3600 + m * 60 + s, now)
            except (ValueError, TypeError):
                pass
        users = int(num(stats, "total_users"))
        if first or not live:
            self.users_seen = users
            if self.ev is None or self.ev[0] != "user":
                self.count_from, self.target_users, self.count_start = \
                    self.shown_users, users, now
        else:
            if users > self.users_seen:
                self.push(("user", self.users_seen, users), merge=True)
                if users // 50 > self.users_seen // 50:
                    self.push(("milestone", "users", users // 50 * 50))
            self.users_seen = max(self.users_seen, users)
            miles = num(stats, "total_miles")
            if old_miles and int(miles // 5000) > int(old_miles // 5000):
                self.push(("milestone", "miles", int(miles // 5000) * 5000))
            if prev_me and self.me and self.me.get("mile_done") and not prev_me.get("mile_done"):
                self.push(("mile", int(self.me.get("streak") or 0)))
        if feed and self.me:
            self._me_changes(prev_me, first, now)
        if self.me and self.me.get("mile_done"):          # a streak milestone today
            st = int(self.me.get("streak") or 0)
            if is_streak_milestone(st) and st != self.celebrated:
                self.celebrated, self.save_needed = st, True
                self.push(("streak", st))
        if feed:
            self._alerts(data.get("alerts") or ())
            self._messages(data.get("messages") or ())
            self._reviews(data.get("reviews") or ())
            self._comments(data.get("comments") or ())
            self._friend_miles(data.get("friends_miles") or (), now)
            self._desk(data.get("desk"), now)
            self._commands(data.get("commands") or (), now)
            names = tuple(upper_name(f.get("name")) for f in self.friends)
            for f, name in zip(self.friends, names):
                if name not in self.running_names:
                    self.push(("friend", name, float(f.get("miles") or 0)))
                self.seen_running[name] = now
            self.running_names = names
            self._finished(data.get("friends_finished") or (), now)
        o = []
        for i in ORDER:
            if i == ME:
                if self.me:
                    o.append(i)
            elif i == GOAL:
                o.append(i)
            elif i == HEAT:
                if self.me and len(self.me.get("days") or ()) >= 7:
                    o.append(i)
            elif i >= 7:
                if feed and num(stats, STATS[i][0]) > 0:
                    o.append(i)
            else:
                o.append(i)
        self.order = tuple(o)

    def _messages(self, msgs):
        """Desk messages from Admin -> Displays: each plays once. At boot,
        anything from the last half hour still plays."""
        ids = [m.get("id") for m in msgs]
        first = self.seen_msgs is None
        seen = self.seen_msgs or []
        for m in reversed(msgs):                       # oldest first
            if m.get("id") in seen or (first and (m.get("age_s") or 0) > 1800):
                continue
            self.push(("message", upper_name(m.get("from")), str(m.get("text") or "")[:64]))
        self.seen_msgs = (ids + [i for i in seen if i not in ids])[:10]

    def _medals(self, medals):
        """Medals the owner just earned: each celebrates once. At boot, only
        ones from the last half hour (the feed keeps two days)."""
        ids = [m.get("id") for m in medals]
        first = self.seen_medals is None
        seen = self.seen_medals or []
        for m in reversed(medals):                     # oldest first
            if m.get("id") in seen or (first and (m.get("age_s") or 0) > 1800):
                continue
            self.push(("medal", str(m.get("name") or "MEDAL")[:48]))
        self.seen_medals = (ids + [i for i in seen if i not in ids])[:10]

    def _desk(self, d, now):
        """The phone remote: sleep hours apply as they are (null = this box's
        own settings.toml); a style / mascot change applies once (by rev), so
        the buttons still work in between."""
        if not isinstance(d, dict):
            return
        if d.get("never_sleep"):
            hours = None
        else:
            a, b = d.get("sleep_start"), d.get("sleep_end")
            if isinstance(a, int) and isinstance(b, int) and 0 <= a < 1440 and 0 <= b < 1440:
                hours = (a, b)
            else:
                hours = self.night_default
        if hours != self.night_hours:
            self.night_hours = hours
            self._update_night(now)
        rev = d.get("rev")
        if not isinstance(rev, int) or rev == self.desk_rev:
            return
        self.desk_rev = rev
        self.save_needed = True
        st, ma = d.get("style"), d.get("mascot")
        if isinstance(ma, int) and 0 <= ma < len(MASCOTS):
            self.mascot = ma
        if isinstance(st, int) and 0 <= st < len(STYLES) and (st not in (5, 6) or self.me):
            if st != self.style:
                self.style = st
                self._restart_dash(now)
            self.toast = (STYLES[st], now + 1.6)
        else:
            self.toast = (MASCOTS[self.mascot], now + 1.6)

    def _commands(self, cmds, now):
        """Taps from the phone remote: "run the stat show now" (real numbers)
        and "wake up" (30 min). Nothing else can be triggered: alerts only
        come from real activity."""
        ids = [c.get("id") for c in cmds]
        if self.seen_cmds is None:            # first feed: those are old taps
            self.seen_cmds = ids
            return
        for c in reversed(cmds):
            if c.get("id") in self.seen_cmds:
                continue
            if c.get("kind") == "show":
                if self.mode in ("dash", "show"):
                    self.start_show(now)
            elif c.get("kind") == "wake":            # bright for half an hour
                self.wake_until = now + 1800
                self._update_night(now)
        self.seen_cmds = (ids + [i for i in self.seen_cmds if i not in ids])[:10]

    def _friend_miles(self, miles, now):
        """'<friend> got their mile in!' (the same announcement as the phone):
        a celebration with their day's numbers. Skipped if their run's finish
        was just celebrated (same run, a few minutes apart)."""
        ids = [m.get("id") for m in miles]
        first = self.seen_miles is None
        seen = self.seen_miles or []
        for m in reversed(miles):                      # oldest first
            if m.get("id") in seen or (first and (m.get("age_s") or 0) > 900):
                continue
            name = upper_name(m.get("name"))
            if now - self.cheered.get(name, -1e9) < 2400:
                continue
            self.cheered[name] = now
            self.push(("friendmile", name, float(m.get("miles") or 0), int(m.get("seconds") or 0),
                       m.get("best_pace")))
        self.seen_miles = (ids + [i for i in seen if i not in ids])[:10]
        for n in [n for n, t in self.cheered.items() if now - t > 3600]:
            self.cheered.pop(n)

    def _comments(self, comments):
        """New comments on posts the owner is tagged in: each plays once. At
        boot, only ones from the last half hour."""
        ids = [c.get("id") for c in comments]
        first = self.seen_comments is None
        seen = self.seen_comments or []
        for c in reversed(comments):                   # oldest first
            if c.get("id") in seen or (first and (c.get("age_s") or 0) > 1800):
                continue
            self.push(("comment", upper_name(c.get("from")), str(c.get("text") or "")[:64]))
        self.seen_comments = (ids + [i for i in seen if i not in ids])[:10]

    def _reviews(self, reviews):
        """Founder mode: a new App Store review (admins' desks only)."""
        ids = [r.get("id") for r in reviews]
        if self.seen_reviews is None:          # first feed: history, not news
            self.seen_reviews = ids
            return
        for r in reversed(reviews):
            if r.get("id") not in self.seen_reviews:
                try:
                    stars = max(1, min(5, int(r.get("stars") or 0)))
                except (ValueError, TypeError):
                    continue
                self.push(("review", stars, str(r.get("title") or "")[:48]))
        self.seen_reviews = (ids + [i for i in self.seen_reviews if i not in ids])[:10]

    def _alerts(self, alerts):
        ids = [a.get("id") for a in alerts]
        if self.seen_alerts is None:          # first feed: history, not news
            self.seen_alerts = ids
            return
        for a in reversed(alerts):            # oldest first
            if a.get("id") not in self.seen_alerts:
                kind = a.get("kind")
                if kind in ("nudge", "hype"):
                    self.push((kind, upper_name(a.get("from"))))
        self.seen_alerts = (ids + [i for i in self.seen_alerts if i not in ids])[:20]

    def _me_changes(self, prev, first, now):
        """My own run, my personal records, the date (seasons, New Year)."""
        me = self.me
        date = me.get("local_date") or ""
        if self.date and date and date != self.date and self.date.endswith("12-31"):
            if not self.ny_countdown:          # (the countdown already partied)
                self.push(("newyear", int(date[:4])))
        if date and (not self.date or date >= self.date):
            self.date = date              # (never step back: the board rolls over itself)
        self.closet = wear(me.get("flamey"))
        self.apply_season()
        self._medals(me.get("medals") or ())
        if me.get("running_now"):
            self.live_last = float(me.get("live_miles") or 0)
        if first or not prev:
            return
        if prev.get("running_now") and not me.get("running_now"):
            # run over: celebrate it (the MILE DONE party follows once it syncs)
            self.push(("finished", upper_name(me.get("username")), self.live_last))
        a, b = prev.get("longest_run"), me.get("longest_run")
        if a is not None and b is not None and b >= a + 0.05:
            self.push(("pr", "LONGEST RUN", "%.1f MI" % b, "NEW PR!"))
        a, b = prev.get("fastest_mile_month"), me.get("fastest_mile_month")
        same_month = (prev.get("local_date") or "")[:7] == date[:7]
        if a and b and b < a and same_month:
            months = ("JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP",
                      "OCT", "NOV", "DEC")
            try:
                head = months[int(date[5:7]) - 1] + " PR!"
            except (ValueError, IndexError):
                head = "NEW PR!"
            self.push(("pr", "FASTEST MILE", "%d:%02d" % (b // 60, b % 60), head))

    def apply_season(self):
        mode = (self.season_mode or "AUTO").upper()
        if mode == "OFF":
            look = None
        elif mode in ("HALLOWEEN", "SANTA", "NEWYEAR") + HOLIDAYS:
            look = mode
        else:
            look = season_for(self.date or "", self.anniv, self.bday)
        # (the closet's colours use the logo's palette slots: not until it's gone)
        wear = self.closet if self.mode not in ("boot", "intro") else None
        if look != self.look or wear != self.wearing:
            gc.collect()
            from mad import season
            season.apply(self, look, wear)
            self.wearing = wear
            unload("season")                  # only needed while dressing
            gc.collect()

    def _finished(self, finished, now):
        """A friend this board showed running has wrapped up."""
        ids = [f.get("id") for f in finished]
        if self.seen_finished is None:
            self.seen_finished = ids
            return
        for f in reversed(finished):
            name = upper_name(f.get("name"))
            seen = self.seen_running.get(name)
            if f.get("id") not in self.seen_finished and seen is not None and now - seen < 3 * 3600:
                self.push(("finished", name, float(f.get("miles") or 0)))
                self.cheered[name] = now
                self.seen_running.pop(name, None)
        self.seen_finished = (ids + [i for i in self.seen_finished if i not in ids])[:12]
        for name in [n for n, t in self.seen_running.items() if now - t > 3 * 3600]:
            self.seen_running.pop(name)

    def push(self, ev, merge=False):
        if merge:
            for k, q in enumerate(self.queue):
                if q[0] == ev[0]:
                    self.queue[k] = (q[0], q[1], ev[2])
                    return
        if ev[0] in ("reminder", "atrisk") and any(q[0] == ev[0] for q in self.queue):
            return
        if len(self.queue) < 8:
            self.queue.append(ev)

    def set_offline(self, msg):
        self.status_text = msg

    def value(self, i):
        if i == 0:
            return self.shown_users
        if i == ME:
            return int(self.me.get("streak") or 0) if self.me else 0
        if i == GOAL:
            target, _ = self.goal()
            return max(0, target - num(self.stats, "total_miles"))
        if i == HEAT:
            days = (self.me or {}).get("days") or ()
            return sum(1 for d in days if d == -1 or d >= 0.95)
        return num(self.stats, STATS[i][0]) if self.stats else 0

    def goal(self):
        """(next community mile goal, fraction of the way there from the last)."""
        total = num(self.stats, "total_miles") if self.stats else 0
        step = goal_step(total)
        target = (int(total) // step + 1) * step
        return target, (total - (target - step)) / step

    def mile_done(self):
        return bool(self.me and self.me.get("mile_done"))

    # ================= time =================
    def local_seconds(self, now):
        if not self.clock:
            return None
        return (self.clock[0] + (now - self.clock[1])) % 86400

    def state(self):
        """What this box tells the server with each poll (X-Desk-State), so the
        phone remote shows it as it really is: style, mascot, awake, sleep hours."""
        a, b = self.night_hours if self.night_hours else (-1, -1)
        return "%d,%d,%d,%d,%d" % (self.style, self.mascot, 0 if self.night else 1, a, b)

    def is_night(self, now):
        s = self.local_seconds(now)
        if s is None or not self.night_hours or now < self.wake_until:
            return False
        d = self.date or ""
        if (d.endswith("12-31") and s >= 22 * 3600) or (d.endswith("01-01") and s < 1800):
            return False                      # stay bright for the New Year fireworks
        m, (a, b) = s / 60, self.night_hours
        return (m >= a or m < b) if a > b else (a <= m < b)

    def wake(self, now):
        """A button press at night: bright for two minutes. True if it woke."""
        was = self.night
        self.wake_until = now + 120
        self._update_night(now)
        return was

    def _update_night(self, now):
        n = self.is_night(now)
        if n != self.night:
            self.night = n
            set_dim(NIGHT_DIM if n else 1.0)
            self._restart_dash(now)

    def view(self):
        """The style on screen: my live run if I'm out, the clock at night,
        else the chosen one."""
        if self.me and self.me.get("running_now"):
            return LIVE
        if self.night:
            return CLOCK
        return self.style

    def _schedule(self, now):
        """Once a second: night mode, the 9pm recap, mile reminders."""
        if now < self.sched_at:
            return
        self.sched_at = now + 1.0
        self._update_night(now)
        s = self.local_seconds(now)
        if s is None or not self.me or not self.live:
            return
        if ((self.date or "").endswith("12-31") and s >= 86400 - 30 and not self.ny_countdown
                and self.mode not in ("boot", "intro") and (self.season_mode or "AUTO") != "OFF"):
            # 30 seconds to midnight: drop everything, it's the countdown
            self.ny_countdown = True
            self.start_event(("countdown", 86400 - s, int(self.date[:4]) + 1), now)
            return
        m = s / 60
        day_start = self.last_m is None or m < self.last_m      # new day
        if self.last_m is not None and m < self.last_m and self.date:
            self.date = next_day(self.date)                     # midnight, locally
            self.apply_season()
        self.last_m = m
        wake_m = self.night_hours[1] if self.night_hours else 7 * 60
        if day_start and self.recap_day is None:
            self.recap_day = 1 if m >= 21 * 60 + 30 else 0    # booted late: skip
            self.greet_day = 0 if wake_m <= m < wake_m + 30 else 1
        elif day_start:
            self.recap_day = self.greet_day = 0
        if self.greet_day == 0 and wake_m <= m < wake_m + 240 and not self.night:
            self.greet_day = 1                                 # good morning
            d = self.date or ""
            if d.endswith("01-01"):
                self.push(("newyear", int(d[:4])))
            elif self.look in HOLIDAYS:                         # holiday greeting
                self.push(("holiday", self.look))
            else:
                self.push(("morning",))
            if self.me.get("year_ago_miles"):
                self.push(("yearago", float(self.me["year_ago_miles"]),
                           int(self.me.get("streak") or 0)))
        risk = int(num(self.at_risk, "count"))
        if risk and 18 * 60 <= m and not self.night:           # evening: hype your friends
            if self.last_risk is None:
                self.last_risk = now - 45 * 60 + 300
            if now - self.last_risk >= 45 * 60:
                self.last_risk = now
                top = tuple((upper_name(f.get("name")), int(f.get("streak") or 0))
                            for f in (self.at_risk.get("top") or ())[:3])
                self.push(("atrisk", risk, top))
        if self.recap_day == 0 and m >= 21 * 60 and not self.night:
            self.recap_day = 1
            self.push(("recap",))
        if self.mile_done() or self.night or m < 8 * 60 or self.me.get("running_now"):
            return                     # done, asleep, too early, or out running
        gap = 20 * 60 if m >= 18 * 60 else 60 * 60
        if self.last_remind is None:
            self.last_remind = now - gap + 90     # first nudge 90 s after boot
        if now - self.last_remind >= gap:
            self.last_remind = now
            self.push(("reminder",))

    # ================= user choices =================
    def next_style(self, now):
        for _ in STYLES:
            self.style = (self.style + 1) % len(STYLES)
            if self.style not in (5, 6) or self.me:    # Race/Clock need the feed
                break
        if self.style not in MODES:
            unload("modes")                   # Classic/Spotlight/Big don't need it
            gc.collect()
        self._restart_dash(now)
        self.toast = (STYLES[self.style], now + 1.6)

    def next_mascot(self, now):
        self.mascot = (self.mascot + 1) % len(MASCOTS)
        self.toast = (MASCOTS[self.mascot], now + 1.6)

    def samples(self):
        """Every alert, with sample names (the UP-hold demo on the box)."""
        n = self.target_users
        streak = self.value(ME) or 41
        return (("user", max(0, n - 1), n), ("nudge", "DAVE"), ("hype", "DAVE"),
                   ("friend", "DAVE", 0.8), ("reminder",), ("mile", streak),
                   ("milestone", "users", (n // 50 + 1) * 50), ("finished", "DAVE", 1.3),
                   ("streak", (streak // 50 + 1) * 50), ("atrisk", 3, (("MEGSMILES", 213), ("DAVE", 513), ("JWIS35", 88))), ("morning",),
                   ("yearago", 1.32, streak), ("pr", "LONGEST RUN", "5.2 MI", "NEW PR!"),
                   ("pr", "FASTEST MILE", "7:42", "OCT PR!"), ("newyear", 2027), ("countdown", 15.0, 2027), ("message", "DAVE", "NICE MILE [FIRE]"),
                   ("medal", "MONTH STRONG"), ("friendmile", "LAQUETA", 4.68, 6184, 1264), ("comment", "DAVE", "NICE RUN [FIRE]"), ("review", 5, "LOVE THIS APP [FIRE]"),
                   ("holiday", "THANKSGIVING"), ("recap",))

    def demo(self, now):
        """UP hold: play every alert once, with sample names."""
        for ev in self.samples():
            self.queue.append(ev)
        self.next_event_at = 0

    def _restart_dash(self, now):
        if self.mode in ("dash", "show"):
            self.mode, self.mode_start = "dash", now

    # ================= mascot =================
    def mood(self, now):
        """How Flamey (or the runner) feels about today's mile:
        roar (done), fresh (morning), ok, nervous (after 6pm), panic (after 9pm).
        Like Flamey's health in the app: a glance says if it's done."""
        if self.night:
            return "sleep"
        if not self.me:
            return "ok"
        if self.mile_done():
            return "roar"
        s = self.local_seconds(now)
        if s is None:
            return "ok"
        h = s / 3600
        return "fresh" if h < 12 else "ok" if h < 18 else "nervous" if h < 21 else "panic"

    def mascot_frame(self, now, big=False):
        m = self.mood(now)
        if self.mascot == 0:                  # runner: sprints when done, tires late
            step = {"roar": 0.05, "nervous": 0.095, "panic": 0.12}.get(m, 0.075)
            return self.runner[int(now / step) % 8]
        frames = self.flamey_l if big else self.flamey_m
        if now % 3.6 > 3.45:                  # blink
            return frames[8]
        step = {"roar": 0.06, "nervous": 0.07, "panic": 0.05}.get(m, 0.083)
        return frames[int(now / step) % 8]    # the app's 12 fps flicker, by mood

    def draw_mascot(self, b, f, x, y, now, skip=BLACK):
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

    def draw_mascot_corner(self, b, now):
        """Mascot in the top-left box (columns 0..18, rows 0..16)."""
        fill(b, 0, 0, 19, 17, BLACK)
        if self.night:                         # asleep: eyes shut, drifting z's
            f = self.flamey_m[8] if self.mascot else self.runner[0]
            blit(b, f, (19 - f.width) // 2, 0, skip=BLACK)
            p = (now % 3.0) / 3.0
            for k in range(2):
                q = (p + k * 0.5) % 1.0
                draw_text(b, 12 + int(q * 5), 6 - int(q * 7), "Z", MAROON if q > 0.6 else RED, F3)
            return
        f = self.mascot_frame(now)
        if self.mascot == 0:
            self.draw_mascot(b, f, 0, 0, now)
        else:
            # every 9 s he does a happy little double hop (not when he's nervous)
            p = now % 9.0
            calm = self.mood(now) not in ("nervous", "panic")
            hop = int(round(abs(math.sin(p / 0.6 * math.pi)) * 2)) if p < 1.2 and calm else 0
            self.draw_mascot(b, f, (19 - f.width) // 2, -hop, now)

    def transition(self, left, right, u, now):
        """Mascot crosses the screen left->right; `left` is revealed behind."""
        fb = self.fb
        e = ease(u)
        if self.mascot == 0:                       # runner: sprint + speed lines
            rx = int(-6 + e * 82)
            edge = rx + 8
            blit(fb, left, 0, 0, x2=max(0, min(64, edge)))
            blit(fb, right, max(0, edge), 0, x1=max(0, edge))
            for i, (dy, ln) in enumerate(((13, 10), (16, 14), (19, 9), (22, 12))):
                x2 = rx + 6 - (i % 2) * 2
                fill(fb, x2 - ln, dy, x2, dy + 1, MAROON if i % 2 else MAROON_DIM)
            fill(fb, edge, 0, edge + 1, 32, MAROON)
            blit(fb, self.runner[int(now / 0.05) % 8], rx - 8, 8, skip=BLACK)
            return
        # Flamey: the big Flamey glides across, vertically centred, with two
        # soft bounces; a flickering wall of fire just behind him burns the
        # old screen away and leaves the new one. Eased start and stop.
        f = self.flamey_l[int(now / 0.083) % 8]
        fx = int(-f.width - 3 + e * (64 + f.width + 6))
        front = fx + 3                              # fire sits just behind him
        blit(fb, left, 0, 0, x2=max(0, min(64, front - 2)))
        blit(fb, right, max(0, front + 1), 0, x1=max(0, front + 1))
        tick = int(now * 18)
        for y in range(32):
            flick = (y * 7 + tick * 3) % 5
            for dx, col in ((-2, FL_DEEP), (-1, FL_ORANGE), (0, FL_GOLD), (1, FL_YELLOW)):
                x = front + dx - (1 if flick == 0 and dx > -2 else 0)
                if 0 <= x < 64:
                    fb[x, y] = col
        for k in range(6):                         # sparks drifting off the flames
            sx = front - 3 - ((tick + k * 5) % 9)
            sy = (k * 11 + tick * 2) % 32
            if 0 <= sx < 64:
                fb[sx, sy] = (FL_GOLD, FL_ORANGE, FL_DEEP)[k % 3]
        bob = abs(math.sin(u * math.pi * 2)) * 3
        blit(fb, f, fx, int(round((32 - f.height) / 2 - bob)), skip=BLACK)

    # ================= building blocks =================
    def users_counter(self, now):
        if self.shown_users != self.target_users:
            t = min(1.0, (now - self.count_start) / 1.6)
            n = int(self.count_from + (self.target_users - self.count_from) * ease_out(t) + 0.5)
            self.shown_users = self.target_users if t >= 1 else n

    def draw_top(self, b, now):
        """Mascot | big user count, divider below (rows 0..17)."""
        self.draw_mascot_corner(b, now)
        fill(b, 19, 1, 20, 16, MAROON_DIM)
        fill(b, 20, 0, 64, 17, BLACK)
        u = self.shown_users
        draw_box(b, 20, 64, 1, str(u) if u < 10000 else short(u), WHITE, FB)
        draw_box(b, 20, 64, 12, "USERS", RED, F3)
        fill(b, 0, 17, 64, 18, MAROON)

    def stat_text(self, i, frac=1.0):
        if i == GOAL:
            return short(self.goal()[0])
        if i == HEAT:
            n = len((self.me or {}).get("days") or ())
            return "%d/%d" % (int(self.value(i) * frac + 0.5), n)
        v = self.value(i) * frac
        if i == 1 and v < 100 and v != int(v):
            return "%.1f" % v
        return commas(v) if v < 10000 else short(v)

    def stat_label(self, i, room=64):
        """(label, colour). My streak says whether today's mile is done."""
        if i == ME:
            if self.mile_done():
                return "MILE DONE", GREEN
            return ("MILE TODAY?" if room >= 44 else "NOT YET"), RED
        if i == GOAL:
            return short(self.value(GOAL)) + " TO GO", RED
        if i == HEAT:
            return "DAYS DONE", RED
        return STATS[i][2], RED

    def draw_stat_line(self, b, i, y, frac=1.0, x0=0, x1=64):
        """icon + number on one row (F5), short label centred under it (F3)."""
        if i == GOAL:
            from mad import cards
            cards.goal_line(self, b, y, frac, x0, x1)
            return
        if i == HEAT:
            from mad import heat
            heat.heat_line(self, b, y, frac, x0, x1)
            return
        ic = STATS[i][1]
        label, col = self.stat_label(i, x1 - x0)
        t = self.stat_text(i, frac)
        iw = icon_width(ic)
        w = iw + 2 + text_width(t)
        x = x0 + (x1 - x0 - w) // 2
        draw_icon(b, x, y, ic)
        draw_text(b, x + iw + 2, y, t, WHITE)
        draw_box(b, x0, x1, y + 8, label, col, F3)

    def card(self, b, i, frac=1.0, now=0.0):
        """One stat, full screen: icon + big number, short label below."""
        fill(b, 0, 0, 64, 32, BLACK)
        if i == ME:
            from mad import cards
            cards.me_card(self, b, frac)
            return
        if i == GOAL:
            from mad import cards
            cards.goal_card(self, b, frac)
            return
        if i == HEAT:
            from mad import heat
            heat.heat_card(self, b, frac, now)
            return
        _, ic, label = STATS[i]
        t = self.stat_text(i, frac)
        if text_width(t, FB) > 52:
            t = short(self.value(i) * frac)
        iw = icon_width(ic)
        w = iw + 3 + text_width(t, FB)
        x = (64 - w) // 2
        draw_icon(b, x, 6, ic)
        draw_text(b, x + iw + 3, 4, t, WHITE, FB)
        fill(b, 26, 17, 38, 18, MAROON)
        lo, hi = ink(label)
        big = hi - lo <= 56                    # keep at least 4 px each side
        draw_box(b, 0, 64, 22 if big else 23, label, RED, F5 if big else F3)

    # ================= dashboard styles =================
    def tick_dash(self, now):
        t = now - self.mode_start
        fb = self.fb
        style = self.view()
        order = self.order
        if style == 0:                                          # CLASSIC
            self.draw_top(fb, now)
            fill(fb, 0, 18, 64, 32, BLACK)
            cols = [((0, 21), 1, "TODAY", RED), ((22, 42), 2, "TOTAL", RED),
                    ((43, 64), 3, "ACTIVE", RED)]
            if self.me:          # my streak (flame); label: DONE, or RUN! if not yet
                cols[2] = ((43, 64), ME, "DONE" if self.mile_done() else "RUN!",
                           GREEN if self.mile_done() else RED)
            for (x0, x1), i, lab, col in cols:
                v = short(self.value(i))
                font = F5 if text_width(v) <= x1 - x0 - 1 else F3
                if i == ME and 7 + text_width(v) <= x1 - x0:   # flame + number
                    w = 7 + text_width(v)
                    x = x0 + (x1 - x0 - w) // 2
                    draw_icon(fb, x, 19, "streak")
                    draw_text(fb, x + 7, 19, v, WHITE)
                else:
                    draw_box(fb, x0, x1, 19 if font is F5 else 20, v, WHITE, font)
                draw_box(fb, x0, x1, 27, lab, col, F3)
            fill(fb, 21, 20, 22, 31, MAROON_DIM)
            fill(fb, 42, 20, 43, 31, MAROON_DIM)
            if self.stats and t > DASH_SECONDS:
                self.start_show(now)
            return
        if style == 1:                                          # SPOTLIGHT
            self.draw_top(fb, now)
            period, slide = 4.0, 0.45
            k = int(t // period)
            u = t - k * period
            n = len(order)
            i = order[k % n]
            lower = self.scratch
            fill(lower, 0, 0, 64, 32, BLACK)
            if u < slide and k > 0:
                off = int(ease(u / slide) * 14)
                self.draw_stat_line(lower, order[(k - 1) % n], 19 - off)
                self.draw_stat_line(lower, i, 33 - off, 0.0)
            else:
                self.draw_stat_line(lower, i, 19, ease_out((u - slide) / T_COUNT) if k > 0 else 1.0)
            blit(fb, lower, 0, 19, y1=19, y2=32)
            fill(fb, 0, 18, 64, 19, BLACK)
            dots = min(n, 11)
            for j in range(dots):                               # page dots
                fb[64 - 2 * dots + 2 * j - 1, 17] = WHITE if j == k % n else MAROON_DIM
            return
        if style == 2:
            _modes().arcade(self, fb, now, t)
        elif style == 3:
            self.big(fb, now, t)
        elif style == 4:
            _modes().campfire(self, fb, now, t)
        elif style == 5:
            _modes().race(self, fb, now, t)
        else:
            if style == LIVE:
                _modes().live(self, fb, now, t)
            else:
                _modes().clock(self, fb, now, t)

    def big(self, fb, now, t):
        """BIG: one stat at a time, the user count between each."""
        seq = []
        for i in self.order:
            seq += (0, i)
        period = 5.0
        k = int(t // period)
        u = t - k * period
        i = seq[k % len(seq)]
        if u < T_TRANS and k > 0:
            self.card(self.card_a, i, 0.0 if i else 1.0)
            self.card(self.card_b, seq[(k - 1) % len(seq)])
            self.transition(self.card_a, self.card_b, u / T_TRANS, now)
        else:
            self.card(self.card_a, i, ease_out((u - T_TRANS) / T_COUNT) if k > 0 and i else 1.0, now)
            blit(fb, self.card_a, 0, 0)

    def quiet(self, now):
        """Is this a moment where a 1-2 s network pause won't show?"""
        if self.mode in ("dash", "boot"):
            return True
        if self.mode == "show":
            u = (now - self.mode_start) % (T_TRANS + 4.0)
            return T_TRANS + T_COUNT + 0.2 < u < T_TRANS + 3.0
        return False

    # ================= Classic's stat show =================
    def start_show(self, now):
        if self.stats:
            self.mode, self.mode_start = "show", now
            self.show = self.order

    def tick_show(self, now):
        t = now - self.mode_start
        hold = 4.0
        seg = T_TRANS + hold
        show = self.show
        n = len(show)
        k = int(t // seg)
        u = t - k * seg
        if k > n:
            self.mode, self.mode_start = "dash", now
            return
        if k == n:                                # back to the dashboard
            if u < T_TRANS:
                self.card(self.card_b, show[-1])
                self.render_dash_still(self.dash, now)
                self.transition(self.dash, self.card_b, u / T_TRANS, now)
                return
            self.mode, self.mode_start = "dash", now
            return
        i = show[k]
        if u < T_TRANS:
            if k == 0:
                self.render_dash_still(self.dash, now)   # (may use card_a)
            self.card(self.card_a, i, 0.0)
            if k == 0:
                self.transition(self.card_a, self.dash, u / T_TRANS, now)
            else:
                self.card(self.card_b, show[k - 1])
                self.transition(self.card_a, self.card_b, u / T_TRANS, now)
            return
        self.card(self.fb, i, ease_out((u - T_TRANS) / T_COUNT), now)

    # ================= frame =================
    def tick(self, now):
        self._schedule(now)
        if self.mode in ("dash", "show", "intro"):
            self.users_counter(now)
        if (self.queue and self.mode in ("dash", "show") and now >= self.next_event_at
                and not self.toast):
            self.start_event(self.queue.pop(0), now)
        if self.mode == "show" and self.view() == LIVE:
            self.mode, self.mode_start = "dash", now      # my run takes over
        if self.mode == "event":
            from mad import fx                  # loaded only while a scene plays
            fx.play(self, now)
        elif self.mode in ("boot", "intro"):
            self.tick_boot(now)
        elif self.mode == "show":
            self.tick_show(now)
        else:
            self.tick_dash(now)
        if self.look and self.mode not in ("boot", "intro"):
            from mad import decor                         # seasonal scenery
            decor.backdrop(self, self.fb, now,
                           self.view() if self.mode in ("dash", "show") else -1)
        if self.toast:
            text, until = self.toast
            if now > until:
                self.toast = None
            else:
                w = text_width(text)
                fill(self.fb, 28 - w // 2, 10, 37 + w // 2, 22, MAROON)
                fill(self.fb, 29 - w // 2, 11, 36 + w // 2, 21, BLACK)
                draw_centered(self.fb, 32, 13, text, WHITE)

    # ================= startup =================
    def tick_boot(self, now):
        fb = self.fb
        if self.mode == "boot":
            fill(fb, 0, 24, 64, 32, BLACK)        # (the logo is already on screen)
            msg = self.status_text.rstrip(".")
            busy = not msg.startswith("ERR") and "SET UP" not in msg
            dots = "." * (int(now * 3) % 4) if busy else ""
            font, y = (F5, 25) if text_width(msg + "...", F5) <= 62 else (F3, 26)
            lo, hi = ink(msg, font)
            room = text_width("...", font) + 1 if busy else 0
            x = (64 - (hi - lo) - room) // 2 - lo
            x = draw_text(fb, x, y, msg[:16], WHITE, font)
            draw_text(fb, x, y, dots, RED, font)
            if self.stats and now - self.mode_start >= BOOT_MIN:
                blit(self.card_b, fb, 0, 0)          # freeze the logo frame
                self.mode, self.mode_start = "intro", now
                self.shown_users, self.count_from, self.count_start = 0, 0, now + T_TRANS
            return
        u = (now - self.mode_start) / T_TRANS
        if u < 1:
            self.render_dash_still(self.dash, now)
            self.transition(self.dash, self.card_b, u, now)
            return
        self.mode, self.mode_start = "dash", now
        self.apply_season()                          # now the closet can dress him

    def render_dash_still(self, b, now):
        """The current style's opening screen, for wipes."""
        fb, self.fb = self.fb, b
        self.mode_start, saved = now, self.mode_start
        mode = self.mode
        self.mode = "dash"
        self.tick_dash(now)
        self.mode, self.mode_start, self.fb = mode, saved, fb

    # ================= alerts and celebrations =================
    def start_event(self, ev, now):
        self.mode, self.mode_start = "event", now
        self.ev = ev
        self.particles = []
        self.popped = False
        self.frozen = False
        self._last = now
        if ev[0] == "user":
            self.target_users = ev[2]

    def finish_wipe(self, now, t, t0):
        """Mascot crosses and wipes the dashboard back in."""
        if not self.frozen:
            blit(self.card_b, self.fb, 0, 0)
            self.frozen = True
            if self.ev[0] == "user":
                self.shown_users = self.target_users = self.ev[2]
        u = (t - t0) / T_TRANS
        if u < 1:
            self.render_dash_still(self.dash, now)
            self.transition(self.dash, self.card_b, u, now)
            return
        self.mode, self.mode_start = "dash", now
        if self.ev[0] in LAZY:
            unload("extra")                   # the rarer scenes: free them again
        unload("fx")                          # celebrations: loaded again for the next one
        gc.collect()
        self.ev = None
        self.next_event_at = now + EVENT_GAP
