# Plant colour grade: leaves / teal patina / copper / soil detected by hue and saturation, each pulled to its concept colour with a
# per-channel gain (soft masks), glossier leaves. Usage: plant_grade.py bc.png mr.png out_bc.jpg out_mr.jpg
import sys, numpy as np
from PIL import Image, ImageFilter
bcf, mrf, obc, omr = sys.argv[1:5]
a = np.asarray(Image.open(bcf).convert('RGB')).astype(float); mr = np.asarray(Image.open(mrf).convert('RGB')).astype(float)
R, G, B = a[..., 0], a[..., 1], a[..., 2]; sat = (a.max(2) - a.min(2)) / (a.max(2) + 1)
teal = (B > R + 10) & (np.abs(G - B) < 30) & (G > R)
leaf = (G >= R) & (G > B + 8) & ~teal
warm = (R > G + 8) & (G >= B - 5)
copper = warm & (sat > 0.3) & (sat < 0.75)   # rims and crescents
soil = warm & (sat >= 0.75)
TARGET = {'leaf': (54, 80, 30), 'teal': (34, 62, 56), 'copper': (120, 80, 40), 'soil': (70, 45, 24)}
def soft(m):
    return np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5))).astype(float)[..., None] / 255
out = a.copy(); wsum = np.zeros(a.shape[:2] + (1,))
for name, m in (('leaf', leaf), ('teal', teal), ('copper', copper), ('soil', soil)):
    gain = np.array(TARGET[name]) / np.maximum(a[m].mean(0), 1)
    w = soft(m); out = out * (1 - w) + a * gain * w; wsum += w
# soil and everything else: slightly darker to sit with the graded parts
rest = np.clip(1 - wsum, 0, 1); out = out * (1 - rest) + a * 0.8 * rest
Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).save(obc, quality=90)
lw = soft(leaf)[..., 0]; cw = soft(copper)[..., 0]; m = mr.copy()
m[..., 1] = m[..., 1] * (1 - lw) + 140 * lw          # waxy leaves (~0.55)
m[..., 1] = m[..., 1] * (1 - cw) + 115 * cw          # worn copper (~0.45)
m[..., 2] = m[..., 2] * (1 - cw) + 255 * cw          # copper is metal
Image.fromarray(np.clip(m, 0, 255).astype(np.uint8)).save(omr, quality=92)
print({k: tuple(np.round(np.array(v) / 1)) for k, v in TARGET.items()})
