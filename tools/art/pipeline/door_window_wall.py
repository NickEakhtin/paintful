# Full room wall with a doorway and a window, built from a front-elevation concept (real scale: door 2.1 m high).
# Usage: python3 door_window_wall.py concept.png out.glb
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image
from elevation import rect_minus, textures, Mesh
src, out = sys.argv[1], sys.argv[2]
im = Image.open(src).convert('RGB')
X0, X1, Y0, Y1 = 41, 1957, 52, 647                  # wall bounds in concept px (Y1 = floor)
DOOR = (362, 585, 257, 647); WINDOW = (1041, 1685, 191, 463)
S = 2.1 / (DOOR[3] - DOOR[2])                       # door opening = 2.1 m
holes = [DOOR, WINDOW]
door_gap = [(325, 620, 0, 9999)]                    # wainscot / rails stop at the door casing
parts = [  # (rect, half thickness, cut by)
    ((100, 1900, 82, 470), 0.08, holes),            # wallpaper field
    ((100, 1900, 470, 647), 0.08, holes),           # wall core behind the wainscot
    ((100, 1900, 492, 612), 0.095, door_gap),       # wainscot field (panels in the texture)
    ((100, 1900, 470, 492), 0.11, door_gap),        # chair rail
    ((100, 1900, 612, 647), 0.105, door_gap),       # baseboard
    ((41, 100, 82, 647), 0.12, []),                 # left pilaster
    ((1900, 1957, 82, 647), 0.12, []),              # right pilaster
    ((41, 1957, 52, 82), 0.14, []),                 # cornice
    ((325, 362, 218, 647), 0.11, []),               # door jamb left
    ((585, 620, 218, 647), 0.11, []),               # door jamb right
    ((312, 632, 205, 245), 0.115, []),              # door header
    ((305, 638, 192, 205), 0.125, []),              # door header cap
    ((457, 489, 178, 226), 0.15, []),               # diamond ornament
    ((1005, 1041, 178, 463), 0.11, []),             # window jamb left
    ((1685, 1725, 178, 463), 0.11, []),             # window jamb right
    ((1003, 1730, 150, 178), 0.115, []),            # window head
    ((995, 1740, 136, 150), 0.125, []),             # window head cap
    ((997, 1735, 463, 482), 0.13, []),              # window sill
]
crop = (X0 - 6, Y0 - 6, X1 + 6, Y1 + 4)
tex, nrm, mr = textures(im, crop, (4096, 1024))
m = Mesh(crop, S, (X0 + X1) / 2, Y1)
for r, h, cut in parts:
    for rr in rect_minus(r, cut):
        m.box(rr, h)
tris, size = m.write(out, 'wall_door_window', tex, nrm, mr)
print('tris', tris, 'size %.2fx%.2fx%.2f m' % tuple(size))
