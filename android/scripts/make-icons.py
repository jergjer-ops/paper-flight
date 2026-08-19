from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / "assets" / "icon-master.png"
RES = ROOT / "android" / "app" / "src" / "main" / "res"

densities = {
    "mdpi": (48, 108),
    "hdpi": (72, 162),
    "xhdpi": (96, 216),
    "xxhdpi": (144, 324),
    "xxxhdpi": (192, 432),
}

source = Image.open(MASTER).convert("RGBA")
for density, (legacy_size, foreground_size) in densities.items():
    folder = RES / f"mipmap-{density}"
    foreground = source.resize((foreground_size, foreground_size), Image.Resampling.LANCZOS)
    foreground.save(folder / "ic_launcher_foreground.png", optimize=True)

    scene = source.resize((legacy_size, legacy_size), Image.Resampling.LANCZOS)

    rounded_mask = Image.new("L", (legacy_size, legacy_size), 0)
    radius = max(2, round(legacy_size * 0.22))
    ImageDraw.Draw(rounded_mask).rounded_rectangle(
        (1, 1, legacy_size - 2, legacy_size - 2), radius=radius, fill=255
    )
    legacy = scene.copy()
    legacy.putalpha(rounded_mask)
    legacy.save(folder / "ic_launcher.png", optimize=True)

    round_mask = Image.new("L", (legacy_size, legacy_size), 0)
    ImageDraw.Draw(round_mask).ellipse((1, 1, legacy_size - 2, legacy_size - 2), fill=255)
    round_icon = scene.copy()
    round_icon.putalpha(round_mask)
    round_icon.save(folder / "ic_launcher_round.png", optimize=True)
