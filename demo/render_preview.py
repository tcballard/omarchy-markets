#!/usr/bin/env python3
"""Render the deterministic fictional-data preview without live market data."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


WIDTH, HEIGHT = 1280, 720
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "preview.png"
SETUP_OUTPUT = ROOT / "preview-profiles.png"
FONT_REGULAR = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_MONO = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
FONT_MONO_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT_BOLD if bold else FONT_REGULAR, size)


def mono_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT_MONO_BOLD if bold else FONT_MONO, size)


def alpha_box(
    image: Image.Image,
    bounds: tuple[int, int, int, int],
    radius: int,
    fill: tuple[int, int, int, int],
    outline: tuple[int, int, int, int] | None = None,
    width: int = 1,
) -> None:
    layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    draw.rounded_rectangle(bounds, radius, fill=fill, outline=outline, width=width)
    image.alpha_composite(layer)


def shadowed_box(
    image: Image.Image,
    bounds: tuple[int, int, int, int],
    radius: int,
    fill: tuple[int, int, int, int],
    outline: tuple[int, int, int, int],
    blur: int,
    offset: int,
) -> None:
    shadow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    shifted = (bounds[0], bounds[1] + offset, bounds[2], bounds[3] + offset)
    ImageDraw.Draw(shadow).rounded_rectangle(shifted, radius, fill=(0, 0, 0, 150))
    image.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(blur)))
    alpha_box(image, bounds, radius, fill, outline)


def label(
    draw: ImageDraw.ImageDraw,
    xy: tuple[int, int],
    value: str,
    size: int,
    color: str,
    bold: bool = False,
    anchor: str | None = None,
) -> None:
    draw.text(xy, value, font=font(size, bold), fill=color, anchor=anchor)


def sparkline(
    image: Image.Image,
    points: list[tuple[int, int]],
    color: str,
    baseline: int | None = None,
) -> None:
    layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    if baseline is not None:
        polygon = points + [(points[-1][0], baseline), (points[0][0], baseline)]
        rgba = (48, 209, 88, 38) if color == "#30d158" else (255, 69, 58, 30)
        draw.polygon(polygon, fill=rgba)
    draw.line(points, fill=color, width=3, joint="curve")
    image.alpha_composite(layer)


def render_marketing_preview_legacy() -> None:
    image = Image.new("RGBA", (WIDTH, HEIGHT), "#090c12")
    pixels = image.load()
    for y in range(HEIGHT):
        for x in range(WIDTH):
            glow = max(0.0, 1.0 - (((x - 580) / 700) ** 2 + ((y - 340) / 520) ** 2))
            pixels[x, y] = (
                int(9 + 8 * glow),
                int(12 + 14 * glow),
                int(18 + 22 * glow),
                255,
            )

    draw = ImageDraw.Draw(image)
    shadowed_box(image, (18, 18, 1262, 60), 13, (17, 21, 27, 255), (48, 55, 65, 255), 10, 7)
    draw = ImageDraw.Draw(image)
    alpha_box(image, (30, 25, 64, 53), 8, (216, 221, 229, 28))
    label(draw, (47, 39), "1", 13, "#d8dde5", True, "mm")
    label(draw, (80, 39), "2", 13, "#7f8995", anchor="mm")
    label(draw, (105, 39), "3", 13, "#7f8995", anchor="mm")
    label(draw, (640, 39), "MON 12:00", 13, "#9aa4af", anchor="mm")
    alpha_box(image, (946, 25, 1190, 53), 8, (48, 209, 88, 25))
    draw = ImageDraw.Draw(image)
    label(draw, (959, 39), "ACME", 13, "#e9edf2", True, "lm")
    label(draw, (1008, 39), "$184.72", 13, "#e9edf2", anchor="lm")
    label(draw, (1071, 39), "↑ +2.48%", 13, "#30d158", True, "lm")
    draw.ellipse((1210, 35, 1218, 43), fill="#30d158")

    label(draw, (68, 145), "Omarchy Markets", 42, "#f3f5f7", True)
    label(draw, (68, 186), "A ticker-first market scanner for the Omarchy bar.", 18, "#909aa6")
    callouts = [
        (238, 254, "Six editable starter profiles", "◆", "#30d158"),
        (298, 246, "Five chart ranges + key stats", "✓", "#30d158"),
        (358, 226, "Consent before any request", "◇", "#909aa6"),
    ]
    for y, width, text, icon, icon_color in callouts:
        alpha_box(image, (68, y, 68 + width, y + 48), 15, (21, 26, 33, 255), (46, 55, 66, 255))
        draw = ImageDraw.Draw(image)
        label(draw, (92, y + 24), icon, 16, icon_color, True, "mm")
        label(draw, (115, y + 24), text, 15, "#dbe0e6", True, "lm")
    label(draw, (68, 633), "Fictional preview data · Informational only · Native quote currencies", 13, "#697480")

    panel = (600, 78, 1230, 688)
    shadowed_box(image, panel, 24, (18, 22, 28, 255), (50, 58, 69, 255), 22, 16)
    draw = ImageDraw.Draw(image)
    label(draw, (630, 115), "Markets", 20, "#f2f4f6", True)
    label(draw, (630, 139), "MAGNIFICENT 7 · JUST NOW", 11, "#7f8995")
    alpha_box(image, (1064, 99, 1167, 129), 9, (255, 255, 255, 15))
    draw = ImageDraw.Draw(image)
    label(draw, (1115, 114), "Manage", 11, "#cdd3da", anchor="mm")
    alpha_box(image, (1175, 99, 1205, 129), 9, (255, 255, 255, 15))
    draw = ImageDraw.Draw(image)
    label(draw, (1190, 114), "↻", 20, "#cdd3da", anchor="mm")

    ranges = [(790, "1D", True), (835, "5D", False), (880, "1M", False), (925, "6M", False), (970, "1Y", False)]
    for x, value, selected in ranges:
        alpha_box(image, (x, 104, x + 39, 127), 7,
                  (48, 209, 88, 28) if selected else (255, 255, 255, 0),
                  (48, 209, 88, 90) if selected else None)
        draw = ImageDraw.Draw(image)
        label(draw, (x + 19, 115), value, 10, "#e0e5ea" if selected else "#7f8995", True, "mm")

    draw.line((620, 153, 1210, 153), fill=(104, 116, 129, 45), width=1)
    rows = [
        (158, "ACME", "Acme Systems", "$184.72", "↑ +2.48%", "#30d158", [183, 177, 180, 171, 174, 164, 168, 159]),
        (200, "NORTH", "Northstar Energy", "£76.18", "↓ −2.38%", "#ff453a", [216, 219, 217, 226, 224, 238, 233, 244]),
        (242, "LUMA", "Luma Foods", "€42.00", "→ 0.00%", "#8b95a1", [266, 265, 267, 266, 267, 266, 267, 266]),
        (284, "ORBIT", "Orbit Software", "$96.40", "↑ +1.15%", "#30d158", [309, 306, 301, 304, 295, 298, 289, 286]),
    ]
    for idx, (y, symbol, name, price, change, color, ys) in enumerate(rows):
        alpha_box(image, (620, y, 1210, y + 40), 8, (255, 255, 255, 14 if idx == 0 else 0))
        draw = ImageDraw.Draw(image)
        label(draw, (636, y + 20), symbol, 13, "#f3f5f7", True, "lm")
        label(draw, (706, y + 20), name, 11, "#7f8995", anchor="lm")
        points = [(875 + i * 17, ys[i]) for i in range(len(ys))]
        sparkline(image, points, color)
        draw = ImageDraw.Draw(image)
        label(draw, (1080, y + 20), price, 13, "#f3f5f7", True, "ra")
        label(draw, (1194, y + 20), change, 11, color, True, "ra")

    draw.line((620, 338, 1210, 338), fill=(104, 116, 129, 45), width=1)
    draw = ImageDraw.Draw(image)
    label(draw, (630, 369), "Acme Systems", 18, "#f3f5f7", True)
    label(draw, (630, 391), "ACME · USD · MARKET OPEN", 10, "#7f8995")
    label(draw, (1194, 369), "$184.72", 27, "#f3f5f7", True, "ra")
    label(draw, (1194, 396), "↑ +4.47  +2.48%", 12, "#30d158", True, "ra")

    hero_points = [(630, 511), (676, 505), (721, 514), (767, 491), (812, 498), (858, 475), (903, 481), (949, 452), (994, 463), (1040, 433), (1085, 441), (1139, 412), (1194, 420)]
    sparkline(image, hero_points, "#30d158", 530)
    draw = ImageDraw.Draw(image)
    label(draw, (630, 549), "PREV CLOSE", 9, "#697480")
    label(draw, (724, 549), "$180.25", 10, "#dbe0e6", True, "ra")
    label(draw, (770, 549), "OPEN", 9, "#697480")
    label(draw, (858, 549), "$181.10", 10, "#dbe0e6", True, "ra")
    label(draw, (902, 549), "VOLUME", 9, "#697480")
    label(draw, (1000, 549), "24.8M", 10, "#dbe0e6", True, "ra")
    label(draw, (1044, 549), "1D", 9, "#697480")
    label(draw, (1194, 549), "↑ +2.48%", 10, "#30d158", True, "ra")
    label(draw, (630, 583), "Open on Yahoo Finance ↗", 10, "#cfd5dc")
    label(draw, (1194, 583), "PIN TO BAR", 10, "#cfd5dc", True, "ra")
    draw.line((620, 610, 1210, 610), fill=(104, 116, 129, 45), width=1)
    label(draw, (630, 633), "Click a row for details · Middle-click the ticker to refresh · Right-click to pause", 10, "#697480")
    label(draw, (915, 670), "YAHOO FINANCE CHART · UNOFFICIAL · INFORMATIONAL ONLY", 10, "#697480", anchor="ma")

    image.convert("RGB").save(OUTPUT, optimize=True)


def render() -> None:
    """Render the actual panel hierarchy at its native marketplace crop."""
    width, height = 640, 720
    image = Image.new("RGBA", (width, height), "#161817")
    draw = ImageDraw.Draw(image)

    foreground = "#ead4ab"
    muted = "#9d876a"
    panel_fill = (35, 37, 35, 255)
    selected_fill = (76, 72, 61, 255)
    separator = (113, 100, 78, 95)
    up = "#b7ce6b"
    down = "#f06a64"
    accent = "#70c7bd"

    # Omarchy bar: the default ticker is visible before the panel opens.
    draw.rectangle((0, 0, width, 34), fill=(33, 35, 33, 255))
    draw.text((14, 17), "MON 09:30", font=mono_font(12), fill=foreground, anchor="lm")
    draw.text((145, 17), "◆  ACME 184.72  ▲ +2.48%   •   NORTH 76.18  ▼ −2.38%",
              font=mono_font(12, True), fill=foreground, anchor="lm")
    draw.line((0, 33, width, 33), fill=accent, width=2)

    # Native panel crop. No marketing page around it: this is the widget.
    panel = (8, 42, 632, 710)
    draw.rounded_rectangle(panel, radius=4, fill=panel_fill, outline=accent, width=2)

    draw.text((28, 74), "Markets", font=mono_font(16, True), fill=foreground, anchor="lm")
    range_x = 180
    for index, value in enumerate(("1D", "5D", "1M", "6M", "1Y")):
        x = range_x + index * 48
        if index == 0:
            draw.rounded_rectangle((x - 8, 58, x + 27, 84), radius=3,
                                   fill=selected_fill)
        draw.text((x + 9, 71), value, font=mono_font(11, index == 0),
                  fill=foreground if index == 0 else muted, anchor="mm")
    draw.text((607, 71), "Updated 09:30", font=mono_font(11), fill=muted, anchor="rm")
    draw.line((20, 96, 620, 96), fill=separator, width=1)

    rows = [
        (102, "ACME", "Acme Systems", "184.72", "▲ +2.48%", up,
         [126, 120, 122, 114, 116, 106, 110, 100]),
        (144, "NORTH", "Northstar Energy", "76.18", "▼ −2.38%", down,
         [158, 161, 159, 168, 166, 180, 175, 186]),
        (186, "LUMA", "Luma Foods", "42.00", "→ 0.00%", muted,
         [208, 207, 209, 208, 209, 208, 209, 208]),
        (228, "ORBIT", "Orbit Software", "96.40", "▲ +1.15%", up,
         [254, 251, 246, 249, 240, 243, 234, 231]),
    ]
    for index, (y, symbol, name, price, change, color, ys) in enumerate(rows):
        if index == 0:
            draw.rounded_rectangle((20, y, 620, y + 40), radius=3, fill=selected_fill)
        draw.text((30, y + 20), symbol, font=mono_font(13, True), fill=foreground, anchor="lm")
        draw.text((112, y + 20), name, font=mono_font(11), fill=muted, anchor="lm")
        points = [(285 + i * 18, ys[i]) for i in range(len(ys))]
        draw.line(points, fill=color, width=2, joint="curve")
        draw.text((502, y + 20), price, font=mono_font(12), fill=foreground, anchor="rm")
        draw.text((606, y + 20), change, font=mono_font(12), fill=color, anchor="rm")

    draw.line((20, 282, 620, 282), fill=separator, width=1)
    draw.text((28, 313), "Acme Systems", font=mono_font(17, True), fill=foreground, anchor="lm")
    draw.text((28, 337), "ACME · USD · MARKET OPEN", font=mono_font(10), fill=muted, anchor="lm")
    draw.text((606, 311), "184.72", font=mono_font(28, True), fill=foreground, anchor="rm")
    draw.text((606, 338), "▲ +4.47  (+2.48%)", font=mono_font(13), fill=up, anchor="rm")

    chart = [(30, 492), (58, 466), (86, 478), (116, 452), (148, 464),
             (180, 438), (214, 458), (248, 432), (282, 444), (318, 420),
             (352, 432), (386, 405), (420, 416), (454, 392), (488, 401),
             (522, 380), (558, 389), (606, 372)]
    baseline = 510
    layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    layer_draw = ImageDraw.Draw(layer)
    layer_draw.polygon(chart + [(606, baseline), (30, baseline)], fill=(183, 206, 107, 42))
    layer_draw.line(chart, fill=up, width=3, joint="curve")
    image.alpha_composite(layer)
    draw = ImageDraw.Draw(image)
    draw.line((30, 438, 606, 438), fill=(240, 106, 100, 80), width=1)
    draw.text((606, 429), "180.25", font=mono_font(10), fill=muted, anchor="rs")
    draw.text((30, 526), "15:30", font=mono_font(10), fill=muted)
    draw.text((606, 526), "22:00", font=mono_font(10), fill=muted, anchor="ra")

    stats = [
        ("Prev close", "180.25", "Open", "181.10"),
        ("Day range", "178.40 – 185.20", "52w range", "102.15 – 188.60"),
        ("Volume", "24.8M", "Last trade", "Mon 22:00"),
    ]
    for index, (left_label, left_value, right_label, right_value) in enumerate(stats):
        y = 558 + index * 27
        draw.text((30, y), left_label, font=mono_font(10), fill=muted)
        draw.text((135, y), left_value, font=mono_font(11), fill=foreground)
        draw.text((330, y), right_label, font=mono_font(10), fill=muted)
        draw.text((435, y), right_value, font=mono_font(11), fill=foreground)

    draw.text((30, 648), "Open on Yahoo Finance ↗", font=mono_font(10), fill=foreground)
    draw.text((606, 648), "PIN TO BAR", font=mono_font(10, True), fill=foreground, anchor="ra")
    draw.line((20, 667, 620, 667), fill=separator, width=1)
    draw.text((30, 687), "Click a row for details · Middle-click refresh · Right-click pause",
              font=mono_font(9), fill=muted)

    image.convert("RGB").save(OUTPUT, optimize=True)


def render_setup() -> None:
    image = Image.new("RGBA", (WIDTH, HEIGHT), "#090c12")
    pixels = image.load()
    for y in range(HEIGHT):
        for x in range(WIDTH):
            glow = max(0.0, 1.0 - (((x - 620) / 720) ** 2 + ((y - 340) / 520) ** 2))
            pixels[x, y] = (
                int(9 + 7 * glow),
                int(12 + 13 * glow),
                int(18 + 21 * glow),
                255,
            )

    draw = ImageDraw.Draw(image)
    shadowed_box(image, (18, 18, 1262, 60), 13, (17, 21, 27, 255), (48, 55, 65, 255), 10, 7)
    draw = ImageDraw.Draw(image)
    alpha_box(image, (30, 25, 64, 53), 8, (216, 221, 229, 28))
    label(draw, (47, 39), "1", 13, "#d8dde5", True, "mm")
    label(draw, (80, 39), "2", 13, "#7f8995", anchor="mm")
    label(draw, (640, 39), "MON 12:00", 13, "#9aa4af", anchor="mm")
    alpha_box(image, (1051, 25, 1190, 53), 8, (255, 255, 255, 12))
    draw = ImageDraw.Draw(image)
    label(draw, (1065, 39), "MARKETS", 12, "#dfe4e9", True, "lm")
    label(draw, (1145, 39), "SET UP", 11, "#9aa4af", True, "lm")

    label(draw, (68, 145), "Start with a market profile", 38, "#f3f5f7", True)
    label(draw, (68, 191), "Useful on first open. Fully editable after that.", 18, "#909aa6")
    setup_notes = [
        (250, 284, "No request until you choose", "1"),
        (310, 302, "Profiles become normal watchlists", "2"),
        (370, 270, "Custom symbols are first-class", "3"),
    ]
    for y, width, text, number in setup_notes:
        alpha_box(image, (68, y, 68 + width, y + 48), 15, (21, 26, 33, 255), (46, 55, 66, 255))
        draw = ImageDraw.Draw(image)
        alpha_box(image, (82, y + 10, 110, y + 38), 8, (48, 209, 88, 24), (48, 209, 88, 80))
        draw = ImageDraw.Draw(image)
        label(draw, (96, y + 24), number, 11, "#30d158", True, "mm")
        label(draw, (122, y + 24), text, 14, "#dbe0e6", True, "lm")
    label(draw, (68, 633), "Fictional product preview · Choosing a profile enables direct best-effort market requests", 12, "#697480")

    panel = (742, 78, 1230, 688)
    shadowed_box(image, panel, 24, (18, 22, 28, 255), (50, 58, 69, 255), 22, 16)
    draw = ImageDraw.Draw(image)
    label(draw, (772, 115), "Omarchy Markets", 22, "#f2f4f6", True)
    label(draw, (772, 139), "MARKET DATA IS OFF", 11, "#7f8995")
    alpha_box(image, (1175, 99, 1205, 129), 9, (255, 255, 255, 10))
    draw = ImageDraw.Draw(image)
    label(draw, (1190, 114), "↻", 20, "#697480", anchor="mm")

    alpha_box(image, (765, 158, 1207, 231), 17, (255, 255, 255, 9), (48, 57, 68, 255))
    draw = ImageDraw.Draw(image)
    label(draw, (786, 183), "Choose your first market view", 16, "#f3f5f7", True)
    label(draw, (786, 207), "Profiles are editable starting points. No accounts or trades.", 10, "#7f8995")

    cards = [
        (244, "1", "Markets", "Global indices + volatility"),
        (298, "2", "Magnificent 7", "US mega-cap technology"),
        (352, "3", "Crypto", "Established large-cap assets"),
        (406, "4", "Meme Coins", "Highly speculative · high volatility"),
        (460, "5", "AI & Semiconductors", "Chips, foundries + equipment"),
        (514, "6", "UK Markets", "Indices, sterling + London leaders"),
    ]
    for index, (y, number, name, description) in enumerate(cards):
        alpha_box(image, (765, y, 1207, y + 47), 12,
                  (48, 209, 88, 18) if index == 0 else (255, 255, 255, 5),
                  (48, 209, 88, 85) if index == 0 else (47, 55, 65, 180))
        draw = ImageDraw.Draw(image)
        alpha_box(image, (778, y + 10, 805, y + 37), 7, (255, 255, 255, 9))
        draw = ImageDraw.Draw(image)
        label(draw, (791, y + 23), number, 10, "#9ca6b1", True, "mm")
        label(draw, (817, y + 18), name, 13, "#eef1f4", True)
        label(draw, (817, y + 36), description, 9, "#77828e")
        alpha_box(image, (1143, y + 10, 1194, y + 37), 8, (255, 255, 255, 10))
        draw = ImageDraw.Draw(image)
        label(draw, (1168, y + 23), "Choose", 9, "#cfd5dc", anchor="mm")

    alpha_box(image, (916, 582, 1057, 618), 10, (255, 255, 255, 10), (48, 57, 68, 255))
    draw = ImageDraw.Draw(image)
    label(draw, (986, 600), "Start custom", 11, "#dce1e6", True, "mm")
    label(draw, (986, 665), "YAHOO FINANCE CHART · UNOFFICIAL · INFORMATIONAL ONLY", 10, "#697480", anchor="ma")

    image.convert("RGB").save(SETUP_OUTPUT, optimize=True)


if __name__ == "__main__":
    render()
    render_setup()
