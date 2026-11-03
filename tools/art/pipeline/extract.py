# extract.py in.glb outdir : writes high mesh + textures as raw arrays
import sys,json,struct,io,os,numpy as np
from PIL import Image
Image.MAX_IMAGE_PIXELS=None
src,od=sys.argv[1],sys.argv[2];os.makedirs(od,exist_ok=True)
d=open(src,'rb').read();l=struct.unpack('<I',d[12:16])[0];j=json.loads(d[20:20+l]);b=d[20+l+8:]
def acc(i):
    a=j['accessors'][i];v=j['bufferViews'][a['bufferView']]
    dt={5126:np.float32,5125:np.uint32,5123:np.uint16,5121:np.uint8}[a['componentType']]
    n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
    stride=v.get('byteStride');o=v.get('byteOffset',0)+a.get('byteOffset',0)
    assert not stride or stride==np.dtype(dt).itemsize*n
    return np.frombuffer(b,dt,a['count']*n,o).reshape(a['count'],n)
sel=[int(x) for x in sys.argv[3].split(',')] if len(sys.argv)>3 else None
prims=[];
for n in j['nodes']:
    if 'mesh' in n and (sel is None or n['mesh'] in sel):
        assert not any(k in n for k in ('matrix','scale','rotation','translation')),n
        prims+=j['meshes'][n['mesh']]['primitives']
for n in j['nodes']: assert 'mesh' in n or not any(k in n for k in ('matrix','scale','rotation','translation')),n
Ps,Ns,Us,Is=[],[],[],[];off=0
for q in prims:
    A=q['attributes'];P=acc(A['POSITION']);Ps.append(P);Ns.append(acc(A['NORMAL']));Us.append(acc(A['TEXCOORD_0']));Is.append(acc(q['indices']).ravel().astype(np.uint32)+off);off+=len(P)
np.vstack(Ps).astype(np.float32).tofile(f'{od}/pos.f32');np.vstack(Ns).astype(np.float32).tofile(f'{od}/nrm.f32');np.vstack(Us).astype(np.float32).tofile(f'{od}/uv.f32');np.concatenate(Is).tofile(f'{od}/idx.u32')
pr=prims[0];A=pr['attributes']
m=j['materials'][pr['material']];pb=m['pbrMetallicRoughness']
def img(ti):
    im=j['images'][j['textures'][ti['index']]['source']];v=j['bufferViews'][im['bufferView']];o=v.get('byteOffset',0)
    return Image.open(io.BytesIO(b[o:o+v['byteLength']])).convert('RGB')
info={'nv':int(off),'nt':int(sum(len(x) for x in Is)//3),'material':m}
for key,ti in [('diffuse',pb.get('baseColorTexture')),('mr',pb.get('metallicRoughnessTexture')),('normal',m.get('normalTexture'))]:
    if ti:
        im=img(ti);np.asarray(im,dtype=np.uint8).tofile(f'{od}/{key}.rgb');info[key]=im.size
json.dump(info,open(f'{od}/info.json','w'))
print(info['nv'],info['nt'],{k:info.get(k) for k in ('diffuse','mr','normal')})
