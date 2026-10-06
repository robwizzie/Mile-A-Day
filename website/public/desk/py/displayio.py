# Stand-in for CircuitPython's displayio, so the desk's own code can draw in
# a browser (the phone remote's live preview).
class Bitmap:
    def __init__(self, w, h, n=32):
        self.width, self.height = w, h
        self.d = bytearray(w * h)

    def __setitem__(self, k, v):
        x, y = k
        if 0 <= x < self.width and 0 <= y < self.height:
            self.d[y * self.width + x] = v
        else:
            raise IndexError

    def __getitem__(self, k):
        x, y = k
        return self.d[y * self.width + x]

    def fill(self, v):
        for i in range(len(self.d)):
            self.d[i] = v


class Palette:
    def __init__(self, n):
        self.c = [0] * n

    def __setitem__(self, i, v):
        self.c[i] = v

    def __getitem__(self, i):
        return self.c[i]

    def __len__(self):
        return len(self.c)


class Group:
    def __init__(self, *a, **k):
        pass

    def append(self, x):
        pass


class TileGrid:
    def __init__(self, *a, **k):
        pass
