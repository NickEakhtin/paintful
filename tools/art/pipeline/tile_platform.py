# Square floor platform (box) with a seamless tiling texture on top.
# The texture covers TILE_M metres and repeats; side faces use a plain strip of the same texture.
# Usage: python3 tile_platform.py seamless_tile.png out.glb [size_m=2.0] [height_m=0.1] [tile_m=1.0]
import sys, io, struct, json, numpy as np
from PIL import Image, ImageFilter
src, out = sys.argv[1], sys.argv[2]
S = float(sys.argv[3]) if len(sys.argv) > 3 else 2.0
H = float(sys.argv[4]) if len(sys.argv) > 4 else 0.1
T = float(sys.argv[5]) if len(sys.argv) > 5 else 1.0
tex = Image.open(src).convert('RGB')
# normal map: grout lines (dark thin lines) pressed in; derived from luminance detail
g = np.asarray(tex.convert('L')).astype(float) / 255
g = g - np.asarray(Image.fromarray((g * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(8))).astype(float) / 255
g = np.asarray(Image.fromarray(np.clip(g * 255 + 128, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1))).astype(float) / 255
dx = (np.roll(g, -1, 1) - np.roll(g, 1, 1)) * 3.0; dy = (np.roll(g, -1, 0) - np.roll(g, 1, 0)) * 3.0
n = np.dstack([-dx, dy, np.ones_like(g)]); n /= np.linalg.norm(n, axis=2, keepdims=True)
nrm = Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8))
# roughness: glazed tiles fairly smooth, grout rough
L = np.asarray(tex.convert('L')).astype(float)
grout = np.asarray(Image.fromarray(((np.abs(L - np.asarray(tex.convert('L').filter(ImageFilter.GaussianBlur(3))).astype(float)) > 18) * 255).astype(np.uint8))).astype(float) / 255
mr = np.zeros(L.shape + (3,), np.uint8); mr[..., 1] = (70 + 150 * grout).astype(np.uint8)
mr = Image.fromarray(mr)
h, r = S / 2, S / T
P, N, UV, I = [], [], [], []
def quad(vs, nn, uvs):
    b = len(P); P.extend(vs); N.extend([nn] * 4); UV.extend(uvs); I.extend([b, b + 1, b + 2, b, b + 2, b + 3])
quad([(-h, H, h), (h, H, h), (h, H, -h), (-h, H, -h)], (0, 1, 0), [(0, r), (r, r), (r, 0), (0, 0)])          # top, repeats
quad([(-h, 0, -h), (h, 0, -h), (h, 0, h), (-h, 0, h)], (0, -1, 0), [(0.02, 0.02)] * 4)                         # bottom
v0, v1 = 0.2, 0.2 + H / T                                                                                       # plain strip (inside an octagon row)
for nn, vs in (((0, 0, 1), [(-h, 0, h), (h, 0, h), (h, H, h), (-h, H, h)]), ((0, 0, -1), [(h, 0, -h), (-h, 0, -h), (-h, H, -h), (h, H, -h)]),
               ((1, 0, 0), [(h, 0, h), (h, 0, -h), (h, H, -h), (h, H, h)]), ((-1, 0, 0), [(-h, 0, -h), (-h, 0, h), (-h, H, h), (-h, H, -h)])):
    quad(vs, nn, [(0, v1), (r, v1), (r, v0), (0, v0)])
P = np.array(P, '<f4'); N = np.array(N, '<f4'); UV = np.array(UV, '<f4'); I3 = np.array(I, np.int64).reshape(-1, 3)
T3 = P[I3]; fl = (np.cross(T3[:, 1] - T3[:, 0], T3[:, 2] - T3[:, 0]) * N[I3[:, 0]]).sum(1) < 0; I3[fl] = I3[fl][:, [0, 2, 1]]
I = I3.ravel().astype('<u2')
def enc(img, fmt):
    b = io.BytesIO(); img.save(b, fmt, **({'quality': 92} if fmt == 'JPEG' else {})); return b.getvalue()
blobs = [P.tobytes(), N.tobytes(), UV.tobytes(), I.tobytes(), enc(tex, 'JPEG'), enc(nrm, 'PNG'), enc(mr, 'JPEG')]
bvs = []; binb = b''
for bl in blobs:
    bvs.append({'buffer': 0, 'byteOffset': len(binb), 'byteLength': len(bl)}); binb += bl + b'\0' * ((-len(bl)) % 4)
for k in range(3): bvs[k]['target'] = 34962
bvs[3]['target'] = 34963
g = {'asset': {'version': '2.0', 'generator': 'cultic tools/pipeline/tile_platform.py'}, 'scene': 0, 'scenes': [{'nodes': [0]}],
     'nodes': [{'name': 'tile_platform', 'mesh': 0}],
     'meshes': [{'name': 'tile_platform', 'primitives': [{'attributes': {'POSITION': 0, 'NORMAL': 1, 'TEXCOORD_0': 2}, 'indices': 3, 'material': 0}]}],
     'materials': [{'name': 'octagon_tile', 'pbrMetallicRoughness': {'baseColorTexture': {'index': 0}, 'metallicFactor': 0.0, 'roughnessFactor': 1.0,
                    'metallicRoughnessTexture': {'index': 2}}, 'normalTexture': {'index': 1}}],
     'textures': [{'source': 0, 'sampler': 0}, {'source': 1, 'sampler': 0}, {'source': 2, 'sampler': 0}],
     'samplers': [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 10497, 'wrapT': 10497}],
     'images': [{'bufferView': 4, 'mimeType': 'image/jpeg', 'name': 'tile_albedo'}, {'bufferView': 5, 'mimeType': 'image/png', 'name': 'tile_normal'},
                {'bufferView': 6, 'mimeType': 'image/jpeg', 'name': 'tile_rough'}],
     'accessors': [{'bufferView': 0, 'componentType': 5126, 'count': len(P), 'type': 'VEC3', 'min': P.min(0).tolist(), 'max': P.max(0).tolist()},
                   {'bufferView': 1, 'componentType': 5126, 'count': len(P), 'type': 'VEC3'},
                   {'bufferView': 2, 'componentType': 5126, 'count': len(P), 'type': 'VEC2'},
                   {'bufferView': 3, 'componentType': 5123, 'count': len(I), 'type': 'SCALAR'}],
     'bufferViews': bvs, 'buffers': [{'byteLength': len(binb)}]}
js = json.dumps(g, separators=(',', ':')).encode(); js += b' ' * ((-len(js)) % 4)
open(out, 'wb').write(struct.pack('<4sII', b'glTF', 2, 28 + len(js) + len(binb)) + struct.pack('<I4s', len(js), b'JSON') + js + struct.pack('<I4s', len(binb), b'BIN\0') + binb)
print('tris', len(I) // 3, 'size %.2fx%.2fx%.2f m' % (S, H, S), 'texture repeats', r, 'bytes', 28 + len(js) + len(binb))
