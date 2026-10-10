#!/usr/bin/env python3
"""Check actual rendered app-hour colours against the named fixture, not source text."""
import importlib.util
import sys
from collections import Counter
from pathlib import Path

arguments = sys.argv[1:]
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('png_reader', Path(__file__).with_name('heatmap-probe.py'))
reader = importlib.util.module_from_spec(spec)
sys.argv = [sys.argv[0]]
spec.loader.exec_module(reader)
sys.argv += arguments

# Rounded sRGB samples from the approved equal-lightness fixture. No brand-opacity scale.
hex_ramps = {
    'claude': ['e3c2b8', 'cb9f91', 'b17e6e', '975e4c'],
    'chatgpt': ['c4ccd0', 'a3acb3', '828e95', '647179'],
    'teams': ['c5c8e5', 'a4a7ce', '8488b5', '66699c'],
    'discord': ['c2c9e5', '9fa9cf', '7f8ab6', '606b9d'],
    'neutral': ['cacaca', 'ababab', '8c8c8c', '6f6f6f'],
}
colours = {('zero', 0): reader.neutral(0.92)}
for name, ramp in hex_ramps.items():
    for step, value in enumerate(ramp, 1):
        colours[name, step] = tuple(int(value[i:i+2], 16) for i in (0, 2, 4))


def shade(rgb):
    for key, value in colours.items():
        if all(abs(a-b) <= 2 for a,b in zip(rgb,value)):
            return key
    return None


expected = [[('zero', 0)] * 24 for _ in range(7)]
expected[0][9] = ('claude', 3)    # 257/525 leads, but TOTAL 525 drives intensity
expected[1][13] = ('teams', 4)   # low-share winner, high total 735
expected[2][9] = ('neutral', 2)  # exact 210/210 tie, total 420
expected[3][9] = ('chatgpt', 3)
expected[4][9] = ('chatgpt', 1)    # Ghostty shares this neutral-blue colour
expected[5][10] = ('neutral', 1)
expected[5][11] = ('discord', 2)
expected[6][12] = ('claude', 2)
expected[6][13] = ('claude', 4)  # 600/957=62.7%; same tag hue, peak-strength total
expected[6][15:] = [None] * 9

for path in arguments:
    width,height,pixel = reader.pixels(path)
    bands=[]
    for y in range(height):
        runs=[];start=None
        for x in range(width+1):
            match=x<width and shade(pixel(x,y)) is not None
            if match and start is None:start=x
            if not match and start is not None:
                if 8 <= x-start <= 110:runs.append((start,x))
                start=None
        if 15 <= len(runs) <= 24:
            if bands and y==bands[-1][-1][0]+1:bands[-1].append((y,runs))
            else:bands.append([(y,runs)])
    bands=[b for b in bands if len(b)>=8]
    assert len(bands)==7,f'{path}: expected 7 rendered rows, got {len(bands)}'
    runs=bands[0][len(bands[0])//2][1]
    pitch=(runs[1][0]+runs[1][1]-runs[0][0]-runs[0][1])/2
    start=(runs[0][0]+runs[0][1])/2
    xs=[round(start+h*pitch) for h in range(24)]
    for day,band in enumerate(bands):
        actual=[]
        for x in xs:
            # Read the most common interior sample; the exact-tie glyph is deliberately non-colour.
            samples=[shade(pixel(x,y)) for y,_ in band[2:-2]]
            actual.append(Counter(samples).most_common(1)[0][0])
        assert actual==expected[day],f'{path}: row {day}: {actual}, expected {expected[day]}'
    print(f'PASS {path}: 168 exact cells match app hue, total intensity, neutral tie, zero and future')
