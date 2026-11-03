# split.py in.glb out.glb RootName name:xmin:xmax ...  (split single-mesh glb into child nodes by triangle centroid x; each pivot at its base centre)
import sys,json,struct,numpy as np
d=open(sys.argv[1],'rb').read();l=struct.unpack('<I',d[12:16])[0];j=json.loads(d[20:20+l]);b=d[20+l+8:]
def acc(i):
    a=j['accessors'][i];v=j['bufferViews'][a['bufferView']]
    dt={5126:np.float32,5125:np.uint32}[a['componentType']];n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
    return np.frombuffer(b,dt,a['count']*n,v.get('byteOffset',0)+a.get('byteOffset',0)).reshape(a['count'],n)
pr=j['meshes'][0]['primitives'][0];A=pr['attributes']
P,N,T,UV=acc(A['POSITION']),acc(A['NORMAL']),acc(A['TANGENT']),acc(A['TEXCOORD_0']);F=acc(pr['indices']).reshape(-1,3)
cx=P[F].mean(1)[:,0]
# keep image bufferViews, rebuild geometry
imgviews=[im['bufferView'] for im in j['images']]
nb=b'';views=[];accs=[]
def add(data,target=None):
    global nb
    nb+=b'\0'*((4-len(nb)%4)%4);v={'buffer':0,'byteOffset':len(nb),'byteLength':len(data)}
    if target: v['target']=target
    views.append(v);nb+=data;return len(views)-1
def addacc(arr,typ,ct,target,mm=False):
    vi=add(np.ascontiguousarray(arr).tobytes(),target);a={'bufferView':vi,'componentType':ct,'count':int(arr.shape[0]),'type':typ}
    if mm: a['min']=arr.min(0).tolist();a['max']=arr.max(0).tolist()
    accs.append(a);return len(accs)-1
meshes=[];nodes=[{'name':sys.argv[3],'children':[]}]
for spec in sys.argv[4:]:
    name,x0,x1=spec.split(':');x0,x1=float(x0),float(x1)
    sel=F[(cx>=x0)&(cx<x1)]
    used=np.unique(sel);rm=-np.ones(len(P),int);rm[used]=np.arange(len(used))
    p=P[used].copy();base=np.array([(p[:,0].min()+p[:,0].max())/2,p[:,1].min(),(p[:,2].min()+p[:,2].max())/2]);p-=base
    prim={'attributes':{'POSITION':addacc(p.astype(np.float32),'VEC3',5126,34962,True),'NORMAL':addacc(N[used],'VEC3',5126,34962),'TANGENT':addacc(T[used],'VEC4',5126,34962),'TEXCOORD_0':addacc(UV[used],'VEC2',5126,34962)},
          'indices':addacc(rm[sel].astype(np.uint32).reshape(-1,1),'SCALAR',5125,34963),'material':0}
    meshes.append({'name':name,'primitives':[prim]});import os
    nodes.append({'name':name,'mesh':len(meshes)-1,'translation':[0,0,0] if os.environ.get('ZERO') else base.tolist()});nodes[0]['children'].append(len(nodes)-1)
    print(name,len(sel),'tris','base',base.round(3),'size',(p.max(0)-p.min(0)).round(3))
for im in j['images']:
    v=j['bufferViews'][im['bufferView']];o=v.get('byteOffset',0);im['bufferView']=add(b[o:o+v['byteLength']])
nb+=b'\0'*((4-len(nb)%4)%4)
j.update({'nodes':nodes,'meshes':meshes,'scenes':[{'nodes':[0]}],'scene':0,'accessors':accs,'bufferViews':views,'buffers':[{'byteLength':len(nb)}]})
js=json.dumps(j,separators=(',',':')).encode();js+=b' '*((4-len(js)%4)%4)
body=struct.pack('<I',len(js))+b'JSON'+js+struct.pack('<I',len(nb))+b'BIN\0'+nb
open(sys.argv[2],'wb').write(b'glTF'+struct.pack('<II',2,12+len(body))+body);print('size %.1f MB'%((12+len(body))/1e6))
