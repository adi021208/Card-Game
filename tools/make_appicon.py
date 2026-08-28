#!/usr/bin/env python3
"""
Renders the DECK app icon.

No image libraries are available here, so this is a small supersampled scanline
renderer: three rotated rounded rectangles (the fanned cards) over a sprayed
ground, written straight out as a PNG. It is the same composition the in-app
`DeckGlyph` draws, so the icon and the app agree.
"""
import math, struct, zlib, os

SIZE = 1024
SS = 3                      # supersampling factor per axis

INK        = (14, 13, 12)
CREAM      = (242, 233, 216)
VERMILION  = (227, 58, 33)
COBALT     = (27, 55, 200)


def rounded_rect_hit(px, py, cx, cy, w, h, radius, angle_deg):
    """Is (px, py) inside a rounded rect centred at (cx, cy) rotated by angle?"""
    angle = math.radians(-angle_deg)
    dx, dy = px - cx, py - cy
    lx = dx * math.cos(angle) - dy * math.sin(angle)
    ly = dx * math.sin(angle) + dy * math.cos(angle)
    hw, hh = w / 2, h / 2
    if abs(lx) > hw or abs(ly) > hh:
        return False
    qx = abs(lx) - (hw - radius)
    qy = abs(ly) - (hh - radius)
    if qx <= 0 or qy <= 0:
        return True
    return qx * qx + qy * qy <= radius * radius


def spray_field(seed, count, cx, cy, spread):
    """Deterministic scatter, matching the app's SprayMark."""
    state = seed or 1
    dots = []
    for _ in range(count):
        state ^= (state << 13) & 0xFFFFFFFFFFFFFFFF
        state ^= state >> 7
        state ^= (state << 17) & 0xFFFFFFFFFFFFFFFF
        a = (state % 100000) / 100000.0
        state ^= (state << 13) & 0xFFFFFFFFFFFFFFFF
        state ^= state >> 7
        state ^= (state << 17) & 0xFFFFFFFFFFFFFFFF
        b = (state % 100000) / 100000.0
        state ^= (state << 13) & 0xFFFFFFFFFFFFFFFF
        state ^= state >> 7
        state ^= (state << 17) & 0xFFFFFFFFFFFFFFFF
        c = (state % 100000) / 100000.0
        angle = a * math.tau
        distance = (b ** 1.7) * spread
        radius = 2 + c * 9
        dots.append((cx + math.cos(angle) * distance,
                     cy + math.sin(angle) * distance,
                     radius,
                     0.10 + c * 0.16))
    return dots


def render():
    """Rasterise into a float buffer: ground, then spray, then cards."""
    cx = cy = SIZE / 2
    card_w = SIZE * 0.335
    card_h = card_w / (2.5 / 3.5)
    radius = card_w * 0.11

    cards = [
        (cx - SIZE * 0.145, cy + SIZE * 0.012, -24.0, CREAM),
        (cx + SIZE * 0.145, cy + SIZE * 0.012,  24.0, CREAM),
        (cx,                cy - SIZE * 0.012,   0.0, VERMILION),
    ]

    # Ground.
    buffer = [[INK[0], INK[1], INK[2]] for _ in range(SIZE * SIZE)]

    # Spray: draw each dot directly rather than testing every dot per pixel.
    for dx, dy, dr, alpha in spray_field(0xDECC, 1400, cx, cy * 0.92, SIZE * 0.46):
        x0, x1 = max(0, int(dx - dr)), min(SIZE - 1, int(dx + dr) + 1)
        y0, y1 = max(0, int(dy - dr)), min(SIZE - 1, int(dy + dr) + 1)
        rr = dr * dr
        for y in range(y0, y1 + 1):
            base = y * SIZE
            ddy = (y + 0.5) - dy
            for x in range(x0, x1 + 1):
                ddx = (x + 0.5) - dx
                if ddx * ddx + ddy * ddy <= rr:
                    pixel = buffer[base + x]
                    for i in range(3):
                        pixel[i] += (VERMILION[i] - pixel[i]) * alpha

    # Cards, antialiased by sampling only near their edges.
    for ccx, ccy, angle, colour in cards:
        reach = int(max(card_w, card_h) * 0.8) + 4
        x0, x1 = max(0, int(ccx - reach)), min(SIZE - 1, int(ccx + reach))
        y0, y1 = max(0, int(ccy - reach)), min(SIZE - 1, int(ccy + reach))
        for y in range(y0, y1 + 1):
            base = y * SIZE
            for x in range(x0, x1 + 1):
                covered = 0
                for sy in range(SS):
                    for sx in range(SS):
                        if rounded_rect_hit(x + (sx + 0.5) / SS, y + (sy + 0.5) / SS,
                                            ccx, ccy, card_w, card_h, radius, angle):
                            covered += 1
                if covered == 0:
                    continue
                weight = covered / (SS * SS)
                pixel = buffer[base + x]
                for i in range(3):
                    pixel[i] += (colour[i] - pixel[i]) * weight

    raw = bytearray()
    for y in range(SIZE):
        raw.append(0)
        base = y * SIZE
        for x in range(SIZE):
            pixel = buffer[base + x]
            raw += bytes((min(255, max(0, int(pixel[0]))),
                          min(255, max(0, int(pixel[1]))),
                          min(255, max(0, int(pixel[2])))))
    return bytes(raw)


def write_png(path, raw, width, height):
    def chunk(tag, data):
        payload = tag + data
        return (struct.pack('>I', len(data)) + payload
                + struct.pack('>I', zlib.crc32(payload) & 0xFFFFFFFF))
    header = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)
    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', header)
           + chunk(b'IDAT', zlib.compress(raw, 9))
           + chunk(b'IEND', b''))
    with open(path, 'wb') as handle:
        handle.write(png)


if __name__ == '__main__':
    target = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                          'Deck/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png')
    os.makedirs(os.path.dirname(target), exist_ok=True)
    write_png(target, render(), SIZE, SIZE)
    print('wrote', target, os.path.getsize(target), 'bytes')
