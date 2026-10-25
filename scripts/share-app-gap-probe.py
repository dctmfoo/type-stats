#!/usr/bin/env python3
"""Check the icon/name gap in real 2x share renders of app-colors-fixture.swift."""
import importlib.util
from pathlib import Path
import sys

arguments = sys.argv[1:]
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("png_reader", Path(__file__).with_name("heatmap-probe.py"))
reader = importlib.util.module_from_spec(spec)
sys.argv = [sys.argv[0]]
spec.loader.exec_module(reader)

for argument in arguments:
    period, path = argument.split(":", 1)
    width, height, pixel = reader.pixels(path)
    assert (width, height) == (2400, 1260), f"{path}: share dimensions changed"
    # The fixed card layouts put these gaps after each 24/20-point icon and
    # before its name. Sample every app row so a bar or lettered cue fails.
    gap = range(827, 830) if period == "week" else range(819, 822)
    centres = (226, 271, 316) if period == "week" else (294, 341, 388)
    background = pixel(0, 0)
    for centre in centres:
        for x in gap:
            for y in range(centre - 3, centre + 4):
                assert all(abs(a - b) <= 2 for a, b in zip(pixel(x * 2, y * 2), background)), \
                    f"{path}: app cue or extra content in icon/name gap at {x},{y}"
    print(f"PASS {period}: all three share app rows have clear icon/name gaps")
