# Usage: python3 age_brass.py basecolor.png metal_rough.png out_basecolor.jpg out_metal_rough.jpg seed [emissive.png]
# Age the brass: darken/redden metal pixels toward the concept's bronze, add patchy wear, lower metal roughness.
import sys,numpy as np
from PIL import Image
bcf,mrf,obc,omr,seed=sys.argv[1:6]
# optional 7th arg: emissive map; glowing texels (glass, flames) are left untouched
keep=None
if len(sys.argv)>6:
    keep=np.asarray(Image.open(sys.argv[6]).convert('RGB')).max(2)>30
bc=np.asarray(Image.open(bcf).convert('RGB')).astype(float);mr=np.asarray(Image.open(mrf).convert('RGB')).astype(float)
w=np.clip((mr[...,2]-60)/140,0,1)[...,None]          # soft metal mask from metallic channel
H,W=bc.shape[:2];rng=np.random.default_rng(int(seed))
def noise(n):
    return np.asarray(Image.fromarray((rng.random((n,n))*255).astype(np.uint8)).resize((W,H),Image.BICUBIC)).astype(float)/255
nz=0.6*noise(24)+0.4*noise(96)
patina=np.clip((nz-0.55)*4,0,1)[...,None]               # dark worn patches
# per-channel gains that bring the mean metal / paint colour to the concept palette
BRONZE=np.array([137,93,53]);PAINT=np.array([43,40,32])
mw=w[...,0]>0.5
free=np.ones(mw.shape,bool) if keep is None else ~keep
gain=BRONZE/np.maximum(bc[mw&free].mean(0),1)
paint_gain=PAINT/np.maximum(bc[~mw&free].mean(0),1)
bronze=bc*gain*(0.85+0.3*nz[...,None])
bronze=bronze*(1-0.55*patina)+np.array([40,36,28])*0.55*patina
paint=bc*paint_gain  # concept paint is near-black green
out=paint*(1-w)+bronze*w
if keep is not None: out[keep]=bc[keep]
Image.fromarray(np.clip(out,0,255).astype(np.uint8)).save(obc,quality=90)
r=mr[...,1]; r_new=r*(1-w[...,0])+(110+80*patina[...,0]+20*nz)*w[...,0]  # metal ~0.45-0.75 roughness
m=mr.copy();m[...,1]=r_new;m[...,2]=mr[...,2]*(1-0.5*patina[...,0])
if keep is not None: m[keep]=mr[keep]
Image.fromarray(np.clip(m,0,255).astype(np.uint8)).save(omr,quality=92)
