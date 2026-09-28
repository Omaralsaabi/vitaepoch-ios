#!/usr/bin/env python3
"""Generate opaque AppIcon PNG sizes from the supplied artwork using macOS sips.

No crop or corner mask is applied. The source must already be square and opaque.
"""
from pathlib import Path
import json
import subprocess

root = Path(__file__).resolve().parent.parent
source = root / 'app_icon.png'
properties = subprocess.check_output(['sips', '-g', 'pixelWidth', '-g', 'pixelHeight', '-g', 'hasAlpha', str(source)], text=True)
values = dict(line.strip().split(': ', 1) for line in properties.splitlines()[1:] if ': ' in line)
if values.get('hasAlpha') != 'no' or values.get('pixelWidth') != values.get('pixelHeight') or int(values.get('pixelWidth', 0)) < 1024:
    raise SystemExit('Source must be square, opaque, and at least 1024 pixels.')
catalog = root / 'VitaEpoch/Assets.xcassets'
icon = catalog / 'AppIcon.appiconset'
icon.mkdir(parents=True, exist_ok=True)
images = []
for idiom, slots in [
    ('iphone', [('20', [2, 3]), ('29', [2, 3]), ('40', [2, 3]), ('60', [2, 3])]),
    ('ipad', [('20', [1, 2]), ('29', [1, 2]), ('40', [1, 2]), ('76', [1, 2]), ('83.5', [2])]),
    ('ios-marketing', [('1024', [1])]),
]:
    for size, scales in slots:
        for scale in scales:
            pixels = int(float(size) * scale)
            filename = f'AppIcon-{pixels}.png'
            images.append({'idiom': idiom, 'size': f'{size}x{size}', 'scale': f'{scale}x', 'filename': filename})
for filename in sorted({image['filename'] for image in images}):
    pixels = filename.removeprefix('AppIcon-').removesuffix('.png')
    subprocess.run(['sips', '-s', 'format', 'png', '-z', pixels, pixels, str(source), '--out', str(icon / filename)], check=True, stdout=subprocess.DEVNULL)
(icon / 'Contents.json').write_text(json.dumps({'images': images, 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
(catalog / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
print(f'Generated {len(images)} icon slots from {source.name}.')
