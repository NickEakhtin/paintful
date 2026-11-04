# flint.py workdir : replace tabletop region with polished flint
import numpy as np,sys
from PIL import Image
from scipy import ndimage
W=sys.argv[1] if len(sys.argv)>1 else 'work';R=2048
pm=np.load(f'{W}/posmap.npy');nm=np.load(f'{W}/nrmmap.npy');cov=np.load(f'{W}/cov.npy')
D=np.asarray(Image.open(f'{W}/out_diffuse.png')).astype(float);M=np.asarray(Image.open(f'{W}/out_mr.png')).astype(float);Nn=np.asarray(Image.open(f'{W}/out_normal.png')).astype(float)
# tangent map
P=np.fromfile(f'{W}/low_pos.f32',np.float32).reshape(-1,3);UV=np.fromfile(f'{W}/low_uv.f32',np.float32).reshape(-1,2);T4=np.fromfile(f'{W}/low_tan.f32',np.float32).reshape(-1,4)
I=np.fromfile(f'{W}/low_idx.u32',np.uint32).reshape(-1,3);tm=np.zeros((R,R,4),np.float32)
for f in I:
    x=UV[f,0]*R;y=UV[f,1]*R
    x0,x1=max(0,int(np.floor(x.min()))-1),min(R-1,int(np.ceil(x.max()))+1);y0,y1=max(0,int(np.floor(y.min()))-1),min(R-1,int(np.ceil(y.max()))+1)
    den=(y[1]-y[2])*(x[0]-x[2])+(x[2]-x[1])*(y[0]-y[2])
    if abs(den)<1e-12: continue
    gx,gy=np.meshgrid(np.arange(x0,x1+1)+.5,np.arange(y0,y1+1)+.5)
    w0=((y[1]-y[2])*(gx-x[2])+(x[2]-x[1])*(gy-y[2]))/den;w1=((y[2]-y[0])*(gx-x[2])+(x[0]-x[2])*(gy-y[2]))/den;w2=1-w0-w1
    ins=(w0>=-0.02)&(w1>=-0.02)&(w2>=-0.02)
    if not ins.any(): continue
    w=np.stack([w0[ins],w1[ins],w2[ins]],1);ys,xs=np.nonzero(ins);tm[ys+y0,xs+x0,:3]=w@T4[f,:3];tm[ys+y0,xs+x0,3]=T4[f[0],3]
# region: top, upward, non-metal, inside frame
top=cov&(nm[...,1]>0.9)&(pm[...,1]>0.55)
stone=top&(M[...,2]<40)
xs_=np.abs(pm[...,0][stone]);zs_=np.abs(pm[...,2][stone])
xl,zl=np.percentile(xs_,99.5),np.percentile(zs_,99.5)
reg=top&(np.abs(pm[...,0])<xl)&(np.abs(pm[...,2])<zl)
reg=ndimage.binary_closing(reg,iterations=3)&top
print('region texels',reg.sum(),'extent',round(xl,3),round(zl,3))
# --- procedural flint in world xz
rng=np.random.default_rng(3)
def vnoise(x,z,scale,seed):
    g=np.random.default_rng(seed).standard_normal((300,300))
    g=ndimage.gaussian_filter(g,1.0)
    u=(x*scale)%299;v=(z*scale)%299
    return ndimage.map_coordinates(g,[v,u],order=3,mode='wrap')
idx=np.nonzero(reg);x=pm[...,0][idx]+1.3;z=pm[...,2][idx]+1.1
def fbm(x,z,s,seed,o=5):
    t=0;a=1;n=0
    for i in range(o): t+=a*vnoise(x,z,s*2**i,seed+i);n+=a;a*=0.5
    return t/n
wx=fbm(x,z,6,10,4)*0.12;wz=fbm(x,z,6,20,4)*0.12
cloud=fbm(x+wx,z+wz,4,30,6);cloud=(cloud-cloud.mean())/cloud.std()
blue=np.clip(fbm(x-wz,z+wx,2.5,40,5)*3.5+0.1,0,1)
brown=np.clip(fbm(x+wz*1.5,z,3,50,4)*2.5-0.4,0,1)
speck=(vnoise(x,z,140,60)>2.6).astype(float)*0.6
base=np.array([34,32,31.])
col=base*(1+0.38*cloud[:,None])
col=col*(1-blue[:,None]*0.6)+np.array([92,96,104.])*blue[:,None]*0.6
col=col*(1-brown[:,None]*0.45)+np.array([96,70,46.])*brown[:,None]*0.45
col=col+speck[:,None]*np.array([40,38,34.])
# conchoidal ripples: concentric rings around a few centres
cent=np.array([[-0.55,-0.2],[0.35,0.25],[0.75,-0.3],[-0.1,0.35]]);hgt=np.zeros(len(x))
px,pz=pm[...,0][idx],pm[...,2][idx]
for (cx,cz),r0 in zip(cent,[0.5,0.45,0.35,0.3]):
    d=np.hypot(px-cx,pz-cz);hgt+=np.exp(-(d/r0)**2)*np.sin(d*95+cloud*0.8)*0.0005
# subtle polish waviness
hgt+=fbm(x,z,8,70,3)*0.0006
# gradient in world (posmap-space) -> finite difference via image grid
Hm=np.zeros((R,R));Hm[idx]=hgt;Hm=ndimage.gaussian_filter(Hm,0.7)
# world slope from texel neighbours: d(H)/d(world) using posmap differences
dHx=np.zeros((R,R));dHz=np.zeros((R,R))
gyH,gxH=np.gradient(Hm);gyX,gxX=np.gradient(pm[...,0]);gyZ,gxZ=np.gradient(pm[...,2])
det=gxX*gyZ-gxZ*gyX;ok=np.abs(det)>1e-12
dHx[ok]=(gxH*gyZ-gyH*gxZ)[ok]/det[ok];dHz[ok]=(gyH*gxX-gxH*gyX)[ok]/det[ok]
nw=np.dstack([-dHx,np.ones((R,R)),-dHz]);nw/=np.linalg.norm(nw,axis=2,keepdims=True)
T=tm[...,:3];T=T/(np.linalg.norm(T,axis=2,keepdims=True)+1e-12);Nup=nm/(np.linalg.norm(nm,axis=2,keepdims=True)+1e-12)
Bv=np.cross(Nup,T)*tm[...,3:4]
ts=np.dstack([(nw*T).sum(2),(nw*Bv).sum(2),(nw*Nup).sum(2)]);ts/=np.linalg.norm(ts,axis=2,keepdims=True)+1e-12
# feather edge
dist=ndimage.distance_transform_edt(reg);k=np.clip(dist/2.5,0,1)[idx][:,None]
D2=D.copy();D2[idx]=D[idx]*(1-k)+col*k
N2=Nn.copy();N2[idx]=Nn[idx]*(1-k)+((ts[idx]*0.5+0.5)*255)*k
rough=np.clip(0.15+0.05*cloud+0.06*blue-0.03*brown,0.08,0.28)*255
M2=M.copy();kk=k[:,0];M2[idx[0],idx[1],1]=M[idx[0],idx[1],1]*(1-kk)+rough*kk;M2[idx[0],idx[1],2]=M[idx[0],idx[1],2]*(1-kk)
for n_,a in [('diffuse',D2),('mr',M2),('normal',N2)]: Image.fromarray(a.clip(0,255).astype(np.uint8)).save(f'{W}/glow_{n_}.png')
np.save(f'{W}/flint_mask.npy',reg)
