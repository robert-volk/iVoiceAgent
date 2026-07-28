"""One-off generator for the legacy app-icon PNGs referenced by
Info.plist's CFBundleIconFiles (see project.yml notes). Draws a bold,
simplified microphone silhouette — phosphor green on near-black,
same palette as the in-app "Terminal" direction, but reads as "voice"
at a glance rather than "generic dev tool" the way the old ">_"
chevron did. Kept to three solid shapes (capsule, stem, base) with no
fine detail, since anything finer disappears at 40x40.

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

    cx = MASTER * 0.5

    # Mic head — a tall rounded capsule, the dominant shape.
    head_w = MASTER * 0.26
    head_h = MASTER * 0.42
    head_x0 = cx - head_w / 2
    head_x1 = cx + head_w / 2
    head_y0 = MASTER * 0.16
    head_y1 = head_y0 + head_h
    d.rounded_rectangle([head_x0, head_y0, head_x1, head_y1], radius=head_w / 2, fill=FG)

    # Stem — connects the head straight down to the base, no gap (a gap
    # would vanish into anti-aliasing noise at the smallest sizes).
    stem_w = MASTER * 0.09
    stem_x0 = cx - stem_w / 2
    stem_x1 = cx + stem_w / 2
    stem_y0 = head_y1
    stem_y1 = MASTER * 0.80
    d.rectangle([stem_x0, stem_y0, stem_x1, stem_y1], fill=FG)

    # Base — the stand's foot, wider than the stem so the silhouette
    # doesn't read as a plain lollipop at a glance.
    base_w = MASTER * 0.34
    base_h = MASTER * 0.07
    base_x0 = cx - base_w / 2
    base_x1 = cx + base_w / 2
    base_y0 = stem_y1
    base_y1 = base_y0 + base_h
    d.rounded_rectangle([base_x0, base_y0, base_x1, base_y1], radius=base_h / 2, fill=FG)

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
