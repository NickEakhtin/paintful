# Usage: node dumpuv.mjs model.glb && python3 emclean.py emissive.png out.png min_radius
# Keep emissive only on triangles far from the vertical axis (the lanterns); Rodin also lit the hoop top.
import sys,numpy as np
from PIL import Image, ImageDraw
from PIL import ImageFilter
emf,out,rmin=sys.argv[1],sys.argv[2],float(sys.argv[3])
P=np.fromfile('d_pos.bin',np.float32).reshape(-1,3);UV=np.fromfile('d_uv.bin',np.float32).reshape(-1,2);I=np.fromfile('d_idx.bin',np.uint32).reshape(-1,3)
c=(P.min(0)+P.max(0))/2;C=P[I].mean(1);rc=np.hypot(C[:,0]-c[0],C[:,2]-c[2])
E=np.asarray(Image.open(emf).convert('RGB')).astype(float);S=E.shape[0]
own=Image.new('I',(S,S),-1);d=ImageDraw.Draw(own)
for t,(a,b,cc) in enumerate(I): d.polygon([(UV[k,0]*S,UV[k,1]*S) for k in (a,b,cc)],fill=t)
own=np.array(own);bad=(own>=0)&(rc[np.maximum(own,0)]<rmin)
bad=np.asarray(Image.fromarray((bad*255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5)))>0   # cover bilinear bleed at chart borders
E[bad]=0;Image.fromarray(E.astype(np.uint8)).save(out);print('cleared texels',bad.sum(),'lit left',(E.max(2)>30).sum())
