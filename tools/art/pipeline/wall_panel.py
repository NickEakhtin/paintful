# Wainscot wall panel module built from a front-elevation concept: stacked moulding boxes, concept image as albedo.
# Usage: python3 wall_panel.py concept.png out.glb
import sys, io, struct, json, numpy as np
from PIL import Image, ImageFilter
src, out = sys.argv[1], sys.argv[2]
im = Image.open(src).convert('RGB')
# panel bounds in concept pixels and target width (one wallpaper wall module = 2.6 m)
X0, X1, Y0, Y1 = 95, 1677, 98, 818
S = 2.6 / (X1 - X0)
CX = (X0 + X1) / 2
# (x0, x1, y0, y1) in concept px, front depth z in metres (back of every box at z=0)
boxes = [
    ((95, 1677, 98, 136), 0.12),    # cap rail
    ((110, 1662, 136, 205), 0.085), # frieze
    ((118, 1652, 205, 222), 0.095), # bead
    ((127, 1643, 222, 682), 0.05),  # body / recessed plank panel
    ((127, 252, 222, 682), 0.07),   # left stile
    ((1520, 1643, 222, 682), 0.07), # right stile
    ((252, 1520, 222, 281), 0.07),  # top rail
    ((252, 1520, 632, 682), 0.07),  # bottom rail
    ((252, 288, 281, 632), 0.085),  # moulding left
    ((1496, 1520, 281, 632), 0.085),# moulding right
    ((288, 1496, 281, 307), 0.085), # moulding top
    ((288, 1496, 612, 632), 0.085), # moulding bottom
    ((115, 1655, 682, 706), 0.09),  # lower bead
    ((105, 1666, 706, 818), 0.10),  # baseboard
]
# texture: crop to the panel (+ small margin) and keep the crop's px->uv mapping
M = 6
cx0, cy0, cx1, cy1 = X0 - M - 10, Y0 - M, X1 + M + 10, Y1 + M
crop = im.crop((cx0, cy0, cx1, cy1))
TW, TH = 2048, 1024
tex = crop.resize((TW, TH), Image.LANCZOS)
def uv(px, py):
    return ((px - cx0) / (cx1 - cx0), (py - cy0) / (cy1 - cy0))
# normal map from luminance detail (plank grooves, wear), Y+ (glTF / Godot convention)
g = np.asarray(tex.convert('L')).astype(float) / 255
g = g - np.asarray(Image.fromarray((g * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(12))).astype(float) / 255
g = np.asarray(Image.fromarray(np.clip(g * 255 + 128, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1))).astype(float) / 255
k = 4.0
dx = (np.roll(g, -1, 1) - np.roll(g, 1, 1)) * k
dy = (np.roll(g, -1, 0) - np.roll(g, 1, 0)) * k
n = np.dstack([-dx, dy, np.ones_like(g)]); n /= np.linalg.norm(n, axis=2, keepdims=True)
nrm = Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8))
# metal-rough: worn copper-brown wood a bit glossier than the paint
a = np.asarray(tex).astype(float)
cop = np.clip((a[..., 0] - a[..., 2] - 20) / 40, 0, 1)
mr = np.zeros((TH, TW, 3), np.uint8); mr[..., 1] = (205 - 70 * cop).astype(np.uint8)
mr = Image.fromarray(mr)
P, N, UV, I = [], [], [], []
def quad(vs, nn, uvs):
    b = len(P); P.extend(vs); N.extend([nn] * 4); UV.extend(uvs); I.extend([b, b + 1, b + 2, b, b + 2, b + 3])
for (x0, x1, y0, y1), z in boxes:
    X = lambda px: (px - CX) * S
    Y = lambda py: (Y1 - py) * S
    e = 2  # sample side faces slightly inside the edge
    # front (+Z)
    quad([(X(x0), Y(y1), z), (X(x1), Y(y1), z), (X(x1), Y(y0), z), (X(x0), Y(y0), z)], (0, 0, 1),
         [uv(x0, y1), uv(x1, y1), uv(x1, y0), uv(x0, y0)])
    # top (+Y)
    quad([(X(x0), Y(y0), z), (X(x1), Y(y0), z), (X(x1), Y(y0), 0), (X(x0), Y(y0), 0)], (0, 1, 0),
         [uv(x0, y0 + e), uv(x1, y0 + e), uv(x1, y0 + e), uv(x0, y0 + e)])
    # bottom (-Y)
    quad([(X(x0), Y(y1), 0), (X(x1), Y(y1), 0), (X(x1), Y(y1), z), (X(x0), Y(y1), z)], (0, -1, 0),
         [uv(x0, y1 - e), uv(x1, y1 - e), uv(x1, y1 - e), uv(x0, y1 - e)])
    # left (-X)
    quad([(X(x0), Y(y1), 0), (X(x0), Y(y1), z), (X(x0), Y(y0), z), (X(x0), Y(y0), 0)], (-1, 0, 0),
         [uv(x0 + e, y1), uv(x0 + e, y1), uv(x0 + e, y0), uv(x0 + e, y0)])
    # right (+X)
    quad([(X(x1), Y(y1), z), (X(x1), Y(y1), 0), (X(x1), Y(y0), 0), (X(x1), Y(y0), z)], (1, 0, 0),
         [uv(x1 - e, y1), uv(x1 - e, y1), uv(x1 - e, y0), uv(x1 - e, y0)])
P = np.array(P, '<f4'); N = np.array(N, '<f4'); UV = np.array(UV, '<f4'); I = np.array(I, '<u2')
# fix winding to match normals
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
g = {'asset': {'version': '2.0', 'generator': 'cultic tools/pipeline/wall_panel.py'}, 'scene': 0, 'scenes': [{'nodes': [0]}],
     'nodes': [{'name': 'wall_panel', 'mesh': 0}],
     'meshes': [{'name': 'wall_panel', 'primitives': [{'attributes': {'POSITION': 0, 'NORMAL': 1, 'TEXCOORD_0': 2}, 'indices': 3, 'material': 0}]}],
     'materials': [{'name': 'wall_panel', 'pbrMetallicRoughness': {'baseColorTexture': {'index': 0}, 'metallicFactor': 0.0, 'roughnessFactor': 1.0,
                    'metallicRoughnessTexture': {'index': 2}}, 'normalTexture': {'index': 1}}],
     'textures': [{'source': 0, 'sampler': 0}, {'source': 1, 'sampler': 0}, {'source': 2, 'sampler': 0}],
     'samplers': [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 33071, 'wrapT': 33071}],
     'images': [{'bufferView': 4, 'mimeType': 'image/jpeg', 'name': 'wall_panel_albedo'}, {'bufferView': 5, 'mimeType': 'image/png', 'name': 'wall_panel_normal'},
                {'bufferView': 6, 'mimeType': 'image/jpeg', 'name': 'wall_panel_metal_rough'}],
     'accessors': [{'bufferView': 0, 'componentType': 5126, 'count': len(P), 'type': 'VEC3', 'min': P.min(0).tolist(), 'max': P.max(0).tolist()},
                   {'bufferView': 1, 'componentType': 5126, 'count': len(P), 'type': 'VEC3'},
                   {'bufferView': 2, 'componentType': 5126, 'count': len(P), 'type': 'VEC2'},
                   {'bufferView': 3, 'componentType': 5123, 'count': len(I), 'type': 'SCALAR'}],
     'bufferViews': bvs, 'buffers': [{'byteLength': len(binb)}]}
js = json.dumps(g, separators=(',', ':')).encode(); js += b' ' * ((-len(js)) % 4)
open(out, 'wb').write(struct.pack('<4sII', b'glTF', 2, 28 + len(js) + len(binb)) + struct.pack('<I4s', len(js), b'JSON') + js + struct.pack('<I4s', len(binb), b'BIN\0') + binb)
print('tris', len(I) // 3, 'size %.3fx%.3fx%.3f m' % tuple(P.max(0) - P.min(0)), 'bytes', 28 + len(js) + len(binb))
