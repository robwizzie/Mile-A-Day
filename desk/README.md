# Mile A Day desk counter

The LED desk counters (Adafruit Matrix Portal M4 + 64x32 panel).

- `firmware/` — the board's code. `firmware/mad/` is the app; `firmware/code.py`
  just starts it. The feed it reads is documented in `docs/DESK_DISPLAY.md`.
- `firmware-build/matrixportal_m4_mad/` — the custom CircuitPython 10.3.1 board
  definition. The `mad` package is frozen into the firmware so its code runs
  from flash (the M4 has 192 KB of RAM; loaded as files it didn't fit).
  Build: copy that folder into `circuitpython/ports/atmel-samd/boards/`, copy
  `firmware/mad` to `circuitpython/frozen/MAD_Desk/mad`, then
  `make BOARD=matrixportal_m4_mad` with arm-none-eabi-gcc 14. Install: double-click
  RESET, drop `firmware.uf2` on MATRIXBOOT, put `code.py` and `settings.toml` on
  CIRCUITPY.
- The phone remote (mileaday.run/admin/desk) draws a box's real screen by
  running this same `mad` code in MicroPython WebAssembly. After changing
  `firmware/mad`, run `desk/sync-preview.sh` (CI checks they match).
