#!/usr/bin/env python3
"""Generate og-image.png (1200x630) for Paper Flight link previews.

Reuses the game's paper-collage palette and shapes (see index.html:
TRACK_THEME.morning, drawPipe, drawPlaneModel). Run from the repo root:
    python3 tools/og-image.py
"""
import math

from PIL import Image, ImageDraw, ImageFont

W, H = 1200, 630
GROUND_Y = 520

FONT_TITLE = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"
FONT_TAG = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"


def lerp(a, b, t):
    return a + (b - a) * t


def gradient(w, h, top, bottom):
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(1, h - 1)
        c = tuple(int(lerp(top[i], bottom[i], t)) for i in range(3))
        d.line([(0, y), (w, y)], fill=c)
    return img


def cloud(d, cx, cy, s):
    d.ellipse([cx - 46 * s, cy - 18 * s, cx + 46 * s, cy + 18 * s], fill=(251, 243, 223, 205))
    d.ellipse([cx - 25 * s, cy - 18 * s, cx - 3 * s, cy + 2 * s], fill=(251, 243, 223, 205))
    d.ellipse([cx - 8 * s, cy - 27 * s, cx + 22 * s, cy + 2 * s], fill=(251, 243, 223, 205))
    d.ellipse([cx + 10 * s, cy - 16 * s, cx + 32 * s, cy + 4 * s], fill=(251, 243, 223, 205))


def draw_plane(d, cx, cy, scale, rot):
    """Paper plane, same geometry as drawPlaneModel in index.html."""
    pts = [(-40, 0), (43, -18), (11, 10), (-11, 22), (-3, 4)]

    def P(p):
        x, y = p
        rx = x * math.cos(rot) - y * math.sin(rot)
        ry = x * math.sin(rot) + y * math.cos(rot)
        return (cx + rx * scale, cy + ry * scale)

    body = [P(p) for p in pts]
    d.polygon(body, fill=(255, 250, 240), outline=(36, 53, 75), width=6)
    wing = [P((-40, 0)), P((43, -18)), P((-3, 4))]
    d.polygon(wing, fill=(234, 215, 173), outline=(36, 53, 75), width=6)
    fold = [P((-3, 4)), P((43, -18)), P((11, 10))]
    d.polygon(fold, fill=(246, 232, 199), outline=(36, 53, 75), width=6)
    tip = [P((-19, 1)), P((-10, -1)), P((-12, 3))]
    d.polygon(tip, fill=(231, 111, 81))
    d.line([P((-40, 0)), P((-3, 4)), P((11, 10))], fill=(108, 82, 50, 200), width=5)
    d.line([P((-3, 4)), P((43, -18))], fill=(108, 82, 50, 200), width=5)


def main():
    img = gradient(W, H, (207, 227, 239), (242, 228, 199))
    d = ImageDraw.Draw(img, "RGBA")

    # Sun + clouds
    d.ellipse([940 - 64, 150 - 64, 940 + 64, 150 + 64], fill=(232, 177, 60, 255))
    d.ellipse([940 - 46, 150 - 46, 940 + 46, 150 + 46], fill=(246, 210, 122, 255))
    cloud(d, 150, 120, 1.35)
    cloud(d, 430, 205, 0.95)
    cloud(d, 745, 92, 1.1)

    # Hills
    d.polygon(
        [(0, 454), (85, 353), (184, 447), (282, 342), (420, 438), (560, 360),
         (720, 440), (900, 350), (1200, 430), (1200, GROUND_Y), (0, GROUND_Y)],
        fill=(141, 162, 130),
    )
    d.polygon(
        [(0, 490), (110, 398), (220, 496), (318, 418), (440, 480), (600, 400),
         (760, 490), (920, 415), (1080, 485), (1200, 440), (1200, GROUND_Y), (0, GROUND_Y)],
        fill=(95, 127, 107),
    )

    # Cardboard pipe with gap (drawPipe geometry)
    pipe_x, pw = 640, 110
    gap_top, gap_bot = 120, 400
    jag = [0, 5, 2, 8, 3, 7, 1, 5, 0]

    def column(y0, y1, edge):
        pts = [(pipe_x, y0), (pipe_x + pw, y0), (pipe_x + pw, y1)]
        n = len(jag)
        for i in range(n - 1, -1, -1):
            px = pipe_x + i / (n - 1) * pw
            py = y1 + jag[i] if edge == "bottom" else y1 - jag[i]
            pts.append((px, py))
        pts.append((pipe_x, y1))
        d.polygon(pts, fill=(185, 134, 85), outline=(108, 77, 53), width=4)
        d.rectangle([pipe_x + 16, y0 + 8, pipe_x + 26, y1 - 8], fill=(247, 239, 217, 70))
        d.rectangle([pipe_x + pw - 18, y0 + 6, pipe_x + pw - 10, y1 - 6], fill=(85, 56, 35, 55))
        for yy in range(y0 + 24, y1 - 12, 34):
            d.line([(pipe_x + 34, yy), (pipe_x + pw - 24, yy + 5)], fill=(91, 61, 39, 120), width=3)

    column(0, gap_top, "bottom")
    column(gap_bot, GROUND_Y, "top")

    # Ground
    d.rectangle([0, GROUND_Y, W, H], fill=(216, 182, 111))
    d.rectangle([0, GROUND_Y, W, GROUND_Y + 9], fill=(198, 155, 75))
    for x in range(-30, W, 34):
        d.line([(x, GROUND_Y + 22), (x + 16, GROUND_Y + 32)], fill=(87, 62, 36, 110), width=4)

    # Paper plane
    draw_plane(d, 365, 350, 3.0, -0.22)

    # Title block
    font_title = ImageFont.truetype(FONT_TITLE, 128)
    font_tag = ImageFont.truetype(FONT_TAG, 40)
    title = "PAPER FLIGHT"
    d.text((66, 74), title, font=font_title, fill=(36, 53, 75, 255))
    d.text((62, 68), title, font=font_title, fill=(251, 243, 223, 255))
    d.polygon([(58, 196), (500, 196), (488, 222), (58, 222)], fill=(232, 177, 60, 210))
    tag = "LAUNCH · FLY · NEVER GIVE UP"
    d.text((70, 238), tag, font=font_tag, fill=(103, 95, 83, 255))

    img.save("og-image.png")
    print("wrote og-image.png", img.size)


if __name__ == "__main__":
    main()
