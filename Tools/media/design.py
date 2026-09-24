"""Visuels du README : bannière, aperçu social, captures mises en scène.

    python3 design.py <dossier des captures> <dossier de sortie>
"""
import sys, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from compose import backdrop

SH, OUT = sys.argv[1], sys.argv[2]
SF = '/System/Library/Fonts/SFNS.ttf'
MONO = '/System/Library/Fonts/SFNSMono.ttf'

def font(size, weight='Regular', path=SF):
    f = ImageFont.truetype(path, size)
    try: f.set_variation_by_name(weight)
    except Exception: pass
    return f

def screen_edge(img):
    """Bord supérieur d'un écran de MacBook : coins arrondis sombres."""
    w, h = img.size
    mask = Image.new('L', (w, h), 255)
    d = ImageDraw.Draw(mask)
    r = int(w * 0.018)
    d.rectangle([0, 0, w, r], fill=0)
    d.rounded_rectangle([0, 0, w, h + r], radius=r, fill=255)
    black = Image.new('RGB', (w, h), (0, 0, 0))
    return Image.composite(img, black, mask)

def text_center(d, cx, y, s, f, fill):
    w = d.textlength(s, font=f)
    d.text((cx - w / 2, y), s, font=f, fill=fill)

def pill_row(d, cx, y, labels, f):
    pad, gap, hgt = 30, 18, 64
    widths = [d.textlength(l, font=f) + 2 * pad for l in labels]
    x = cx - (sum(widths) + gap * (len(labels) - 1)) / 2
    for l, w in zip(labels, widths):
        d.rounded_rectangle([x, y, x + w, y + hgt], radius=hgt / 2, fill=(255, 255, 255, 22), outline=(255, 255, 255, 60), width=2)
        d.text((x + pad, y + hgt / 2), l, font=f, fill=(235, 235, 245, 230), anchor='lm')
        x += w + gap

def hero(path, W, H, panel_file, panel_w, title, tag, pills, title_size, tag_size, pill_size, gap):
    bg = backdrop(W, H).convert('RGBA')
    panel = Image.open(panel_file).convert('RGBA')
    panel = panel.resize((panel_w, int(panel.height * panel_w / panel.width)), Image.LANCZOS)
    bg.alpha_composite(panel, ((W - panel.width) // 2, 0))
    overlay = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    y = panel.height + gap
    text_center(d, W / 2, y, title, font(title_size, 'Bold'), (255, 255, 255, 255))
    y += int(title_size * 1.18)
    text_center(d, W / 2, y, tag, font(tag_size, 'Medium'), (225, 225, 240, 215))
    if pills:
        pill_row(d, W / 2, y + int(tag_size * 1.9), pills, font(pill_size, 'Semibold'))
    bg.alpha_composite(overlay)
    screen_edge(bg.convert('RGB')).save(path, optimize=True)

hero(f'{OUT}/hero.png', 2400, 1220, f'{SH}/home-summary.png', 1676,
     'NotchKiller', "L'encoche de votre MacBook devient un tableau de bord.",
     ['SwiftUI natif', 'macOS 15+', 'Claude Code', 'Sans télémétrie'], 150, 54, 32, 90)

hero(f'{OUT}/social-preview.png', 1280, 640, f'{SH}/home-summary.png', 900,
     'NotchKiller', "L'encoche du MacBook devient un tableau de bord.",
     None, 78, 30, 0, 36)

def framed(name, width=1800, pad_top=0, pad_bottom=70):
    im = Image.open(f'{SH}/{name}.png').convert('RGBA')
    W = width
    scale = min(1.0, (W - 120) / im.width)
    im = im.resize((int(im.width * scale), int(im.height * scale)), Image.LANCZOS)
    H = im.height + pad_top + pad_bottom
    bg = backdrop(W, H).convert('RGBA')
    bg.alpha_composite(im, ((W - im.width) // 2, pad_top))
    screen_edge(bg.convert('RGB')).save(f'{OUT}/{name}.png', optimize=True)

pages = ['home-summary', 'home-agenda', 'dev-projects', 'dev-ports', 'dev-docker', 'dev-terminal',
         'claude-sessions', 'claude-history', 'claude-mcp', 'media', 'system-stats', 'system-processes',
         'system-memory', 'system-cleanup', 'system-battery', 'system-controls', 'workshop-shelf',
         'workshop-clipboard', 'workshop-notes', 'workshop-calculator', 'workshop-actions', 'workshop-settings']
for p in pages:
    framed(p)

# Bandeau fermé : les quatre états côte à côte, chacun sous son bord d'écran.
bars = ['bar-claude', 'bar-music', 'bar-calendar', 'bar-done']
labels = ['Session Claude en cours', 'Lecture en cours', 'Prochain rendez-vous', 'Claude a fini']
ims = [Image.open(f'{SH}/{b}.png').convert('RGBA') for b in bars]
cw, ch = 1100, 330
W, H = cw * 2 + 60, ch * 2 + 60
sheet = Image.new('RGB', (W, H), (16, 16, 22))
for i, (im, lab) in enumerate(zip(ims, labels)):
    cell = backdrop(cw, ch).convert('RGBA')
    cell.alpha_composite(im, ((cw - im.width) // 2, 0))
    d = ImageDraw.Draw(cell)
    d.text((cw / 2, ch - 42), lab, font=font(30, 'Semibold'), fill=(235, 235, 245, 220), anchor='mm')
    cell = screen_edge(cell.convert('RGB'))
    sheet.paste(cell, (20 + (i % 2) * (cw + 20), 20 + (i // 2) * (ch + 20)))
sheet.save(f'{OUT}/bar-states.png', optimize=True)
print('ok')
