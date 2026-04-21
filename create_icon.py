#!/usr/bin/env python3
"""
create_icon.py — Generates the Contexto app icon (AppIcon.iconset/)
No third-party libraries required; uses only Python's standard library.
"""

import math
import os
import struct
import zlib

# ── Design ──────────────────────────────────────────────────────────────────
BG_COLOR  = (26, 95, 200)   # Blue-indigo background
FG_COLOR  = (255, 255, 255) # White "C" stroke
DOT_COLOR = (255, 210, 40)  # Gold dot


def make_pixel(x: int, y: int, w: int, h: int) -> tuple:
    """Return an RGBA tuple for pixel (x,y) in an w×h icon."""
    cx, cy = w / 2, h / 2
    dx, dy = x - cx, y - cy
    dist   = math.hypot(dx, dy)

    # ── Background: circular disc ──────────────────────────────────────────
    bg_radius = w * 0.46
    if dist > bg_radius:
        return (0, 0, 0, 0)          # transparent

    r_outer = w * 0.31
    r_inner = w * 0.19
    angle   = math.degrees(math.atan2(dy, dx))  # –180 … 180

    # ── "C" ring arc (open on right side) ────────────────────────────────
    in_ring = r_inner <= dist <= r_outer
    in_gap  = -38 <= angle <= 38       # the "mouth" of the C

    if in_ring and not in_gap:
        return (*FG_COLOR, 255)

    # ── Gold dot (the "definition" period) ───────────────────────────────
    dot_cx = cx + r_outer + (r_outer - r_inner) / 2
    dot_r  = w * 0.055
    if math.hypot(x - dot_cx, y - cy) <= dot_r:
        return (*DOT_COLOR, 255)

    return (*BG_COLOR, 255)          # plain background


# ── Minimal PNG writer ───────────────────────────────────────────────────────

def write_png(width: int, height: int) -> bytes:
    def chunk(name: bytes, data: bytes) -> bytes:
        c = name + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xFFFFFFFF)

    ihdr = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)  # RGBA, 8-bit

    raw = bytearray()
    for y in range(height):
        raw += b'\x00'   # filter byte per row
        for x in range(width):
            raw += bytes(make_pixel(x, y, width, height))

    return (
        b'\x89PNG\r\n\x1a\n' +
        chunk(b'IHDR', ihdr) +
        chunk(b'IDAT', zlib.compress(bytes(raw), 9)) +
        chunk(b'IEND', b'')
    )


# ── Icon sizes required by macOS ─────────────────────────────────────────────
ICONSET_SIZES = [
    (16,   'icon_16x16.png'),
    (32,   'icon_16x16@2x.png'),
    (32,   'icon_32x32.png'),
    (64,   'icon_32x32@2x.png'),
    (128,  'icon_128x128.png'),
    (256,  'icon_128x128@2x.png'),
    (256,  'icon_256x256.png'),
    (512,  'icon_256x256@2x.png'),
    (512,  'icon_512x512.png'),
    (1024, 'icon_512x512@2x.png'),
]


def main():
    outdir = 'AppIcon.iconset'
    os.makedirs(outdir, exist_ok=True)
    for size, fname in ICONSET_SIZES:
        data = write_png(size, size)
        path = os.path.join(outdir, fname)
        with open(path, 'wb') as f:
            f.write(data)
        print(f'  {fname}  ({size}×{size})')
    print(f'\nIcon files written to {outdir}/')


if __name__ == '__main__':
    main()
