# Glass-door display cabinet from a front concept, as separate objects so the doors open and the drawers slide:
# nodes body, door_left / door_right (origin on the hinge line), drawer_left / drawer_right.
# The concept is the wood texture (UV = concept pixels); glass is a separate transparent material.
# Real scale: 2.0 m high, 0.5 m deep; pivot at bottom centre of the back (stands against a wall, front +Z).
# Usage: python3 cabinet.py concept.png out.glb
import sys, os, io, struct, json, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image
from elevation import rect_minus, textures
src, out = sys.argv[1], sys.argv[2]
im = Image.open(src).convert('RGB'); IW, IH = im.size
S = 2.0 / (1500 - 30); CX = (195 + 828) / 2; YB = 1500
ZB = 0.25                                   # everything shifted so the back sits on z=0
X = lambda px: (px - CX) * S
Y = lambda py: (YB - py) * S
uvp = lambda px, py: (px / IW, py / IH)

class Part:
    """Geometry for one node, per material; boxes in concept px, z in metres (body coordinates)."""
    def __init__(self): self.g = {0: [[], [], [], []], 1: [[], [], [], []]}
    def quad(self, mat, vs, n, uvs):
        P, N, U, I = self.g[mat]; b = len(P); P += vs; N += [n] * 4; U += uvs; I += [b, b + 1, b + 2, b, b + 2, b + 3]
    def box(self, r, z0, z1, side=None, top=None, front=None, xform=None):
        """r=(x0,x1,y0,y1) px; z0<z1. front/side/top: px rects to sample instead of the projected front."""
        x0, x1, y0, y1 = r; f = front or r; e = 6
        fx = (lambda px: X(px)) if xform is None else xform[0]; fy = (lambda py: Y(py)) if xform is None else xform[1]
        q = self.quad
        sg = 1 if fx(x0) < fx(x1) else -1      # mirrored door mapping flips which face is on the left
        # front
        q(0, [(fx(x0), fy(y1), z1), (fx(x1), fy(y1), z1), (fx(x1), fy(y0), z1), (fx(x0), fy(y0), z1)], (0, 0, 1),
          [uvp(f[0], f[3]), uvp(f[1], f[3]), uvp(f[1], f[2]), uvp(f[0], f[2])])
        # back
        q(0, [(fx(x1), fy(y1), z0), (fx(x0), fy(y1), z0), (fx(x0), fy(y0), z0), (fx(x1), fy(y0), z0)], (0, 0, -1),
          [uvp(f[1], f[3]), uvp(f[0], f[3]), uvp(f[0], f[2]), uvp(f[1], f[2])])
        t = top or (f[0], f[1], f[2] + e, f[2] + e + 1)
        q(0, [(fx(x0), fy(y0), z1), (fx(x1), fy(y0), z1), (fx(x1), fy(y0), z0), (fx(x0), fy(y0), z0)], (0, 1, 0),
          [uvp(t[0], t[3]), uvp(t[1], t[3]), uvp(t[1], t[2]), uvp(t[0], t[2])])
        b = top or (f[0], f[1], f[3] - e - 1, f[3] - e)
        q(0, [(fx(x0), fy(y1), z0), (fx(x1), fy(y1), z0), (fx(x1), fy(y1), z1), (fx(x0), fy(y1), z1)], (0, -1, 0),
          [uvp(b[0], b[2]), uvp(b[1], b[2]), uvp(b[1], b[3]), uvp(b[0], b[3])])
        sd = side or (f[0] + e, f[0] + e + 1, f[2], f[3])
        q(0, [(fx(x0), fy(y1), z0), (fx(x0), fy(y1), z1), (fx(x0), fy(y0), z1), (fx(x0), fy(y0), z0)], (-sg, 0, 0),
          [uvp(sd[0], sd[3]), uvp(sd[1], sd[3]), uvp(sd[1], sd[2]), uvp(sd[0], sd[2])])
        sd = side or (f[1] - e - 1, f[1] - e, f[2], f[3])
        q(0, [(fx(x1), fy(y1), z1), (fx(x1), fy(y1), z0), (fx(x1), fy(y0), z0), (fx(x1), fy(y0), z1)], (sg, 0, 0),
          [uvp(sd[0], sd[3]), uvp(sd[1], sd[3]), uvp(sd[1], sd[2]), uvp(sd[0], sd[2])])

DARK = (300, 330, 200, 1100)      # plain dark interior planks, for hidden / inner faces
SHELF_TOP = (265, 760, 360, 378)  # shelf top strip
STILE = (200, 218, 150, 1300)     # painted carcass stile left of the hinges, for the outer sides
body = Part()
body.box((175, 852, 30, 140), -0.25 + ZB, 0.26 + ZB, side=(185, 200, 40, 135))       # cornice
body.box((195, 255, 140, 1320), -0.225 + ZB, 0.225 + ZB, side=STILE)                  # left side
body.box((770, 828, 140, 1320), -0.225 + ZB, 0.225 + ZB, side=STILE)                  # right side
body.box((255, 770, 143, 1150), -0.225 + ZB, -0.20 + ZB)                              # back panel (interior art)
for y0, y1 in ((382, 400), (627, 645), (883, 899)):
    body.box((255, 770, y0, y1), -0.20 + ZB, 0.19 + ZB, top=SHELF_TOP)                # shelves
body.box((255, 770, 1130, 1170), -0.20 + ZB, 0.21 + ZB, top=(265, 760, 1105, 1125))  # bottom shelf / counter
DRAWERS = [(275, 497, 1188, 1310), (525, 750, 1188, 1310)]
for rr in rect_minus((255, 770, 1170, 1320), DRAWERS):
    body.box(rr, -0.225 + ZB, 0.22 + ZB, side=DARK)                                   # drawer frame around openings
body.box((275, 750, 1188, 1310), -0.225 + ZB, -0.20 + ZB, front=DARK)                 # back of drawer bays
body.box((172, 858, 1320, 1500), -0.24 + ZB, 0.24 + ZB, side=(180, 200, 1340, 1460))  # plinth
body.box((255, 770, 140, 143), -0.225 + ZB, 0.225 + ZB, front=DARK)                   # top of the interior

drawers = []
for (x0, x1, y0, y1) in DRAWERS:
    d = Part()
    d.box((x0, x1, y0, y1), 0.205 + ZB, 0.235 + ZB, side=DARK)                         # drawer front
    d.box((x0 + 10, x1 - 10, y0 + 8, y1 - 6), -0.19 + ZB, 0.205 + ZB, front=DARK, side=DARK, top=DARK)  # drawer box
    drawers.append(d)

# doors: texture rect in the concept, closed footprint on the carcass, glass panes in texture px
DOOR_TEX = {'left': (42, 220, 85, 1285), 'right': (804, 982, 85, 1285)}
PANES_Y = [(180, 398), (420, 885), (910, 1205)]
GLASS_X = {'left': (85, 190), 'right': (834, 939)}
HANDLE = {'left': (44, 62, 610, 770), 'right': (962, 980, 610, 770)}
DOOR_Y = (128, 1172); THICK = 0.032; ZF = 0.225 + ZB
HINGE = {'left': 232, 'right': 791}; MEET = 511.5
doors = {}
for side in ('left', 'right'):
    tx0, tx1, ty0, ty1 = DOOR_TEX[side]
    gx0 = HINGE[side] if side == 'left' else MEET; gx1 = MEET if side == 'left' else HINGE[side]
    # texture px -> door geometry in body coordinates (left door: free edge = texture x0 lands at the middle)
    if side == 'left':
        fx = lambda px, tx0=tx0, tx1=tx1: X(gx1 - (px - tx0) / (tx1 - tx0) * (gx1 - gx0))
    else:
        fx = lambda px, tx0=tx0, tx1=tx1: X(gx0 + (tx1 - px) / (tx1 - tx0) * (gx1 - gx0))
    fy = lambda py, ty0=ty0, ty1=ty1: Y(DOOR_Y[0] + (py - ty0) / (ty1 - ty0) * (DOOR_Y[1] - DOOR_Y[0]))
    d = Part(); gx = GLASS_X[side]
    panes = [(gx[0], gx[1], a, b) for a, b in PANES_Y]
    for rr in rect_minus((tx0, tx1, ty0, ty1), panes):
        # mirrored mapping flips x order; keep x0<x1 in geometry by swapping via a box over sorted coordinates
        d.box(rr, ZF, ZF + THICK, xform=(fx, fy))
    for (a0, a1, b0, b1) in panes:
        xs = sorted((fx(a0), fx(a1))); zg = ZF + THICK / 2
        for zz, n in ((zg + 0.002, (0, 0, 1)), (zg - 0.002, (0, 0, -1))):
            d.quad(1, [(xs[0], fy(b1), zz), (xs[1], fy(b1), zz), (xs[1], fy(b0), zz), (xs[0], fy(b0), zz)], n,
                   [uvp(a0, b1), uvp(a1, b1), uvp(a1, b0), uvp(a0, b0)])
    h = HANDLE[side]
    d.box(h, ZF + THICK, ZF + THICK + 0.035, xform=(fx, fy))
    doors[side] = (d, X(HINGE[side]))

tex, nrm, mr = textures(im, (0, 0, IW, IH), (1024, 1536))

def pack(nodes):
    """nodes: list of (name, Part, translation). Geometry is shifted by -translation so the node origin is the pivot."""
    blobs = []; acc = []; bvs = []; meshes = []; gnodes = []
    def add(arr, target, comp, typ):
        bvs.append({'buffer': 0, 'byteOffset': 0, 'byteLength': len(arr.tobytes()), 'target': target}); blobs.append(arr.tobytes())
        a = {'bufferView': len(bvs) - 1, 'componentType': comp, 'count': len(arr) if arr.ndim == 2 else arr.size, 'type': typ}
        if typ == 'VEC3' and target == 34962 and not acc_flags.get('n'):
            a['min'] = arr.min(0).tolist(); a['max'] = arr.max(0).tolist()
        acc.append(a); return len(acc) - 1
    for name, part, t in nodes:
        prims = []
        for mat, (P, N, U, I) in part.g.items():
            if not P: continue
            P = np.array(P, '<f4') - np.array(t, '<f4'); N = np.array(N, '<f4'); U = np.array(U, '<f4')
            I3 = np.array(I, np.int64).reshape(-1, 3); T = P[I3]
            fl = (np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0]) * N[I3[:, 0]]).sum(1) < 0; I3[fl] = I3[fl][:, [0, 2, 1]]
            acc_flags['n'] = False; ip = add(P, 34962, 5126, 'VEC3')
            acc_flags['n'] = True; inn = add(N, 34962, 5126, 'VEC3'); acc_flags['n'] = False
            iu = add(U, 34962, 5126, 'VEC2'); ii = add(I3.ravel().astype('<u2'), 34963, 5123, 'SCALAR')
            prims.append({'attributes': {'POSITION': ip, 'NORMAL': inn, 'TEXCOORD_0': iu}, 'indices': ii, 'material': mat})
        meshes.append({'name': name, 'primitives': prims})
        gnodes.append({'name': name, 'mesh': len(meshes) - 1, 'translation': [float(v) for v in t]})
    def enc(img, fmt):
        b = io.BytesIO(); img.save(b, fmt, **({'quality': 90} if fmt == 'JPEG' else {})); return b.getvalue()
    for data in (enc(tex, 'JPEG'), enc(nrm, 'PNG'), enc(mr, 'JPEG')):
        bvs.append({'buffer': 0, 'byteOffset': 0, 'byteLength': len(data)}); blobs.append(data)
    binb = b''
    for bv, bl in zip(bvs, blobs):
        bv['byteOffset'] = len(binb); binb += bl + b'\0' * ((-len(bl)) % 4)
    nimg = len(bvs) - 3
    g = {'asset': {'version': '2.0', 'generator': 'cultic tools/pipeline/cabinet.py'}, 'scene': 0,
         'scenes': [{'nodes': [len(gnodes)]}],
         'nodes': gnodes + [{'name': 'cabinet', 'children': list(range(len(gnodes)))}],
         'meshes': meshes,
         'materials': [{'name': 'cabinet_wood', 'pbrMetallicRoughness': {'baseColorTexture': {'index': 0}, 'metallicFactor': 0.0, 'roughnessFactor': 1.0,
                        'metallicRoughnessTexture': {'index': 2}}, 'normalTexture': {'index': 1}},
                       {'name': 'cabinet_glass', 'alphaMode': 'BLEND', 'doubleSided': True,
                        'pbrMetallicRoughness': {'baseColorFactor': [0.30, 0.27, 0.21, 0.16], 'metallicFactor': 0.0, 'roughnessFactor': 0.05}}],
         'textures': [{'source': 0, 'sampler': 0}, {'source': 1, 'sampler': 0}, {'source': 2, 'sampler': 0}],
         'samplers': [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 33071, 'wrapT': 33071}],
         'images': [{'bufferView': nimg, 'mimeType': 'image/jpeg', 'name': 'cabinet_albedo'}, {'bufferView': nimg + 1, 'mimeType': 'image/png', 'name': 'cabinet_normal'},
                    {'bufferView': nimg + 2, 'mimeType': 'image/jpeg', 'name': 'cabinet_metal_rough'}],
         'accessors': acc, 'bufferViews': bvs, 'buffers': [{'byteLength': len(binb)}]}
    js = json.dumps(g, separators=(',', ':')).encode(); js += b' ' * ((-len(js)) % 4)
    open(out, 'wb').write(struct.pack('<4sII', b'glTF', 2, 28 + len(js) + len(binb)) + struct.pack('<I4s', len(js), b'JSON') + js
                          + struct.pack('<I4s', len(binb), b'BIN\0') + binb)
acc_flags = {}
nodes = [('body', body, (0, 0, 0)),
         ('door_left', doors['left'][0], (doors['left'][1], 0, ZF)),
         ('door_right', doors['right'][0], (doors['right'][1], 0, ZF)),
         ('drawer_left', drawers[0], (0, 0, 0)), ('drawer_right', drawers[1], (0, 0, 0))]
pack(nodes)
tris = sum(len(p.g[m][3]) // 3 for _, p, _ in nodes for m in p.g)
allP = np.concatenate([np.array(p.g[0][0]) for _, p, _ in nodes])
print('tris', tris, 'size %.2fx%.2fx%.2f m' % tuple(allP.max(0) - allP.min(0)))
