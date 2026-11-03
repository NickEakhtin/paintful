# scene_top.py project out.png : orthographic top-down per-pixel textured render
import json,struct,io,sys,re,numpy as np
from PIL import Image,ImageDraw,ImageFont
Image.MAX_IMAGE_PIXELS=None
proj,outp=sys.argv[1],sys.argv[2]
scn=open(f'{proj}/scenes/main.tscn').read()
res={m[1]:m[0] for m in re.findall(r'path="res://cultic/([^"]+\.glb)" id="([^"]+)"',scn)}
groups={g.group(1):[float(x) for x in g.group(2).split(',')][9:] for g in re.finditer(r'\[node name="(\w+)" type="Node3D" parent="\."\]\ntransform = Transform3D\(([^)]+)\)',scn)}
items=[]
for blk in re.split(r'\n(?=\[node )',scn):
    m=re.search(r'name="([^"]+)" parent="(Models|WallKit|FloorKit)" instance=ExtResource\("([^"]+)"\)',blk)
    if not m: continue
    t=re.search(r'transform = Transform3D\(([^)]+)\)',blk);v=[float(x) for x in t.group(1).split(',')] if t else [1,0,0,0,1,0,0,0,1,0,0,0]
    B=np.array(v[:9]).reshape(3,3).T;o=np.array(v[9:])+np.array(groups.get(m.group(2),[0,0,0]))
    items.append((m.group(1),res[m.group(3)],B,o))
def mat4(n):
    if 'matrix' in n: return np.array(n['matrix']).reshape(4,4).T
    T=np.eye(4)
    if 'scale' in n: T=np.diag(list(n['scale'])+[1])@T
    if 'rotation' in n:
        x,y,z,w=n['rotation'];R=np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]]);M=np.eye(4);M[:3,:3]=R;T=M@T
    if 'translation' in n: M=np.eye(4);M[:3,3]=n['translation'];T=M@T
    return T
def load(p):
    d=open(p,'rb').read();l=struct.unpack('<I',d[12:16])[0];j=json.loads(d[20:20+l]);b=d[20+l+8:]
    def acc(i):
        a=j['accessors'][i];v=j['bufferViews'][a['bufferView']]
        dt={5126:np.float32,5125:np.uint32,5123:np.uint16,5121:np.uint8}[a['componentType']];n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
        return np.frombuffer(b,dt,a['count']*n,v.get('byteOffset',0)+a.get('byteOffset',0)).reshape(a['count'],n)
    cache={}
    def tex(i):
        if i not in cache:
            im=j['images'][j['textures'][i]['source']];v=j['bufferViews'][im['bufferView']];o=v.get('byteOffset',0)
            x=Image.open(io.BytesIO(b[o:o+v['byteLength']])).convert('RGB');x=x.resize((min(1024,x.width),min(1024,x.height)),Image.BILINEAR)
            cache[i]=np.asarray(x).astype(float)
        return cache[i]
    out=[]
    def walk(ni,M):
        n=j['nodes'][ni];M=M@mat4(n)
        if 'mesh' in n:
            for pr in j['meshes'][n['mesh']]['primitives']:
                A=pr['attributes'];P=acc(A['POSITION']).astype(float)@M[:3,:3].T+M[:3,3]
                N=acc(A['NORMAL']).astype(float)@M[:3,:3].T if 'NORMAL' in A else None
                F=acc(pr['indices']).reshape(-1,3).astype(int);UV=acc(A['TEXCOORD_0']).astype(float) if 'TEXCOORD_0' in A else None
                mt=j['materials'][pr['material']] if 'material' in pr else {};pb=mt.get('pbrMetallicRoughness',{})
                ti=pb.get('baseColorTexture',mt.get('emissiveTexture'));T=tex(ti['index']) if ti and UV is not None else None
                E=tex(mt['emissiveTexture']['index']) if 'emissiveTexture' in mt and 'baseColorTexture' in pb else None
                col=np.array(pb.get('baseColorFactor',[0.7,0.7,0.7,1])[:3])*255
                out.append((P,N,F,UV,T,E,col))
        for c in n.get('children',[]): walk(c,M)
    for r in j['scenes'][j.get('scene',0)]['nodes']: walk(r,np.eye(4))
    return out
prims=[];labels=[]
for name,path,B,o in items:
    ps=load(f'{proj}/{path}');allP=[]
    for P,N,F,UV,T,E,col in ps:
        Pw=P@B.T+o;Nw=N@B.T if N is not None else None;prims.append((Pw,Nw,F,UV,T,E,col));allP.append(Pw)
    allP=np.vstack(allP);labels.append((name,allP.min(0),allP.max(0)))
allv=np.vstack([p[0] for p in prims])
AZ=np.radians(float(sys.argv[3]) if len(sys.argv)>3 else 45);EL=np.radians(float(sys.argv[4]) if len(sys.argv)>4 else 35.264)
dv=np.array([np.sin(AZ)*np.cos(EL),np.sin(EL),np.cos(AZ)*np.cos(EL)])
rt=np.cross([0,1,0],dv);rt/=np.linalg.norm(rt);up=np.cross(dv,rt)
SS=2;ppm=float(sys.argv[5]) if len(sys.argv)>5 else 95;ppm*=SS
def scr(Pw): return np.c_[Pw@rt,-(Pw@up),Pw@dv]
lo,hi=allv.min(0),allv.max(0)
gx0,gx1=np.floor(lo[0]-0.5),np.ceil(hi[0]+0.5);gz0,gz1=np.floor(lo[2]-0.5),np.ceil(hi[2]+0.5)
corners=np.array([[x,y,z] for x in (gx0,gx1) for y in (0,hi[1]+0.4) for z in (gz0,gz1)])
C=scr(corners);ox,oy=C[:,0].min()-0.3,C[:,1].min()-0.6
Wd,H=int((C[:,0].max()+0.3-ox)*ppm),int((C[:,1].max()+0.3-oy)*ppm)
img=np.zeros((H,Wd,3));img[:]=(222,224,228);zb=np.full((H,Wd),-1e9)
# floor
fl=scr(np.array([[gx0,0,gz0],[gx1,0,gz0],[gx1,0,gz1],[gx0,0,gz1]]));fim=Image.new('RGB',(Wd,H),(222,224,228));fd=ImageDraw.Draw(fim)
fd.polygon([((q[0]-ox)*ppm,(q[1]-oy)*ppm) for q in fl],fill=(236,236,238))
for gx in np.arange(gx0,gx1+0.01,0.5):
    q=scr(np.array([[gx,0,gz0],[gx,0,gz1]]));fd.line([((q[0,0]-ox)*ppm,(q[0,1]-oy)*ppm),((q[1,0]-ox)*ppm,(q[1,1]-oy)*ppm)],fill=(200,203,210) if gx%1 else (178,182,192),width=SS)
for gz in np.arange(gz0,gz1+0.01,0.5):
    q=scr(np.array([[gx0,0,gz],[gx1,0,gz]]));fd.line([((q[0,0]-ox)*ppm,(q[0,1]-oy)*ppm),((q[1,0]-ox)*ppm,(q[1,1]-oy)*ppm)],fill=(200,203,210) if gz%1 else (178,182,192),width=SS)
# soft contact shadows
sh_=Image.new('L',(Wd,H),0);sd=ImageDraw.Draw(sh_)
for name,mn,mx in labels:
    q=scr(np.array([[mn[0],0,mn[2]],[mx[0],0,mn[2]],[mx[0],0,mx[2]],[mn[0],0,mx[2]]]));sd.polygon([((a-ox)*ppm,(b-oy)*ppm) for a,b,_ in q],fill=70)
from PIL import ImageFilter
sh_=np.asarray(sh_.filter(ImageFilter.GaussianBlur(10*SS))).astype(float)/255
img=np.asarray(fim).astype(float)*(1-0.35*sh_[...,None])
L=np.array([0.45,0.8,0.55]);L/=np.linalg.norm(L)
for P,N,F,UV,T,E,col in prims:
    Q=scr(P);X=(Q[:,0]-ox)*ppm;Y=(Q[:,1]-oy)*ppm;Z=Q[:,2]
    for f in F:
        x,y,z=X[f],Y[f],Z[f]
        a0,a1=int(max(0,np.floor(x.min()))),int(min(Wd-1,np.ceil(x.max())));b0,b1=int(max(0,np.floor(y.min()))),int(min(H-1,np.ceil(y.max())))
        if a1<a0 or b1<b0: continue
        den=(y[1]-y[2])*(x[0]-x[2])+(x[2]-x[1])*(y[0]-y[2])
        if abs(den)<1e-12: continue
        gx,gy=np.meshgrid(np.arange(a0,a1+1)+.5,np.arange(b0,b1+1)+.5)
        w0=((y[1]-y[2])*(gx-x[2])+(x[2]-x[1])*(gy-y[2]))/den;w1=((y[2]-y[0])*(gx-x[2])+(x[0]-x[2])*(gy-y[2]))/den;w2=1-w0-w1
        ins=(w0>=-1e-6)&(w1>=-1e-6)&(w2>=-1e-6)
        if not ins.any(): continue
        zz=w0*z[0]+w1*z[1]+w2*z[2];sub=zb[b0:b1+1,a0:a1+1];upd=ins&(zz>sub)
        if not upd.any(): continue
        W0,W1,W2=w0[upd],w1[upd],w2[upd]
        if T is not None:
            u=W0*UV[f[0],0]+W1*UV[f[1],0]+W2*UV[f[2],0];v=W0*UV[f[0],1]+W1*UV[f[1],1]+W2*UV[f[2],1]
            th,tw,_=T.shape;ty=np.clip((v%1*th).astype(int),0,th-1);tx=np.clip((u%1*tw).astype(int),0,tw-1);c=T[ty,tx].copy()
        else: c=np.tile(col,(len(W0),1))
        if N is not None:
            n=W0[:,None]*N[f[0]]+W1[:,None]*N[f[1]]+W2[:,None]*N[f[2]];n/=np.linalg.norm(n,axis=1,keepdims=True)+1e-12
            n=np.where(((n@dv)<0)[:,None],-n,n);sh=0.42+0.7*np.clip(n@L,0,1)
        else: sh=np.ones(len(W0))
        c=c*sh[:,None]
        if E is not None: c=c+E[ty,tx]*1.1
        sub[upd]=zz[upd];blk=img[b0:b1+1,a0:a1+1];blk[upd]=c
im=Image.fromarray(img.clip(0,255).astype(np.uint8)).resize((Wd//SS,H//SS),Image.LANCZOS);dr=ImageDraw.Draw(im)
f=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',16)
rows=[]
for name,mn,mx in sorted(labels,key=lambda t:-scr(np.array([[(t[1][0]+t[2][0])/2,t[2][1],(t[1][2]+t[2][2])/2]]))[0,1]):
    q=scr(np.array([[(mn[0]+mx[0])/2,mx[1],(mn[2]+mx[2])/2]]))[0];cx,ty=(q[0]-ox)*ppm/SS,(q[1]-oy)*ppm/SS
    bb=dr.textbbox((0,0),name,font=f);w=bb[2]-bb[0];bx=[cx-w/2-5,ty-30,cx+w/2+5,ty-8]
    while any(not(bx[2]<a or bx[0]>c or bx[3]<b_ or bx[1]>d) for a,b_,c,d in rows): bx[1]-=24;bx[3]-=24
    rows.append(tuple(bx));dr.line([(cx,bx[3]),(cx,ty-3)],fill=(140,140,140));dr.rectangle(bx,fill=(255,255,255),outline=(200,200,200));dr.text((bx[0]+5,bx[1]+2),name,fill=(40,40,40),font=f)
dr.text((12,im.height-24),'Изометрия  ·  сетка 0.5 м (толстые линии — 1 м)',fill=(90,90,90),font=f)
im.save(outp);print(im.size)
