# posmap.py workdir R -> work/posmap.f32 (R,R,3), work/nrmmap.f32
import sys,numpy as np
W,R=sys.argv[1],int(sys.argv[2])
P=np.fromfile(f'{W}/low_pos.f32',np.float32).reshape(-1,3);N=np.fromfile(f'{W}/low_nrm.f32',np.float32).reshape(-1,3)
UV=np.fromfile(f'{W}/low_uv.f32',np.float32).reshape(-1,2);I=np.fromfile(f'{W}/low_idx.u32',np.uint32).reshape(-1,3)
pm=np.zeros((R,R,3),np.float32);nm=np.zeros((R,R,3),np.float32);cov=np.zeros((R,R),bool)
for f in I:
    x=UV[f,0]*R;y=UV[f,1]*R
    x0,x1=max(0,int(np.floor(x.min()))-1),min(R-1,int(np.ceil(x.max()))+1);y0,y1=max(0,int(np.floor(y.min()))-1),min(R-1,int(np.ceil(y.max()))+1)
    den=(y[1]-y[2])*(x[0]-x[2])+(x[2]-x[1])*(y[0]-y[2])
    if abs(den)<1e-12: continue
    gx,gy=np.meshgrid(np.arange(x0,x1+1)+.5,np.arange(y0,y1+1)+.5)
    w0=((y[1]-y[2])*(gx-x[2])+(x[2]-x[1])*(gy-y[2]))/den;w1=((y[2]-y[0])*(gx-x[2])+(x[0]-x[2])*(gy-y[2]))/den;w2=1-w0-w1
    ins=(w0>=-0.02)&(w1>=-0.02)&(w2>=-0.02)
    if not ins.any(): continue
    w=np.stack([w0[ins],w1[ins],w2[ins]],1)
    ys,xs=np.nonzero(ins);ys+=y0;xs+=x0
    pm[ys,xs]=w@P[f];nm[ys,xs]=w@N[f];cov[ys,xs]=True
np.save(f'{W}/posmap.npy',pm);np.save(f'{W}/nrmmap.npy',nm);np.save(f'{W}/cov.npy',cov)
print('cov',cov.mean())
