"""Rogne une capture de fenêtre (fond transparent) sur son contenu."""
import sys
from PIL import Image
im=Image.open(sys.argv[1]); bb=im.getchannel('A').point(lambda a:255 if a>8 else 0).getbbox()
im.crop(bb).save(sys.argv[2])
