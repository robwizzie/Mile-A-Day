# Mile A Day desk counter - test animations from the phone remote (the owner
# taps "Play on my box"). Each one is the real scene, with TEST where a
# person's name would be and this box's own numbers, so it can never be
# mistaken for a real nudge or hype. Loaded only for a test, then dropped.
SCENES = ("user", "milestone", "nudge", "hype", "friend", "friend_walk", "finished",
          "friendmile", "atrisk", "reminder", "morning", "mile", "streak", "yearago",
          "pr", "message", "comment", "medal", "review", "recap", "holiday",
          "newyear", "countdown", "lead", "doodle", "record")
# The test doodle: a heart with a few stars (run-length coded like the feed's).
HEART = ("0_0_0_0O2207220l2603260h2L0f2L0S300A2N0Q32092N0R300A2N0A300Q2P08320P25112H09300R23112H0d23102I0d2N0d"
         "2N0N400F2L0N420E2L0O400G2J0G700Q2H0G720P2H0H700R2F0m2D0o2B0r270d600F250d620F230H500M600b520z500_0_0_0A")


def sample(app, scene):
    """The event tuple for a test of `scene`, or None for an unknown one."""
    n = int(app.target_users or 0)
    st = int(app.value(11) or 0) if app.me else 0
    who = "TEST"
    year = int((app.date or "2026")[:4])
    return {
        "user": ("user", max(0, n - 1), n),
        "milestone": ("milestone", "users", (n // 50 + 1) * 50),
        "nudge": ("nudge", who),
        "hype": ("hype", who),
        "friend": ("friend", who, 0.8, False),
        "friend_walk": ("friend", who, 0.6, True),
        "finished": ("finished", who, 1.3, False),
        "friendmile": ("friendmile", who, 1.25, 720, 540, False),
        "atrisk": ("atrisk", 1, ((who, max(st, 1)),)),
        "reminder": ("reminder",),
        "morning": ("morning",),
        "mile": ("mile", st),
        "streak": ("streak", (st // 50 + 1) * 50),
        "yearago": ("yearago", 1.0, st),
        "pr": ("pr", "LONGEST RUN", "5.0 MI", "TEST PR"),
        "message": ("message", who, "THIS IS A TEST"),
        "comment": ("comment", who, "THIS IS A TEST"),
        "medal": ("medal", "TEST MEDAL"),
        "review": ("review", 5, "THIS IS A TEST"),
        "recap": ("recap",),
        "holiday": ("holiday", "THANKSGIVING"),
        "newyear": ("newyear", year + 1),
        "countdown": ("countdown", 12.0, year + 1),
        "lead": ("lead", who, 2.0, 1.5),
        "doodle": ("doodle", who, HEART),
        "record": ("pr", "SIGNUPS", "%d TODAY" % max(1, int((app.growth or {}).get("today") or 0)), "TEST"),
    }.get(scene)
