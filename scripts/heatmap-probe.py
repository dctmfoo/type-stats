#!/usr/bin/env python3
"""Check real rendered cell colours against known fixture counts, using stdlib only.

Usage: heatmap-probe.py dark:<png> light:<png> ... (the palette each image is drawn with)."""
import struct
import sys
import zlib


def pixels(path):
    data = open(path, "rb").read()
    pos, compressed = 8, b""
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, colour = struct.unpack(">IIBB", body[:10])
            assert depth == 8 and colour in (2, 6), "unsupported PNG"
        elif kind == b"IDAT":
            compressed += body
        pos += length + 12
    bpp = 4 if colour == 6 else 3
    stride = width * bpp
    raw, previous, rows = zlib.decompress(compressed), bytearray(stride), []
    for y in range(height):
        filter_type = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b, c = previous[i], previous[i - bpp] if i >= bpp else 0
            if filter_type == 1: line[i] = (line[i] + a) & 255
            elif filter_type == 2: line[i] = (line[i] + b) & 255
            elif filter_type == 3: line[i] = (line[i] + (a + b) // 2) & 255
            elif filter_type == 4:
                p = a + b - c
                distances = [abs(p - a), abs(p - b), abs(p - c)]
                line[i] = (line[i] + [a, b, c][distances.index(min(distances))]) & 255
        rows.append(line)
        previous = line
    return width, height, lambda x, y: tuple(rows[y][x * bpp:x * bpp + 3])


palettes = {
    "dark": [(41, 46, 56), (38, 82, 130), (41, 117, 184), (38, 150, 224), (56, 186, 255)],
    "light": [(219, 222, 230), (189, 217, 247), (128, 184, 237), (64, 133, 219), (20, 84, 173)],
}
palette = palettes["dark"]


def shade(rgb):
    for step, colour in enumerate(palette):
        if all(abs(a - b) <= 2 for a, b in zip(rgb, colour)):
            return step
    return None


expected = [[0] * 24 for _ in range(7)]
expected[0][9:17] = [1, 1, 2, 2, 3, 3, 4, 4]
for day, step in enumerate([1, 2, 2, 2, 3], 1):
    expected[day][9] = step
expected[6] = [0] * 9 + [4, 1] + [None] * 13

for arg in sys.argv[1:]:
    scheme, path = arg.split(":", 1)
    palette = palettes[scheme]
    width, height, pixel = pixels(path)
    bands = []
    for y in range(height):
        runs, start = [], None
        for x in range(width + 1):
            match = x < width and shade(pixel(x, y)) is not None
            if match and start is None: start = x
            if not match and start is not None:
                if x - start >= 8: runs.append((start, x))
                start = None
        if len(runs) in (24, 11):
            if bands and y == bands[-1][-1][0] + 1:
                bands[-1].append((y, runs))
            else:
                bands.append([(y, runs)])
    bands = [band for band in bands if len(band) >= 8]
    assert len(bands) == 7, f"{path}: expected 7 grid rows, got {len(bands)}"
    centres = [(a + b) // 2 for a, b in bands[0][len(bands[0]) // 2][1]]
    for day, band in enumerate(bands):
        y = band[len(band) // 2][0]
        actual = [shade(pixel(x, y)) for x in centres]
        assert actual == expected[day], f"{path}: row {day}: {actual}, expected {expected[day]}"
    print(f"PASS {scheme} {path}: all 168 cell centres match fixture shades and future mask")
