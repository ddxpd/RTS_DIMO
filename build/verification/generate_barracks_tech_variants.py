from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps
from pathlib import Path
import math
import random

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "tools" / "effect-gallery" / "generated"
OUT.mkdir(parents=True, exist_ok=True)
random.seed(2309)

W, H = 1600, 1000
BASE = Image.open(OUT / "barracks_tech_base.png").convert("RGBA")
BASE_CROP = BASE.crop(BASE.getbbox())

FONT_BOLD = r"C:\Windows\Fonts\seguisb.ttf"
FONT_MONO = r"C:\Windows\Fonts\consolab.ttf"
FONT_REG = r"C:\Windows\Fonts\segoeui.ttf"

def font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except Exception:
        return ImageFont.load_default()

def linear_gradient(size, top, bottom):
    grad = Image.linear_gradient("L").resize(size)
    return Image.merge("RGBA", (*Image.new("RGB", size, top).split(), grad.point(lambda x: x)))

def radial_glow(size, center, radius, color, max_alpha=120):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = center
    steps = 72
    for i in range(steps, 0, -1):
        r = radius * i / steps
        alpha = int(max_alpha * (1 - i / steps) ** 1.7)
        d.ellipse((cx-r, cy-r, cx+r, cy+r), fill=color + (alpha,))
    return layer.filter(ImageFilter.GaussianBlur(radius * 0.06))

def rounded_panel(draw, box, fill=(10, 24, 31, 185), outline=(97, 216, 255, 120), width=2, radius=18):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)

def draw_tech_grid(image, spacing=42, color=(83, 175, 205, 28), bold_every=6, bold_color=(105, 207, 238, 42)):
    d = ImageDraw.Draw(image, "RGBA")
    for x in range(0, image.width, spacing):
        c = bold_color if (x // spacing) % bold_every == 0 else color
        d.line((x, 0, x, image.height), fill=c, width=1)
    for y in range(0, image.height, spacing):
        c = bold_color if (y // spacing) % bold_every == 0 else color
        d.line((0, y, image.width, y), fill=c, width=1)
    return image

def model_layer(size, tint=None, opacity=1.0, glow_color=(90, 190, 255), glow_strength=7):
    fitted = ImageOps.contain(BASE_CROP, size, method=Image.LANCZOS)
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    x = (size[0] - fitted.width) // 2
    y = int((size[1] - fitted.height) * 0.54)
    if glow_strength:
        alpha = fitted.getchannel("A").point(lambda a: min(255, int(a * 0.72)))
        glow = Image.new("RGBA", fitted.size, glow_color + (0,))
        glow.putalpha(alpha)
        for _ in range(glow_strength):
            glow = glow.filter(ImageFilter.GaussianBlur(14))
        big_glow = Image.new("RGBA", size, (0, 0, 0, 0))
        big_glow.alpha_composite(glow, (x, y))
        canvas.alpha_composite(big_glow)
    if tint:
        rgb = Image.new("RGBA", fitted.size, tint + (0,))
        rgb.putalpha(fitted.getchannel("A").point(lambda a: int(a * opacity)))
        fitted = Image.composite(rgb, fitted, rgb.getchannel("A"))
    canvas.alpha_composite(fitted, (x, y))
    return canvas, fitted.getbbox()

def hud_frame(d, title, subtitle, accent=(86, 205, 255, 255), tag="HUMAN FACTION"):
    rounded_panel(d, (30, 28, W-30, H-28), fill=(5, 13, 19, 82), outline=accent, width=3, radius=24)
    d.line((30, 100, W-30, 100), fill=(90, 170, 200, 75), width=1)
    d.line((30, H-92, W-30, H-92), fill=(90, 170, 200, 75), width=1)
    corners = [(52, 52, 170, 72), (W-170, 52, W-52, 72), (52, H-72, 170, H-52), (W-170, H-72, W-52, H-52)]
    for box in corners:
        d.rounded_rectangle(box, radius=7, fill=(6, 20, 28, 175), outline=accent, width=2)
    f1 = font(FONT_BOLD, 33)
    f2 = font(FONT_MONO, 18)
    f3 = font(FONT_MONO, 16)
    d.text((74, 42), title, font=f1, fill=(226, 248, 255, 255))
    d.text((74, 72), subtitle, font=f2, fill=(121, 194, 219, 230))
    d.text((W-74, 44), tag, font=f3, fill=accent, anchor="ra")
    d.text((W-74, 68), "CONCEPT // NON-AI PROCEDURAL", font=f3, fill=(111, 171, 191, 205), anchor="ra")

def status_block(d, x, y, label, value, width=260, accent=(86, 205, 255, 255)):
    f1 = font(FONT_MONO, 16)
    f2 = font(FONT_MONO, 15)
    d.text((x, y), label, font=f1, fill=(162, 205, 220, 235))
    d.rounded_rectangle((x, y+26, x+width, y+34), radius=4, fill=(17, 44, 55, 220))
    d.rounded_rectangle((x, y+26, x+int(width*value/100), y+34), radius=4, fill=accent)
    d.text((x+width+12, y+19), f"{value}%", font=f2, fill=(218, 242, 250, 235))

def scanlines(image, opacity=20, step=4):
    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    for y in range(0, image.height, step):
        d.line((0, y, image.width, y), fill=(8, 24, 32, opacity))
    return Image.alpha_composite(image, overlay)

def save(image, name):
    path = OUT / name
    image.convert("RGB").save(path, "PNG", optimize=True)
    print(name, image.size, path.stat().st_size)

# 1. Blueprint fabrication module
img = linear_gradient((W, H), (7, 19, 34), (1, 7, 14))
img = draw_tech_grid(img, 40, (60, 132, 190, 21), 6, (76, 157, 210, 39))
img.alpha_composite(radial_glow(img.size, (780, 580), 620, (30, 110, 180), 100))
d = ImageDraw.Draw(img, "RGBA")
for r in [430, 520, 610, 700]:
    d.ellipse((800-r, 560-int(r*0.62), 800+r, 560+int(r*0.62)), outline=(68, 148, 205, 34), width=2)
for a in range(0, 360, 10):
    rad = math.radians(a)
    if a % 30 == 0:
        d.line((800-math.cos(rad)*650, 560-math.sin(rad)*403, 800+math.cos(rad)*650, 560+math.sin(rad)*403), fill=(61, 137, 193, 23), width=2)
model, bbox = model_layer((1150, 820), tint=(43, 141, 210), opacity=.54, glow_color=(34, 112, 190), glow_strength=5)
img.alpha_composite(model, (190, 70))
d = ImageDraw.Draw(img, "RGBA")
# blueprint callouts
callouts = [(250, 275, 455, 368), (1135, 360, 950, 468), (410, 765, 620, 708), (1175, 710, 965, 762)]
for x1,y1,x2,y2 in callouts:
    d.line((x1,y1,x2,y2), fill=(111, 212, 255, 135), width=2)
    d.ellipse((x1-5,y1-5,x1+5,y1+5), fill=(170, 240, 255, 210))
labels = [(190, 225), (960, 325), (620, 755), (965, 775)]
texts = ["MODULAR ARMOR PLATE", "DRONE ASSEMBLY GANTRY", "PERSONNEL AIRLOCK", "FIELD REACTOR CELL"]
for (x,y), text in zip(labels, texts):
    rounded_panel(d, (x, y, x+285, y+40), fill=(8, 26, 39, 195), outline=(93, 181, 230, 95), width=1, radius=8)
    d.text((x+14, y+10), text, font=font(FONT_MONO, 15), fill=(194, 235, 250, 240))
hud_frame(d, "HUMAN BARRACKS", "FABRICATION MODULE // SCHEMATIC OVERLAY")
status_block(d, 95, 828, "PRODUCTION", 88)
status_block(d, 95, 888, "POWER", 64)
status_block(d, 1235, 828, "ARMOR", 74, width=200)
img = scanlines(img, 16)
save(img, "barracks_tech_blueprint.png")

# 2. Night operations holographic deployment
img = linear_gradient((W, H), (3, 15, 26), (7, 39, 52))
img = draw_tech_grid(img, 56, (57, 171, 190, 16), 8, (69, 203, 224, 27))
img.alpha_composite(radial_glow(img.size, (780, 590), 700, (16, 118, 150), 120))
d = ImageDraw.Draw(img, "RGBA")
for i in range(190):
    x, y = random.randint(40, W-40), random.randint(40, H-40)
    r = random.uniform(.5, 1.8)
    a = random.randint(40, 150)
    d.ellipse((x-r,y-r,x+r,y+r), fill=(180, 245, 255,a))
for r, alpha in [(470, 18), (370, 24), (275, 31)]:
    d.ellipse((790-r, 590-int(r*.55), 790+r, 590+int(r*.55)), outline=(113, 238, 255, alpha), width=3)
ground = Image.new("RGBA", (W,H), (0,0,0,0))
gd = ImageDraw.Draw(ground)
gd.ellipse((460, 760, 1120, 885), fill=(57, 215, 235, 72))
ground = ground.filter(ImageFilter.GaussianBlur(38))
img.alpha_composite(ground)
model, _ = model_layer((1100, 780), tint=(25, 96, 142), opacity=.26, glow_color=(64, 213, 255), glow_strength=10)
img.alpha_composite(model, (220, 85))
d = ImageDraw.Draw(img, "RGBA")
for i in range(11):
    y = 780 + i*9 + i*i*.35
    width = 250 + i*27
    d.line((800-width/2, y, 800+width/2, y), fill=(101, 228, 255, max(5, 72-i*6)), width=2)
d.polygon([(705,545),(755,505),(815,493),(858,510),(875,548),(850,590),(785,610),(720,590)], outline=(160,247,255,90))
rounded_panel(d, (1115, 250, 1450, 450), fill=(4, 22, 31, 190), outline=(91, 219, 245, 95), width=2, radius=16)
for i,(label,val) in enumerate([("TRAINING",96),("SHIELD",78),("RESPONSE",84)]):
    status_block(d, 1140, 282+i*54, label, val, width=180, accent=(90, 229, 255,255))
hud_frame(d, "NIGHT OPS BARRACKS", "DEPLOYMENT READY // ACTIVE HOLOGRAM", accent=(83, 226, 255,255))
img = scanlines(img, 24)
save(img, "barracks_tech_night_ops.png")

# 3. Expansion module family
img = linear_gradient((W,H), (14, 27, 35), (7, 14, 21))
img = draw_tech_grid(img, 64, (70, 143, 159, 14), 7, (87, 171, 190, 22))
img.alpha_composite(radial_glow(img.size, (800, 560), 700, (16, 84, 102), 85))
d = ImageDraw.Draw(img, "RGBA")
panels = [
    (90, 175, 525, 720, "FABRICATION", (76,196,255), .18),
    (575, 175, 1010, 720, "MEDICAL", (95,255,193), .12),
    (1060, 175, 1495, 720, "DRONE BAY", (255,181,78), .15),
]
for idx,(x1,y1,x2,y2,name,color,tint) in enumerate(panels):
    rounded_panel(d, (x1,y1,x2,y2), fill=(8, 21, 30, 190), outline=color+(105,), width=2, radius=22)
    d.text(((x1+x2)//2, y1+28), name, font=font(FONT_BOLD, 24), fill=(226,250,255,245), anchor="mm")
    d.text(((x1+x2)//2, y1+58), f"MODULE {idx+1:02d}", font=font(FONT_MONO, 15), fill=color+(220,), anchor="mm")
    panel_size=(x2-x1-60, y2-y1-135)
    model,_ = model_layer(panel_size, tint=color, opacity=tint, glow_color=color, glow_strength=6)
    img.alpha_composite(model, (x1+30, y1+90))
    d = ImageDraw.Draw(img, "RGBA")
    d.rounded_rectangle((x1+22,y1+82,x2-22,y2-22), radius=16, outline=color+(55,), width=1)
    for i in range(4):
        xx=x1+50+i*95
        d.rounded_rectangle((xx,y2-62,xx+72,y2-48), radius=6, fill=color+(38,), outline=color+(100,), width=1)
hud_frame(d, "BARRACKS EXPANSION SET", "HIGH-TECH HUMAN MODULE FAMILY", accent=(102,211,255,255))
d.text((90, 800), "SHARED ARMOR LANGUAGE / DISTINCT FUNCTIONAL SILHOUETTES", font=font(FONT_MONO, 17), fill=(148,200,220,235))
save(img, "barracks_tech_modules.png")

# 4. Combat ready field profile
img = linear_gradient((W,H), (17, 24, 25), (5, 9, 11))
img.alpha_composite(radial_glow(img.size, (790, 620), 760, (28, 57, 62), 90))
d = ImageDraw.Draw(img, "RGBA")
for i in range(90):
    x=random.randint(0,W); y=random.randint(600,H); r=random.uniform(12,60); a=random.randint(5,20)
    d.ellipse((x-r,y-r*.35,x+r,y+r*.35), fill=(140,180,190,a))
img = draw_tech_grid(img, 80, (70,102,105, 11), 8, (79,121,125, 18))
ground = Image.new("RGBA",(W,H),(0,0,0,0)); gd=ImageDraw.Draw(ground)
gd.polygon([(180,820),(1420,820),(1530,910),(80,910)], fill=(11,20,22,190))
img.alpha_composite(ground.filter(ImageFilter.GaussianBlur(8)))
model,_ = model_layer((1060, 760), tint=(19, 55, 72), opacity=.14, glow_color=(51, 154, 204), glow_strength=8)
img.alpha_composite(model, (260, 85))
d = ImageDraw.Draw(img, "RGBA")
# energy shield
for i in range(10):
    r=390+i*12
    alpha=max(5, 28-i*2)
    d.ellipse((790-r, 560-r*.74, 790+r, 560+r*.74), outline=(93,201,236,alpha), width=2)
for row in range(9):
    for col in range(13):
        cx=390+col*67
        cy=320+row*51 + (col%2)*25
        if random.random() < .38:
            radius=28
            points=[]
            for k in range(6):
                ang=math.radians(60*k)
                points.append((cx+math.cos(ang)*radius, cy+math.sin(ang)*radius*.85))
            d.polygon(points, outline=(106,216,248,30))
# warning chevrons
for i in range(6):
    x=130+i*250
    d.polygon([(x,900),(x+90,900),(x+45,942)], fill=(255,177,63,42), outline=(255,204,110,110))
hud_frame(d, "COMBAT READY BARRACKS", "FIELD PROFILE // SHIELD ONLINE", accent=(255,178,72,255), tag="IRON FRONT")
status_block(d, 95, 820, "STRUCTURE", 82, width=220, accent=(255,178,72,255))
status_block(d, 95, 878, "SHIELD", 77, width=220, accent=(92,200,246,255))
rounded_panel(d, (1180, 800, 1450, 910), fill=(8,20,27,190), outline=(255,178,72,100), width=2, radius=16)
d.text((1315, 838), "PERSONNEL", font=font(FONT_MONO, 17), fill=(238,245,248,235), anchor="mm")
d.text((1315, 872), "x 12 / CYCLE", font=font(FONT_BOLD, 28), fill=(255,209,134,245), anchor="mm")
img = scanlines(img, 12)
save(img, "barracks_tech_combat_ready.png")

print("GENERATED_COUNT", 4)
