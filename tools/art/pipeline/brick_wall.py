# Brick wall module from a front-elevation concept: one box per brick course (silhouette measured from the
# image), protruding coping on top, concept image as albedo on both faces. Same footprint as wall_wallpaper.glb.
# Usage: python3 brick_wall.py concept.png out.glb
import sys, io, struct, json, numpy as np
from PIL import Image, ImageFilter
src, out = sys.argv[1], sys.argv[2]
im = Image.open(src).convert('RGB'); A = np.asarray(im).astype(float)
bg = A[5, 5]; mask = np.abs(A - bg).max(2) > 25
# course boundaries (mortar lines) in concept px; first band is the coping
cuts = [29, 112, 155, 235, 337, 440, 545, 647, 745, 847, 987]
X0, X1, Y0, Y1 = 31, 1504, cuts[0], cuts[-1]
W_M, H_M = 2.6, 1.9                      # module size of the wallpaper wall
SX, SY = W_M / (X1 - X0), H_M / (Y1 - Y0)
CX = (X0 + X1) / 2
boxes = []
for i, (a, b) in enumerate(zip(cuts[:-1], cuts[1:])):
    ls, rs = [], []
    for y in range(a + 3, b - 3):
        xs = np.where(mask[y])[0]
        if len(xs): ls.append(xs.min()); rs.append(xs.max())
    half = 0.09 if i == 0 else (0.07 if i == len(cuts) - 2 else 0.06)
    boxes.append(((int(np.median(ls)), int(np.median(rs)), a, b), half))
crop = (X0 - 8, Y0 - 4, X1 + 8, Y1 + 4)
TW, TH = 2048, 1024
tex = im.crop(crop).resize((TW, TH), Image.LANCZOS)
def uv(px, py):
    return ((px - crop[0]) / (crop[2] - crop[0]), (py - crop[1]) / (crop[3] - crop[1]))
# normal map: mortar grooves and chipped edges from luminance detail
g = np.asarray(tex.convert('L')).astype(float) / 255
g = g - np.asarray(Image.fromarray((g * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(16))).astype(float) / 255
g = np.asarray(Image.fromarray(np.clip(g * 255 + 128, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))).astype(float) / 255
k = 6.0
dx = (np.roll(g, -1, 1) - np.roll(g, 1, 1)) * k
dy = (np.roll(g, -1, 0) - np.roll(g, 1, 0)) * k
n = np.dstack([-dx, dy, np.ones_like(g)]); n /= np.linalg.norm(n, axis=2, keepdims=True)
nrm = Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8))
# roughness: matte brick, mortar rougher, rusty patches a touch smoother
a = np.asarray(tex).astype(float); L = a.mean(2)
rust = np.clip((a[..., 0] - a[..., 2] - 15) / 35, 0, 1)
mr = np.zeros((TH, TW, 3), np.uint8); mr[..., 1] = np.clip(225 - 35 * rust + 0.15 * (60 - L), 150, 255).astype(np.uint8)
mr = Image.fromarray(mr)
P, N, UV, I = [], [], [], []
def quad(vs, nn, uvs):
    b = len(P); P.extend(vs); N.extend([nn] * 4); UV.extend(uvs); I.extend([b, b + 1, b + 2, b, b + 2, b + 3])
X = lambda px: (px - CX) * SX
Y = lambda py: (Y1 - py) * SY
for (x0, x1, y0, y1), h in boxes:
    e = 3
    quad([(X(x0), Y(y1), h), (X(x1), Y(y1), h), (X(x1), Y(y0), h), (X(x0), Y(y0), h)], (0, 0, 1),
         [uv(x0, y1), uv(x1, y1), uv(x1, y0), uv(x0, y0)])
    quad([(X(x1), Y(y1), -h), (X(x0), Y(y1), -h), (X(x0), Y(y0), -h), (X(x1), Y(y0), -h)], (0, 0, -1),
         [uv(x1, y1), uv(x0, y1), uv(x0, y0), uv(x1, y0)])
    quad([(X(x0), Y(y0), h), (X(x1), Y(y0), h), (X(x1), Y(y0), -h), (X(x0), Y(y0), -h)], (0, 1, 0),
         [uv(x0, y0 + e), uv(x1, y0 + e), uv(x1, y0 + e), uv(x0, y0 + e)])
    quad([(X(x0), Y(y1), -h), (X(x1), Y(y1), -h), (X(x1), Y(y1), h), (X(x0), Y(y1), h)], (0, -1, 0),
         [uv(x0, y1 - e), uv(x1, y1 - e), uv(x1, y1 - e), uv(x0, y1 - e)])
    quad([(X(x0), Y(y1), -h), (X(x0), Y(y1), h), (X(x0), Y(y0), h), (X(x0), Y(y0), -h)], (-1, 0, 0),
         [uv(x0 + e, y1), uv(x0 + e, y1), uv(x0 + e, y0), uv(x0 + e, y0)])
    quad([(X(x1), Y(y1), h), (X(x1), Y(y1), -h), (X(x1), Y(y0), -h), (X(x1), Y(y0), h)], (1, 0, 0),
         [uv(x1 - e, y1), uv(x1 - e, y1), uv(x1 - e, y0), uv(x1 - e, y0)])
P = np.array(P, '<f4'); N = np.array(N, '<f4'); UV = np.array(UV, '<f4'); I = np.array(I, '<u2')
T = P[I.reshape(-1, 3)]; fn = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0]); vn = N[I.reshape(-1, 3)[:, 0]]
I3 = I.reshape(-1, 3); flip = (fn * vn).sum(1) < 0; I3[flip] = I3[flip][:, [0, 2, 1]]; I = I3.ravel()
def enc(img, fmt):
    b = io.BytesIO(); img.save(b, fmt, **({'quality': 90} if fmt == 'JPEG' else {})); return b.getvalue()
blobs = [P.tobytes(), N.tobytes(), UV.tobytes(), I.tobytes(), enc(tex, 'JPEG'), enc(nrm, 'PNG'), enc(mr, 'JPEG')]
bvs = []; binb = b''
for bl in blobs:
    bvs.append({'buffer': 0, 'byteOffset': len(binb), 'byteLength': len(bl)}); binb += bl + b'\0' * ((-len(bl)) % 4)
for k_ in range(3): bvs[k_]['target'] = 34962
bvs[3]['target'] = 34963
g = {'asset': {'version': '2.0', 'generator': 'cultic tools/pipeline/brick_wall.py'}, 'scene': 0, 'scenes': [{'nodes': [0]}],
     'nodes': [{'name': 'brick_wall', 'mesh': 0}],
     'meshes': [{'name': 'brick_wall', 'primitives': [{'attributes': {'POSITION': 0, 'NORMAL': 1, 'TEXCOORD_0': 2}, 'indices': 3, 'material': 0}]}],
     'materials': [{'name': 'brick_wall', 'pbrMetallicRoughness': {'baseColorTexture': {'index': 0}, 'metallicFactor': 0.0, 'roughnessFactor': 1.0,
                    'metallicRoughnessTexture': {'index': 2}}, 'normalTexture': {'index': 1}}],
     'textures': [{'source': 0, 'sampler': 0}, {'source': 1, 'sampler': 0}, {'source': 2, 'sampler': 0}],
     'samplers': [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 33071, 'wrapT': 33071}],
     'images': [{'bufferView': 4, 'mimeType': 'image/jpeg', 'name': 'brick_wall_albedo'}, {'bufferView': 5, 'mimeType': 'image/png', 'name': 'brick_wall_normal'},
                {'bufferView': 6, 'mimeType': 'image/jpeg', 'name': 'brick_wall_metal_rough'}],
     'accessors': [{'bufferView': 0, 'componentType': 5126, 'count': len(P), 'type': 'VEC3', 'min': P.min(0).tolist(), 'max': P.max(0).tolist()},
                   {'bufferView': 1, 'componentType': 5126, 'count': len(P), 'type': 'VEC3'},
                   {'bufferView': 2, 'componentType': 5126, 'count': len(P), 'type': 'VEC2'},
                   {'bufferView': 3, 'componentType': 5123, 'count': len(I), 'type': 'SCALAR'}],
     'bufferViews': bvs, 'buffers': [{'byteLength': len(binb)}]}
js = json.dumps(g, separators=(',', ':')).encode(); js += b' ' * ((-len(js)) % 4)
open(out, 'wb').write(struct.pack('<4sII', b'glTF', 2, 28 + len(js) + len(binb)) + struct.pack('<I4s', len(js), b'JSON') + js + struct.pack('<I4s', len(binb), b'BIN\0') + binb)
print('courses', [(b[0], b[1]) for b, _ in boxes]); print('tris', len(I) // 3, 'size %.3fx%.3fx%.3f m' % tuple(P.max(0) - P.min(0)), 'bytes', 28 + len(js) + len(binb))
