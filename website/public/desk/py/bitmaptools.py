def fill_region(b, x1, y1, x2, y2, v):
    w, d = b.width, b.d
    for y in range(max(0, y1), min(b.height, y2)):
        o = y * w
        for x in range(max(0, x1), min(w, x2)):
            d[o + x] = v


def blit(dst, src, x, y, x1=0, y1=0, x2=None, y2=None, skip_source_index=None, skip_index=None):
    sk = skip_source_index if skip_source_index is not None else skip_index
    x2 = src.width if x2 is None else x2
    y2 = src.height if y2 is None else y2
    dw, dh, sw = dst.width, dst.height, src.width
    dd, sd = dst.d, src.d
    for sy in range(y1, y2):
        dy = y + sy - y1
        if not (0 <= dy < dh) or not (0 <= sy < src.height):
            continue
        for sx in range(x1, x2):
            dx = x + sx - x1
            if 0 <= dx < dw and 0 <= sx < sw:
                v = sd[sy * sw + sx]
                if sk is None or v != sk:
                    dd[dy * dw + dx] = v
