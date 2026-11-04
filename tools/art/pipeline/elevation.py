# Shared builder for props made from a front-elevation concept: boxes in concept-pixel coordinates (optionally with
# rectangular holes cut through), the concept as albedo on the front (and mirrored on the back), a normal map from the
# image detail and a roughness map. Used by door_window_wall.py.
import io, struct, json, numpy as np
from PIL import Image, ImageFilter

def rect_minus(r, holes):
    """Split rect (x0, x1, y0, y1) into rects that avoid all holes (grid split, merged into horizontal runs)."""
    x0, x1, y0, y1 = r
    hs = [(max(h[0], x0), min(h[1], x1), max(h[2], y0), min(h[3], y1)) for h in holes]
    hs = [h for h in hs if h[0] < h[1] and h[2] < h[3]]
    xs = sorted({x0, x1, *[v for h in hs for v in h[:2]]}); ys = sorted({y0, y1, *[v for h in hs for v in h[2:]]})
    out = []
    for ya, yb in zip(ys[:-1], ys[1:]):
        run = None
        for xa, xb in zip(xs[:-1], xs[1:]):
            cx, cy = (xa + xb) / 2, (ya + yb) / 2
            inside = any(h[0] <= cx <= h[1] and h[2] <= cy <= h[3] for h in hs)
            if not inside:
                run = (run[0], xb) if run else (xa, xb)
            elif run:
                out.append((run[0], run[1], ya, yb)); run = None
        if run: out.append((run[0], run[1], ya, yb))
    return out

def textures(im, crop, size, normal_strength=4.0, blur=12):
    tex = im.crop(crop).resize(size, Image.LANCZOS)
    g = np.asarray(tex.convert('L')).astype(float) / 255
    g = g - np.asarray(Image.fromarray((g * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(blur))).astype(float) / 255
    g = np.asarray(Image.fromarray(np.clip(g * 255 + 128, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1))).astype(float) / 255
    dx = (np.roll(g, -1, 1) - np.roll(g, 1, 1)) * normal_strength
    dy = (np.roll(g, -1, 0) - np.roll(g, 1, 0)) * normal_strength
    n = np.dstack([-dx, dy, np.ones_like(g)]); n /= np.linalg.norm(n, axis=2, keepdims=True)
    nrm = Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8))
    a = np.asarray(tex).astype(float)
    cop = np.clip((a[..., 0] - a[..., 2] - 25) / 40, 0, 1)        # worn copper edges a bit glossier
    mr = np.zeros(a.shape, np.uint8); mr[..., 1] = (215 - 75 * cop).astype(np.uint8)
    return tex, nrm, Image.fromarray(mr)

class Mesh:
    def __init__(self, crop, scale, cx, ybase):
        self.crop, self.s, self.cx, self.yb = crop, scale, cx, ybase
        self.P, self.N, self.UV, self.I = [], [], [], []
    def uv(self, px, py):
        c = self.crop; return ((px - c[0]) / (c[2] - c[0]), (py - c[1]) / (c[3] - c[1]))
    def X(self, px): return (px - self.cx) * self.s
    def Y(self, py): return (self.yb - py) * self.s
    def quad(self, vs, nn, uvs):
        b = len(self.P); self.P += vs; self.N += [nn] * 4; self.UV += uvs; self.I += [b, b + 1, b + 2, b, b + 2, b + 3]
    def box(self, r, h, back=True, e=2):
        """Box over pixel rect r=(x0,x1,y0,y1), front at z=+h, back at z=-h (or z=0 when back=False)."""
        x0, x1, y0, y1 = r; X, Y, uv = self.X, self.Y, self.uv; zb = -h if back else 0.0
        self.quad([(X(x0), Y(y1), h), (X(x1), Y(y1), h), (X(x1), Y(y0), h), (X(x0), Y(y0), h)], (0, 0, 1),
                  [uv(x0, y1), uv(x1, y1), uv(x1, y0), uv(x0, y0)])
        if back:
            self.quad([(X(x1), Y(y1), zb), (X(x0), Y(y1), zb), (X(x0), Y(y0), zb), (X(x1), Y(y0), zb)], (0, 0, -1),
                      [uv(x1, y1), uv(x0, y1), uv(x0, y0), uv(x1, y0)])
        self.quad([(X(x0), Y(y0), h), (X(x1), Y(y0), h), (X(x1), Y(y0), zb), (X(x0), Y(y0), zb)], (0, 1, 0),
                  [uv(x0, y0 + e), uv(x1, y0 + e), uv(x1, y0 + e), uv(x0, y0 + e)])
        self.quad([(X(x0), Y(y1), zb), (X(x1), Y(y1), zb), (X(x1), Y(y1), h), (X(x0), Y(y1), h)], (0, -1, 0),
                  [uv(x0, y1 - e), uv(x1, y1 - e), uv(x1, y1 - e), uv(x0, y1 - e)])
        self.quad([(X(x0), Y(y1), zb), (X(x0), Y(y1), h), (X(x0), Y(y0), h), (X(x0), Y(y0), zb)], (-1, 0, 0),
                  [uv(x0 + e, y1), uv(x0 + e, y1), uv(x0 + e, y0), uv(x0 + e, y0)])
        self.quad([(X(x1), Y(y1), h), (X(x1), Y(y1), zb), (X(x1), Y(y0), zb), (X(x1), Y(y0), h)], (1, 0, 0),
                  [uv(x1 - e, y1), uv(x1 - e, y1), uv(x1 - e, y0), uv(x1 - e, y0)])
    def write(self, out, name, tex, nrm, mr):
        P = np.array(self.P, '<f4'); N = np.array(self.N, '<f4'); UV = np.array(self.UV, '<f4')
        I3 = np.array(self.I, np.int64).reshape(-1, 3)
        T = P[I3]; fn = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0]); flip = (fn * N[I3[:, 0]]).sum(1) < 0
        I3[flip] = I3[flip][:, [0, 2, 1]]
        big = len(P) > 65535; I = I3.ravel().astype('<u4' if big else '<u2')
        def enc(img, fmt):
            b = io.BytesIO(); img.save(b, fmt, **({'quality': 90} if fmt == 'JPEG' else {})); return b.getvalue()
        blobs = [P.tobytes(), N.tobytes(), UV.tobytes(), I.tobytes(), enc(tex, 'JPEG'), enc(nrm, 'PNG'), enc(mr, 'JPEG')]
        bvs = []; binb = b''
        for bl in blobs:
            bvs.append({'buffer': 0, 'byteOffset': len(binb), 'byteLength': len(bl)}); binb += bl + b'\0' * ((-len(bl)) % 4)
        for k in range(3): bvs[k]['target'] = 34962
        bvs[3]['target'] = 34963
        g = {'asset': {'version': '2.0', 'generator': 'cultic tools/pipeline/elevation.py'}, 'scene': 0, 'scenes': [{'nodes': [0]}],
             'nodes': [{'name': name, 'mesh': 0}],
             'meshes': [{'name': name, 'primitives': [{'attributes': {'POSITION': 0, 'NORMAL': 1, 'TEXCOORD_0': 2}, 'indices': 3, 'material': 0}]}],
             'materials': [{'name': name, 'pbrMetallicRoughness': {'baseColorTexture': {'index': 0}, 'metallicFactor': 0.0, 'roughnessFactor': 1.0,
                            'metallicRoughnessTexture': {'index': 2}}, 'normalTexture': {'index': 1}}],
             'textures': [{'source': 0, 'sampler': 0}, {'source': 1, 'sampler': 0}, {'source': 2, 'sampler': 0}],
             'samplers': [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 33071, 'wrapT': 33071}],
             'images': [{'bufferView': 4, 'mimeType': 'image/jpeg', 'name': name + '_albedo'}, {'bufferView': 5, 'mimeType': 'image/png', 'name': name + '_normal'},
                        {'bufferView': 6, 'mimeType': 'image/jpeg', 'name': name + '_metal_rough'}],
             'accessors': [{'bufferView': 0, 'componentType': 5126, 'count': len(P), 'type': 'VEC3', 'min': P.min(0).tolist(), 'max': P.max(0).tolist()},
                           {'bufferView': 1, 'componentType': 5126, 'count': len(P), 'type': 'VEC3'},
                           {'bufferView': 2, 'componentType': 5126, 'count': len(P), 'type': 'VEC2'},
                           {'bufferView': 3, 'componentType': 5125 if big else 5123, 'count': len(I), 'type': 'SCALAR'}],
             'bufferViews': bvs, 'buffers': [{'byteLength': len(binb)}]}
        js = json.dumps(g, separators=(',', ':')).encode(); js += b' ' * ((-len(js)) % 4)
        open(out, 'wb').write(struct.pack('<4sII', b'glTF', 2, 28 + len(js) + len(binb)) + struct.pack('<I4s', len(js), b'JSON') + js
                              + struct.pack('<I4s', len(binb), b'BIN\0') + binb)
        return len(I) // 3, P.max(0) - P.min(0)
