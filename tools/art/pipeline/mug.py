# Low-poly porcelain mug (960 tris) fitted to the Hyper3D Rodin original (models/originals/coffee_mug_original.glb).
# Usage: python3 mug.py out.glb [roughness]
import numpy as np, struct, json, sys
N=24  # lathe segments
cz=0.265
# profile (r, y), outer bottom centre -> rim -> inner floor centre
prof=[(0,0),(0.40,0),(0.47,0.03),(0.53,0.11),(0.60,0.30),(0.66,0.60),(0.689,1.0),(0.693,1.38),
      (0.675,1.46),(0.635,1.472),(0.595,1.455),(0.583,1.38),(0.565,0.95),(0.53,0.60),(0.48,0.35),
      (0.40,0.20),(0.25,0.135),(0,0.12)]
hard={1}  # crease between flat bottom and side wall
pr=np.array(prof,float)
def seg_n(a,b):
    d=b-a; n=np.array([d[1],-d[0]]); return n/np.linalg.norm(n)   # outward for this ordering
# build profile vertex list with normals (split at hard points)
pv=[]  # (r,y,nr,ny,v)
L=np.concatenate([[0],np.cumsum(np.linalg.norm(np.diff(pr,axis=0),axis=1))]);L/=L[-1]
for i,p in enumerate(pr):
    ns=[]
    if i>0: ns.append(seg_n(pr[i-1],p))
    if i<len(pr)-1: ns.append(seg_n(p,pr[i+1]))
    if i in hard:
        pv.append((p,ns[0],L[i],'end')); pv.append((p,ns[1],L[i],'start'))
    else:
        n=sum(ns); n/=np.linalg.norm(n)
        if p[0]==0: n=np.array([0.0,np.sign(n[1])])
        pv.append((p,n,L[i],''))
P=[];Nn=[];UV=[];I=[]
cols=N+1
rows=[]
for (p,n,v,tag) in pv:
    base=len(P);rows.append((base,tag))
    for k in range(cols):
        a=2*np.pi*k/N;c,s=np.cos(a),np.sin(a)
        P.append((p[0]*c,p[1],p[0]*s));Nn.append((n[0]*c,n[1],n[0]*s));UV.append((k/N,v))
for ri in range(len(rows)-1):
    (a,ta),(b,tb)=rows[ri],rows[ri+1]
    if ta=='end' and tb=='start': continue   # duplicated crease ring, no faces between
    for k in range(N):
        i0,i1,j0,j1=a+k,a+k+1,b+k,b+k+1
        I+= [i0,j0,i1, i1,j0,j1]
# drop degenerate triangles at the axis (r=0 rings)
P=np.array(P);Nn=np.array(Nn);UV=np.array(UV)
I=np.array(I).reshape(-1,3)
area=np.linalg.norm(np.cross(P[I[:,1]]-P[I[:,0]],P[I[:,2]]-P[I[:,0]]),axis=1)
I=I[area>1e-9]
# --- handle: elliptical tube along centreline in the x=0 plane (y, z relative to body axis)
cl=np.array([(1.18,-0.38),(1.205,-0.55),(1.20,-0.69),(1.13,-0.80),(1.01,-0.86),(0.875,-0.865),(0.755,-0.84),
             (0.655,-0.79),(0.575,-0.725),(0.505,-0.655),(0.445,-0.585),(0.395,-0.505),(0.35,-0.30)])
cl[:,1]-=cz
def catmull(pts,m):
    pts=np.vstack([pts[0],pts,pts[-1]]);out=[]
    seg=len(pts)-3
    for t in np.linspace(0,seg,m+1):
        i=min(int(t),seg-1);u=t-i;p0,p1,p2,p3=pts[i:i+4]
        out.append(0.5*((2*p1)+(-p0+p2)*u+(2*p0-5*p1+4*p2-p3)*u*u+(-p0+3*p1-3*p2+p3)*u**3))
    return np.array(out)
M,S=12,8;ax,an=0.107,0.088
path=catmull(cl,M)
hb=len(P);HP=[];HN=[];HUV=[]
for i,(py,pz) in enumerate(path):
    t=path[min(i+1,M)]-path[max(i-1,0)];t/=np.linalg.norm(t)
    nrm=np.array([-t[1],t[0]])  # in-plane normal (y,z)
    for s in range(S+1):
        a=2*np.pi*s/S;cx,sn=np.cos(a),np.sin(a)
        HP.append((ax*cx,py+an*sn*nrm[0],pz+an*sn*nrm[1]))
        g=np.array([cx/ax,sn/an]);g/=np.linalg.norm(g)
        HN.append((g[0],g[1]*nrm[0],g[1]*nrm[1]));HUV.append((s/S,i/M))
HI=[]
for i in range(M):
    for s in range(S):
        a=hb+i*(S+1)+s;b=a+S+1
        HI+=[a,b,a+1, a+1,b,b+1]
P=np.vstack([P,HP]);Nn=np.vstack([Nn,HN]);UV=np.vstack([UV,HUV]);I=np.vstack([I,np.array(HI).reshape(-1,3)])
# shift so origin is bottom centre of the body (body axis was at z=cz)
P[:,2]+=0  # body built around origin already; handle shifted by -cz above
# make winding agree with normals
fn=np.cross(P[I[:,1]]-P[I[:,0]],P[I[:,2]]-P[I[:,0]]);vn=Nn[I].sum(1)
flip=(fn*vn).sum(1)<0;I[flip]=I[flip][:,[0,2,1]]
print('verts',len(P),'tris',len(I),'flipped',flip.sum())
# --- write GLB
P=P.astype('<f4');Nn=(Nn/np.linalg.norm(Nn,axis=1,keepdims=True)).astype('<f4');UV=UV.astype('<f4');Ix=I.astype('<u2').ravel()
blobs=[P.tobytes(),Nn.tobytes(),UV.tobytes(),Ix.tobytes()];bvs=[];off=0;bin_=b''
for bl in blobs:
    bvs.append({'buffer':0,'byteOffset':off,'byteLength':len(bl)});bin_+=bl+b'\0'*((-len(bl))%4);off=len(bin_)
bvs[3]['target']=34963
for k in range(3): bvs[k]['target']=34962
acc=[{'bufferView':0,'componentType':5126,'count':len(P),'type':'VEC3','min':P.min(0).tolist(),'max':P.max(0).tolist()},
     {'bufferView':1,'componentType':5126,'count':len(P),'type':'VEC3'},
     {'bufferView':2,'componentType':5126,'count':len(P),'type':'VEC2'},
     {'bufferView':3,'componentType':5123,'count':len(Ix),'type':'SCALAR'}]
rough=float(sys.argv[2]) if len(sys.argv)>2 else 0.1
g={'asset':{'version':'2.0','generator':'procedural mug fitted to Hyper3D Rodin 6e23a9fa'},'scene':0,'scenes':[{'nodes':[0]}],
   'nodes':[{'name':'coffee_mug','mesh':0}],
   'meshes':[{'name':'coffee_mug','primitives':[{'attributes':{'POSITION':0,'NORMAL':1,'TEXCOORD_0':2},'indices':3,'material':0}]}],
   'materials':[{'name':'porcelain','pbrMetallicRoughness':{'baseColorFactor':[0.93,0.93,0.91,1],'metallicFactor':0.0,'roughnessFactor':rough}}],
   'accessors':acc,'bufferViews':bvs,'buffers':[{'byteLength':len(bin_)}]}
js=json.dumps(g,separators=(',',':')).encode();js+=b' '*((-len(js))%4)
out=struct.pack('<4sII',b'glTF',2,12+8+len(js)+8+len(bin_))+struct.pack('<I4s',len(js),b'JSON')+js+struct.pack('<I4s',len(bin_),b'BIN\0')+bin_
open(sys.argv[1],'wb').write(out);print('bytes',len(out))
