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


# The spade, lifted verbatim from `SuitShapes.swift` so the icon and the app
# draw the same shape rather than two shapes that look similar.
SPADE_PATH = [
    ("move", (0.50, 0.04)),
    ("curve", (0.34, 0.22), (0.05, 0.40), (0.05, 0.58)),
    ("curve", (0.05, 0.74), (0.20, 0.83), (0.35, 0.80)),
    ("curve", (0.42, 0.79), (0.46, 0.75), (0.48, 0.70)),
    ("curve", (0.47, 0.84), (0.40, 0.93), (0.30, 0.97)),
    ("line", (0.70, 0.97)),
    ("curve", (0.60, 0.93), (0.53, 0.84), (0.52, 0.70)),
    ("curve", (0.54, 0.75), (0.58, 0.79), (0.65, 0.80)),
    ("curve", (0.80, 0.83), (0.95, 0.74), (0.95, 0.58)),
    ("curve", (0.95, 0.40), (0.66, 0.22), (0.50, 0.04)),
]


def flatten_spade(steps=18):
    """The spade outline as a unit-box polygon."""
    points = []
    current = (0.0, 0.0)
    for segment in SPADE_PATH:
        if segment[0] == "move":
            current = segment[1]
            points.append(current)
        elif segment[0] == "line":
            current = segment[1]
            points.append(current)
        else:
            c1, c2, end = segment[1], segment[2], segment[3]
            p0 = current
            for step in range(1, steps + 1):
                t = step / steps
                u = 1 - t
                x = (u ** 3) * p0[0] + 3 * (u ** 2) * t * c1[0] \
                    + 3 * u * (t ** 2) * c2[0] + (t ** 3) * end[0]
                y = (u ** 3) * p0[1] + 3 * (u ** 2) * t * c1[1] \
                    + 3 * u * (t ** 2) * c2[1] + (t ** 3) * end[1]
                points.append((x, y))
            current = end
    return points


SPADE = flatten_spade()


def polygon_hit(px, py, polygon):
    """Crossing-number test in the polygon's own unit space."""
    inside = False
    count = len(polygon)
    j = count - 1
    for i in range(count):
        xi, yi = polygon[i]
        xj, yj = polygon[j]
        if (yi > py) != (yj > py):
            if px < (xj - xi) * (py - yi) / (yj - yi) + xi:
                inside = not inside
        j = i
    return inside


def render():
    """Rasterise into a float buffer: ground, then spray, then cards, then mark."""
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

    # The mark: a spade knocked out of the front card in cream, sized so it
    # still reads at the smallest icon size.
    mark = SIZE * 0.185
    mx, my = cx - mark / 2, (cy - SIZE * 0.012) - mark / 2
    x0, x1 = int(mx) - 2, int(mx + mark) + 2
    y0, y1 = int(my) - 2, int(my + mark) + 2
    for y in range(max(0, y0), min(SIZE - 1, y1) + 1):
        base = y * SIZE
        for x in range(max(0, x0), min(SIZE - 1, x1) + 1):
            covered = 0
            for sy in range(SS):
                for sx in range(SS):
                    ux = (x + (sx + 0.5) / SS - mx) / mark
                    uy = (y + (sy + 0.5) / SS - my) / mark
                    if 0 <= ux <= 1 and 0 <= uy <= 1 and polygon_hit(ux, uy, SPADE):
                        covered += 1
            if covered == 0:
                continue
            weight = covered / (SS * SS)
            pixel = buffer[base + x]
            for i in range(3):
                pixel[i] += (CREAM[i] - pixel[i]) * weight

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
