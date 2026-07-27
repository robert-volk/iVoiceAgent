"""One-off generator for the legacy app-icon PNGs referenced by
Info.plist's CFBundleIconFiles (see project.yml notes). Draws a simple
terminal-prompt glyph — a phosphor-green ">" chevron with a trailing
caret block on black — matching the app's "Terminal" visual direction.

Run once locally (`python scripts/gen_icon.py`) whenever the icon needs
regenerating; the output PNGs are committed to Resources/AppIcons/.
"""
from PIL import Image, ImageDraw

BG = (11, 13, 12, 255)        # #0B0D0C
FG = (124, 224, 166, 255)     # #7CE0A6

SIZES = {
    "AppIcon20x20@2x": 40,
    "AppIcon20x20@3x": 60,
    "AppIcon29x29@2x": 58,
    "AppIcon29x29@3x": 87,
    "AppIcon40x40@2x": 80,
    "AppIcon40x40@3x": 120,
    "AppIcon60x60@2x": 120,
    "AppIcon60x60@3x": 180,
}

MASTER = 1024


def draw_master() -> Image.Image:
    img = Image.new("RGBA", (MASTER, MASTER), BG)
    d = ImageDraw.Draw(img)

    # Chevron ">" — two thick diagonal strokes meeting at a point.
    stroke = MASTER // 11
    left_x = MASTER * 0.22
    mid_x = MASTER * 0.46
    right_x = left_x
    top_y = MASTER * 0.30
    mid_y = MASTER * 0.50
    bot_y = MASTER * 0.70

    d.line([(left_x, top_y), (mid_x, mid_y)], fill=FG, width=stroke, joint="curve")
    d.line([(mid_x, mid_y), (right_x, bot_y)], fill=FG, width=stroke, joint="curve")
    # Round the stroke ends so it doesn't look clipped at small sizes.
    for (x, y) in [(left_x, top_y), (mid_x, mid_y), (right_x, bot_y)]:
        r = stroke / 2
        d.ellipse([x - r, y - r, x + r, y + r], fill=FG)

    # Trailing caret block.
    caret_w = MASTER * 0.16
    caret_h = stroke
    caret_x0 = MASTER * 0.56
    caret_y0 = bot_y - caret_h / 2
    d.rectangle([caret_x0, caret_y0, caret_x0 + caret_w, caret_y0 + caret_h], fill=FG)

    return img


def main() -> None:
    master = draw_master()
    out_dir = "Resources/AppIcons"
    for name, size in SIZES.items():
        resized = master.resize((size, size), Image.LANCZOS)
        resized.convert("RGB").save(f"{out_dir}/{name}.png")
        print(f"wrote {out_dir}/{name}.png ({size}x{size})")


if __name__ == "__main__":
    main()
