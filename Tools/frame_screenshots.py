from pathlib import Path

from PIL import Image, ImageChops, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "screenshots"
OUTPUT = SOURCE / "framed"
BEZEL = SOURCE / "iphone-bezel.png"
NAMES = (
    "settings.png",
    "shorts-download-menu.png",
    "video-download-menu.png",
    "tab-editor.png",
    "shorts-library.png",
    "shorts-player.png",
    "download-progress.png",
    "audio-library.png",
    "audio-player.png",
    "audio-queue.png",
)


def make_overlay(bezel):
    overlay = bezel.copy()
    red, green, blue, alpha = bezel.split()
    white = ImageChops.darker(ImageChops.darker(red, green), blue)
    white = white.point(lambda value: 255 if value >= 250 else 0)

    interior = Image.new("L", bezel.size, 0)
    ImageDraw.Draw(interior).rectangle((175, 165, 1425, 2835), fill=255)
    opening = ImageChops.multiply(white, interior)
    overlay.putalpha(ImageChops.subtract(alpha, opening))
    return overlay, opening


def cover(image, size):
    scale = max(size[0] / image.width, size[1] / image.height)
    resized = image.resize(
        (round(image.width * scale), round(image.height * scale)),
        Image.Resampling.LANCZOS,
    )
    left = (resized.width - size[0]) // 2
    top = (resized.height - size[1]) // 2
    return resized.crop((left, top, left + size[0], top + size[1]))


def frame(path, overlay, opening):
    display = opening.getbbox()
    screen_size = (display[2] - display[0], display[3] - display[1])
    screen = cover(Image.open(path).convert("RGBA"), screen_size)
    canvas = Image.new("RGBA", overlay.size, (0, 0, 0, 0))
    canvas.paste(screen, display[:2], opening.crop(display))
    canvas.alpha_composite(overlay)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    result = canvas.resize((800, 1500), Image.Resampling.LANCZOS)
    result.save(OUTPUT / path.name, optimize=True)


bezel_image = Image.open(BEZEL).convert("RGBA")
bezel_overlay, display_mask = make_overlay(bezel_image)
for name in NAMES:
    frame(SOURCE / name, bezel_overlay, display_mask)
