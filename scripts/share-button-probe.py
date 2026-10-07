#!/usr/bin/env python3
"""Exit 0 if the popup snapshot has the Share button: accent-blue pixels in the footer band
(bottom 70 px of the 2x snapshot), right half, where only the Share control is blue."""
import struct, sys, zlib

data = open(sys.argv[1], "rb").read()
pos, idat, w, h, ct = 8, b"", 0, 0, 0
while pos < len(data):
    n, kind = struct.unpack(">I4s", data[pos:pos + 8])
    body = data[pos + 8:pos + 8 + n]
    if kind == b"IHDR":
        w, h, depth, ct = struct.unpack(">IIBB", body[:10])
        assert depth == 8 and ct in (2, 6), "unsupported PNG"
    elif kind == b"IDAT":
        idat += body
    pos += 12 + n
bpp = 4 if ct == 6 else 3
raw, stride, prev, rows = zlib.decompress(idat), w * bpp, bytearray(w * bpp), []
for y in range(h):
    f, line = raw[y * (stride + 1)], bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
    for i in range(stride):
        a = line[i - bpp] if i >= bpp else 0
        b, c = prev[i], (prev[i - bpp] if i >= bpp else 0)
        if f == 1: line[i] = (line[i] + a) & 255
        elif f == 2: line[i] = (line[i] + b) & 255
        elif f == 3: line[i] = (line[i] + (a + b) // 2) & 255
        elif f == 4:
            p = a + b - c; pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
            line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
    rows.append(line); prev = line
blue = 0
for y in range(h - 70, h):
    for x in range(w // 2, w):
        r, g, b = rows[y][x * bpp:x * bpp + 3]
        if b > 150 and b > r + 60 and b > g + 30:
            blue += 1
print("blue pixels in footer band:", blue)
sys.exit(0 if blue > 40 else 1)
