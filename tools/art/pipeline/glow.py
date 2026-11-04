# glow.py workdir : amber emissive glass for lantern panes
import numpy as np
from PIL import Image
from scipy import ndimage
from scipy.spatial import cKDTree
W='work'
pm=np.load(f'{W}/posmap.npy');cov=np.load(f'{W}/cov.npy')
D=np.asarray(Image.open(f'{W}/out_diffuse.png')).astype(float);M=np.asarray(Image.open(f'{W}/out_mr.png')).astype(float)
lum=D.mean(2);cz=0.27
r=np.hypot(pm[...,0],pm[...,2]-cz)
mask=cov&(pm[...,2]>-0.05)&(pm[...,1]>0.42)&(pm[...,1]<1.0)&(r>0.2)&(r<0.262)&(lum<27)
mask=ndimage.binary_opening(mask,iterations=1);mask=ndimage.binary_closing(mask,iterations=2)
lab,n=ndimage.label(mask);sizes=ndimage.sum(mask,lab,range(1,n+1));keep=np.isin(lab,1+np.nonzero(sizes>800)[0]);mask=keep
print('pane texels',mask.sum(),'islands',(sizes>800).sum())
# soft edge
dist=ndimage.distance_transform_edt(mask);soft=np.clip(dist/3.0,0,1)
# cylindrical coords for procedural detail
ang=np.arctan2(pm[...,0],pm[...,2]-cz);s=ang*0.235;y=pm[...,1]
rng=np.random.default_rng(7);seeds=np.c_[rng.uniform(-0.8,0.8,1100),rng.uniform(0.4,1.05,1100)]
idx=np.nonzero(mask);q=np.c_[s[idx],y[idx]]
dd,_=cKDTree(seeds*[1,1]).query(q,k=2);edge=dd[:,1]-dd[:,0]
crack=np.exp(-(edge/0.0028)**2)  # thin cell borders
# glow: bright in vertical centre of pane band, falls off to top/bottom
yc=0.71;gy=np.exp(-((y[idx]-yc)/0.17)**2)
# subtle mottling
mot=ndimage.gaussian_filter(rng.standard_normal(mask.shape),6)[idx];mot=(mot-mot.mean())/(mot.std()+1e-9)
base=np.array([214,128,42.]);hot=np.array([255,214,120.])
t=np.clip(0.25+0.75*gy+0.06*mot,0,1)[:,None]
glass=base*(1-t)+hot*t
glass=glass*(1-0.45*crack[:,None])
k=soft[idx][:,None]
D2=D.copy();D2[idx]=D[idx]*(1-k)+glass*k
E=np.zeros_like(D);emis=np.array([255,150,50.])*(0.35+0.65*gy)[:,None]+np.array([0,60,40.])*gy[:,None]**2
emis=emis*(1-0.5*crack[:,None])*(1+0.08*mot[:,None]);E[idx]=np.clip(emis,0,255)*k
M2=M.copy();kk=k[:,0];M2[idx[0],idx[1],1]=M[idx[0],idx[1],1]*(1-kk)+90*kk;M2[idx[0],idx[1],2]=M[idx[0],idx[1],2]*(1-kk)
# dilate emissive into padding so bilinear sampling at chart borders stays clean
Image.fromarray(D2.clip(0,255).astype(np.uint8)).save(f'{W}/glow_diffuse.png')
Image.fromarray(M2.clip(0,255).astype(np.uint8)).save(f'{W}/glow_mr.png')
Image.fromarray(E.clip(0,255).astype(np.uint8)).save(f'{W}/glow_emissive.png')
Image.fromarray((mask*255).astype(np.uint8)).resize((512,512)).save('/tmp/claude-0/-home-claude/7ce1b33a-a892-5d10-b2ef-b07352f1bb43/scratchpad/wl_mask.png')
