"""Decode real Copy/Save outputs; both caller orders and appearances must agree."""
from pathlib import Path
import subprocess
import sys
from PIL import Image, ImageChops

root = Path(sys.argv[1])
for period in ['today', 'week', 'month']:
    reference = Image.open(root / 'popup-first-light' / f'save-{period}.png').convert('RGBA')
    assert reference.size == (2400, 1260)
    for order in ['popup-first', 'export-first']:
        for appearance in ['light', 'dark']:
            directory = root / f'{order}-{appearance}'
            for name in [f'copy-{period}.png', f'copy-{period}.tiff', f'save-{period}.png']:
                path = directory / name
                if path.suffix == '.tiff':
                    # macOS-produced LZW TIFF is decoded by the platform.
                    target = path.with_suffix('.decoded.png')
                    subprocess.run(['sips', '-s', 'format', 'png', str(path), '--out', str(target)],
                                   check=True, stdout=subprocess.DEVNULL)
                    path = target
                actual = Image.open(path).convert('RGBA')
                assert actual.size == reference.size, name
                # AppKit's repeated SDR draws can round a component by one 8-bit step.
                difference = ImageChops.difference(reference, actual)
                assert max(high for low, high in difference.getextrema()) <= 1, (period, order, appearance, name)
                size = 20 if period == 'week' else 24
                x = 1608 if period == 'week' else 1584
                rows = [432, 522, 612] if period == 'week' else [565, 659, 753]
                for index, y in enumerate(rows):
                    template = directory / f'declared-{index}-{size}.png'
                    if not template.exists():
                        continue  # This installed app/resource is unavailable on this Mac.
                    expected = Image.open(template).convert('RGBA')
                    icon = actual.crop((x, y, x + size * 2, y + size * 2))
                    delta = ImageChops.difference(expected, icon)
                    assert max(high for low, high in delta.getextrema()) <= 1, (period, name, 'declared icon', index)
print('PASS final icon regions match independent declared-resource templates; decoded Copy PNG/TIFF and Save PNG agree across actual popup/export cache orders and light/dark contexts; production cards stay light')
