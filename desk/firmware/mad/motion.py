# Mile A Day desk counter - tap and shake, from the Matrix Portal M4's
# built-in LIS3DH accelerometer (I2C 0x19). A few registers, no library:
#   tap        -> wakes the screen at night (a little hop by day)
#   double tap -> next style
#   shake      -> the mascot gets dizzy
# If the sensor isn't there (or answers oddly) everything here stays off.
ADDR = 0x19
WHO_AM_I = 0x33
SHAKE_MG = 650           # how far from 1 g a sample must be to count as a jolt
SHAKE_HITS = 6           # jolts...
SHAKE_SPAN = 1.2         # ...within this many seconds = a shake
POLL_S = 0.03


class Motion:
    def __init__(self, i2c=None):
        self.ok = False
        self.buf = bytearray(6)
        self.one = bytearray(1)
        self.hits = []
        self.quiet_until = 0.0
        self.next_at = 0.0
        try:
            if i2c is None:
                import board
                i2c = board.I2C()
            self.i2c = i2c
            if self._read(0x0F, 1)[0] != WHO_AM_I:
                return
            self._write(0x20, 0x57)        # CTRL_REG1: 100 Hz, X/Y/Z on
            self._write(0x23, 0x88)        # CTRL_REG4: block update, high-res, +-2 g
            self._write(0x22, 0x80)        # CTRL_REG3: click on INT1
            self._write(0x38, 0x3F)        # CLICK_CFG: single + double tap, every axis
            self._write(0x3A, 0x80 | 60)   # CLICK_THS: latch until read, ~1 g
            self._write(0x3B, 10)          # TIME_LIMIT
            self._write(0x3C, 20)          # TIME_LATENCY
            self._write(0x3D, 255)         # TIME_WINDOW
            self._read(0x39, 1)            # clear anything latched
            self.ok = True
        except Exception as e:             # no sensor: no tap and shake
            print("motion off:", e)

    def _write(self, reg, val):
        while not self.i2c.try_lock():
            pass
        try:
            self.i2c.writeto(ADDR, bytes((reg, val)))
        finally:
            self.i2c.unlock()

    def _read(self, reg, n):
        buf = self.buf if n == 6 else self.one
        while not self.i2c.try_lock():
            pass
        try:
            self.i2c.writeto_then_readfrom(ADDR, bytes((reg | (0x80 if n > 1 else 0),)), buf)
        finally:
            self.i2c.unlock()
        return buf

    def poll(self, now):
        """'shake', 'double', 'tap' or None. Cheap: one look every 30 ms."""
        if not self.ok or now < self.next_at:
            return None
        self.next_at = now + POLL_S
        try:
            b = self._read(0x28, 6)
            x, y, z = (((b[i + 1] << 8 | b[i]) ^ 0x8000) - 0x8000 for i in (0, 2, 4))
            mag = (x * x + y * y + z * z) ** 0.5 / 16          # 12-bit, 1 mg per digit
            src = self._read(0x39, 1)[0]
        except Exception:
            return None
        if abs(mag - 1000) > SHAKE_MG:
            self.hits.append(now)
        self.hits = [t for t in self.hits if now - t < SHAKE_SPAN]
        if len(self.hits) >= SHAKE_HITS and self.hits[-1] - self.hits[0] > 0.35:
            self.hits = []
            self.quiet_until = now + 2.0               # its own taps don't count
            return "shake"
        if now < self.quiet_until or not src & 0x40:
            return None
        if src & 0x20:
            return "double"
        if src & 0x10:
            return "tap"
        return None
