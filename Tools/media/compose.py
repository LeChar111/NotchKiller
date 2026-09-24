"""Compose les images d'un enregistrement (wrec) sur le fond commun et écrit
la liste de concaténation ffmpeg, avec la durée réelle de chaque image.

    python3 compose.py <images brutes> <sortie>
"""
import glob, os, sys
from PIL import Image, ImageDraw, ImageFilter

def backdrop(w, h):
    bg = Image.new('RGB', (w, h), (10, 10, 18))
    glow = Image.new('RGB', (w, h), (0, 0, 0))
    d = ImageDraw.Draw(glow)
    for (cx, cy, r, col) in [(0.18, 0.95, 0.55, (90, 60, 200)), (0.85, 0.85, 0.5, (230, 110, 70)),
                             (0.5, 1.25, 0.6, (40, 90, 200))]:
        R = int(r * w)
        d.ellipse([cx*w-R, cy*h-R, cx*w+R, cy*h+R], fill=col)
    glow = glow.filter(ImageFilter.GaussianBlur(w * 0.09))
    return Image.blend(bg, glow, 0.55)

if __name__ == '__main__':
    src, dst = sys.argv[1], sys.argv[2]
    os.makedirs(dst, exist_ok=True)
    files = sorted(glob.glob(f'{src}/f_*.png'))
    first = Image.open(files[0])
    W, H = first.size
    H2 = 1040  # le panneau le plus haut tient dans 520 pt
    bg = backdrop(W, H2)
    for f in files:
        im = Image.open(f).convert('RGBA').crop((0, 0, W, H2))
        out = bg.copy()
        out.paste(im, (0, 0), im)
        out.save(f'{dst}/{os.path.basename(f)}', optimize=False, compress_level=1)
    # fichier concat ffmpeg avec durées réelles
    times = [int(os.path.basename(f)[2:9]) for f in files]
    with open(f'{dst}/list.txt', 'w') as fh:
        for i, f in enumerate(files):
            dur = ((times[i+1] if i+1 < len(times) else times[i] + 2500) - times[i]) / 1000
            fh.write(f"file '{os.path.basename(f)}'\nduration {dur:.3f}\n")
        fh.write(f"file '{os.path.basename(files[-1])}'\n")
    print(W, H2, len(files))
