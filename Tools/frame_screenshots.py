import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "screenshots"
OUTPUT = SOURCE / "framed"
BEZEL = SOURCE / "iphone-bezel.png"
FRAME_OPENING = (197, 189, 1403, 2811)
DISPLAY = (220, 220, 1380, 2780)
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


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius, fill=255)
    return mask


def extract_bezel(path):
    bezel = Image.open(path).convert("RGBA")
    alpha = bezel.getchannel("A")
    hole = Image.new("L", bezel.size, 0)
    ImageDraw.Draw(hole).rounded_rectangle(FRAME_OPENING, 145, fill=255)
    bezel.putalpha(ImageChops.subtract(alpha, hole))
    bezel.save(BEZEL, optimize=True)


def cover(image, size):
    scale = max(size[0] / image.width, size[1] / image.height)
    resized = image.resize(
        (round(image.width * scale), round(image.height * scale)),
        Image.Resampling.LANCZOS,
    )
    left = (resized.width - size[0]) // 2
    top = (resized.height - size[1]) // 2
    return resized.crop((left, top, left + size[0], top + size[1]))


def frame(path, bezel):
    screen_size = (DISPLAY[2] - DISPLAY[0], DISPLAY[3] - DISPLAY[1])
    screen = cover(Image.open(path).convert("RGBA"), screen_size)
    canvas = Image.new("RGBA", bezel.size, (0, 0, 0, 0))
    ImageDraw.Draw(canvas).rounded_rectangle(FRAME_OPENING, 145, fill=(0, 0, 0, 255))
    canvas.paste(screen, DISPLAY[:2], rounded_mask(screen_size, 120))
    canvas.alpha_composite(bezel)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    result = canvas.resize((800, 1500), Image.Resampling.LANCZOS)
    result.save(OUTPUT / path.name, optimize=True)


if len(sys.argv) == 2:
    extract_bezel(Path(sys.argv[1]))

bezel_image = Image.open(BEZEL).convert("RGBA")
for name in NAMES:
    frame(SOURCE / name, bezel_image)
