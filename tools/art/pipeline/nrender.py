# nrender.py model.glb out.png label : normal-mapped per-pixel render, 2 views
import sys,json,struct,io,numpy as np
from PIL import Image,ImageDraw,ImageFont
Image.MAX_IMAGE_PIXELS=None
d=open(sys.argv[1],'rb').read();l=struct.unpack('<I',d[12:16])[0];j=json.loads(d[20:20+l]);b=d[20+l+8:]
def acc(i):
    a=j['accessors'][i];v=j['bufferViews'][a['bufferView']]
    dt={5126:np.float32,5125:np.uint32,5123:np.uint16,5121:np.uint8}[a['componentType']]
    n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
    return np.frombuffer(b,dt,a['count']*n,v.get('byteOffset',0)+a.get('byteOffset',0)).reshape(a['count'],n)
pr=j['meshes'][0]['primitives'][0];A=pr['attributes']
P=acc(A['POSITION']).astype(float);F=acc(pr['indices']).reshape(-1,3).astype(int);UV=acc(A['TEXCOORD_0']).astype(float);NV=acc(A['NORMAL']).astype(float)
m=j['materials'][0]
def tex(ti,size=2048):
    im=j['images'][j['textures'][ti['index']]['source']];v=j['bufferViews'][im['bufferView']];o=v.get('byteOffset',0)
    return np.asarray(Image.open(io.BytesIO(b[o:o+v['byteLength']])).convert('RGB').resize((size,size),Image.BILINEAR)).astype(float)
TD=tex(m['pbrMetallicRoughness']['baseColorTexture']);TE=tex(m['emissiveTexture']) if 'emissiveTexture' in m else None;TN=tex(m['normalTexture'])/127.5-1
TM=tex(m['pbrMetallicRoughness']['metallicRoughnessTexture'])/255 if 'metallicRoughnessTexture' in m['pbrMetallicRoughness'] else None;th,tw,_=TD.shape
# per-triangle tangent/bitangent (glTF: B=-dP/dv)
e1=P[F[:,1]]-P[F[:,0]];e2=P[F[:,2]]-P[F[:,0]];du1=UV[F[:,1],0]-UV[F[:,0],0];dv1=UV[F[:,1],1]-UV[F[:,0],1];du2=UV[F[:,2],0]-UV[F[:,0],0];dv2=UV[F[:,2],1]-UV[F[:,0],1]
r=du1*dv2-du2*dv1;r=np.where(np.abs(r)<1e-20,0,1/np.where(r==0,1,r))
TT=(e1*dv2[:,None]-e2*dv1[:,None])*r[:,None];BB=-(e2*du1[:,None]-e1*du2[:,None])*r[:,None]
if 'TANGENT' in A:
    TV=acc(A['TANGENT']).astype(float)
ctr=(P.max(0)+P.min(0))/2;ext=(P.max(0)-P.min(0)).max()
views=[(30,-15),(-60,-30)] if len(sys.argv)<5 else eval(sys.argv[4]);Wd,H=700,900
out=Image.new('RGB',(Wd*len(views),H+50),(230,230,230))
L=np.array([0.4,0.6,0.7]);L/=np.linalg.norm(L)
for k,(az,el) in enumerate(views):
    a,e=np.radians(az),np.radians(el)
    R=np.array([[np.cos(a),0,-np.sin(a)],[0,1,0],[np.sin(a),0,np.cos(a)]]);E=np.array([[1,0,0],[0,np.cos(e),np.sin(e)],[0,-np.sin(e),np.cos(e)]]);M=E@R
    Q=(P-ctr)@M.T;s=min(H,Wd)*0.9/ext;X=Wd/2+Q[:,0]*s;Y=H/2-Q[:,1]*s+25;Z=Q[:,2]
    zb=np.full((H+50,Wd),-1e9);img=np.full((H+50,Wd,3),230.)
    Lv=M@L
    for fi,f in enumerate(F):
        x,y,z=X[f],Y[f],Z[f]
        x0,x1=int(max(0,np.floor(x.min()))),int(min(Wd-1,np.ceil(x.max())));y0,y1=int(max(0,np.floor(y.min()))),int(min(H+49,np.ceil(y.max())))
        if x1<x0 or y1<y0: continue
        den=(y[1]-y[2])*(x[0]-x[2])+(x[2]-x[1])*(y[0]-y[2])
        if abs(den)<1e-12: continue
        gx,gy=np.meshgrid(np.arange(x0,x1+1)+.5,np.arange(y0,y1+1)+.5)
        w0=((y[1]-y[2])*(gx-x[2])+(x[2]-x[1])*(gy-y[2]))/den;w1=((y[2]-y[0])*(gx-x[2])+(x[0]-x[2])*(gy-y[2]))/den;w2=1-w0-w1
        ins=(w0>=-1e-6)&(w1>=-1e-6)&(w2>=-1e-6)
        if not ins.any(): continue
        zz=w0*z[0]+w1*z[1]+w2*z[2];sub=zb[y0:y1+1,x0:x1+1];upd=ins&(zz>sub)
        if not upd.any(): continue
        W0,W1,W2=w0[upd],w1[upd],w2[upd]
        u=W0*UV[f[0],0]+W1*UV[f[1],0]+W2*UV[f[2],0];v=W0*UV[f[0],1]+W1*UV[f[1],1]+W2*UV[f[2],1]
        ty=np.clip((v%1*th).astype(int),0,th-1);tx=np.clip((u%1*tw).astype(int),0,tw-1)
        n=(W0[:,None]*NV[f[0]]+W1[:,None]*NV[f[1]]+W2[:,None]*NV[f[2]])@M.T;n/=np.linalg.norm(n,axis=1,keepdims=True)+1e-12
        if 'TANGENT' in A:
            t=(W0[:,None]*TV[f[0],:3]+W1[:,None]*TV[f[1],:3]+W2[:,None]*TV[f[2],:3])@M.T;w=TV[f[0],3]
            t=t-n*(t*n).sum(1,keepdims=True);t/=np.linalg.norm(t,axis=1,keepdims=True)+1e-12;bt=np.cross(n,t)*w
        else:
            t=np.tile(TT[fi]@M.T,(len(n),1));bt=np.tile(BB[fi]@M.T,(len(n),1))
            t=t-n*(t*n).sum(1,keepdims=True);t/=np.linalg.norm(t,axis=1,keepdims=True)+1e-12
            bt=bt-n*(bt*n).sum(1,keepdims=True);bt/=np.linalg.norm(bt,axis=1,keepdims=True)+1e-12
        nm=TN[ty,tx];nw=t*nm[:,:1]+bt*nm[:,1:2]+n*nm[:,2:3];nw/=np.linalg.norm(nw,axis=1,keepdims=True)+1e-12
        if (nw[:,2].mean()<0): nw=-nw  # double-sided facing
        diff=np.clip(nw@Lv,0,1);sh=0.35+0.75*diff
        c=TD[ty,tx]*sh[:,None]
        if TM is not None:
            rgh=np.clip(TM[ty,tx,1],0.05,1);met=TM[ty,tx,2]
            V=np.array([0,0,1.]);Hh=Lv+V;Hh/=np.linalg.norm(Hh)
            ex=2/np.maximum(rgh**4,1e-4)-2;sp=np.clip(nw@Hh,0,1)**np.minimum(ex,4000)*(ex+2)/8*np.clip(nw@Lv,0,1)
            Rr=2*(nw@V)[:,None]*nw-V;env=np.clip(0.25+0.9*np.clip(Rr[:,1],0,1)**1.5+1.6*np.exp(-((Rr[:,0]-0.45)**2+(Rr[:,1]-0.55)**2)/0.02*(0.3+rgh*3)**-1),0,3)
            F0=0.04*(1-met)+met*TD[ty,tx].mean(1)/255;fr=F0+(1-F0)*(1-np.clip(nw@V,0,1))**5
            gl=(1-rgh)**2
            c=c+(sp*0.9*255*(1-rgh)+env*fr*gl*255*0.55)[:,None]
        if TE is not None: c=c+TE[ty,tx]*1.2
        sub[upd]=zz[upd];blk=img[y0:y1+1,x0:x1+1];blk[upd]=c
    out.paste(Image.fromarray(img.clip(0,255).astype(np.uint8)),(k*Wd,0))
dr=ImageDraw.Draw(out);f=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',26)
dr.text((15,H+12),sys.argv[3],fill=(30,30,30),font=f)
out.save(sys.argv[2])
