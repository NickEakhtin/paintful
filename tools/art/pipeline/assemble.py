# assemble.py workdir R out.glb diffuse_fmt(png|jpg)
import sys,json,struct,io,numpy as np
from PIL import Image
from scipy import ndimage
W,R,out,fmt=sys.argv[1],int(sys.argv[2]),sys.argv[3],sys.argv[4]
info=json.load(open(f'{W}/info.json'))
mask=np.fromfile(f'{W}/bake_mask.u8',np.uint8).reshape(R,R)>0
print('coverage %.1f%%'%(mask.mean()*100))
# nearest-filled dilation for all empty texels
_,(iy,ix)=ndimage.distance_transform_edt(~mask,return_indices=True)
imgs={}
for k in ['diffuse','mr','normal']:
    a=np.fromfile(f'{W}/bake_{k}.rgb',np.uint8).reshape(R,R,3)
    a=a[iy,ix];imgs[k]=Image.fromarray(a)
    imgs[k].save(f'{W}/out_{k}.png')
import os
for k in ['diffuse','mr','normal']:
    if os.path.exists(f'{W}/glow_{k}.png'): imgs[k]=Image.open(f'{W}/glow_{k}.png').convert('RGB')
emis=Image.open(f'{W}/glow_emissive.png').convert('RGB') if os.path.exists(f'{W}/glow_emissive.png') else None
def enc(im,kind):
    bio=io.BytesIO()
    if kind=='jpg': im.save(bio,'JPEG',quality=92,subsampling=0,optimize=True);return bio.getvalue(),'image/jpeg'
    im.save(bio,'PNG',optimize=True);return bio.getvalue(),'image/png'
P=np.fromfile(f'{W}/low_pos.f32',np.float32).reshape(-1,3);N=np.fromfile(f'{W}/low_nrm.f32',np.float32).reshape(-1,3)
UV=np.fromfile(f'{W}/low_uv.f32',np.float32).reshape(-1,2);T=np.fromfile(f'{W}/low_tan.f32',np.float32).reshape(-1,4)
I=np.fromfile(f'{W}/low_idx.u32',np.uint32)
bin=b'';views=[];accs=[]
def add(data,target=None):
    global bin
    bin+=b'\0'*((4-len(bin)%4)%4);v={'buffer':0,'byteOffset':len(bin),'byteLength':len(data)}
    if target: v['target']=target
    views.append(v);bin+=data;return len(views)-1
def addacc(arr,typ,ct,target,mm=False):
    vi=add(arr.tobytes(),target);a={'bufferView':vi,'componentType':ct,'count':int(arr.shape[0]),'type':typ}
    if mm: a['min']=arr.min(0).tolist();a['max']=arr.max(0).tolist()
    accs.append(a);return len(accs)-1
aP=addacc(P,'VEC3',5126,34962,True);aN=addacc(N,'VEC3',5126,34962);aT=addacc(T,'VEC4',5126,34962);aU=addacc(UV,'VEC2',5126,34962)
aI=addacc(I.reshape(-1,1),'SCALAR',5125,34963)
images=[];textures=[]
def addimg(name,im,kind):
    data,mime=enc(im,kind);vi=add(data);images.append({'name':name,'mimeType':mime,'bufferView':vi});textures.append({'source':len(images)-1,'sampler':0});return len(textures)-1
tD=addimg('diffuse',imgs['diffuse'],fmt);tM=addimg('metallic_roughness',imgs['mr'],fmt);tN=addimg('normal',imgs['normal'],'png')
tE=addimg('emissive',emis,fmt) if emis is not None else None
m0=info['material'];mat={'name':m0.get('name','model'),'doubleSided':m0.get('doubleSided',False),
 'pbrMetallicRoughness':{'baseColorTexture':{'index':tD},'metallicRoughnessTexture':{'index':tM}},'normalTexture':{'index':tN}}
for k in ('metallicFactor','roughnessFactor','baseColorFactor'):
    if k in m0['pbrMetallicRoughness']: mat['pbrMetallicRoughness'][k]=m0['pbrMetallicRoughness'][k]
ext_used=[]
if tE is not None:
    mat['emissiveTexture']={'index':tE};mat['emissiveFactor']=[1,1,1];mat['extensions']={'KHR_materials_emissive_strength':{'emissiveStrength':3.0}};ext_used.append('KHR_materials_emissive_strength')
bin+=b'\0'*((4-len(bin)%4)%4)
j={'asset':{'version':'2.0','generator':'decimate+bake (meshoptimizer, xatlas)'},'scene':0,'scenes':[{'nodes':[0]}],
 'nodes':[{'name':sys.argv[5] if len(sys.argv)>5 else 'model','mesh':0}],
 'meshes':[{'name':sys.argv[5] if len(sys.argv)>5 else 'model','primitives':[{'attributes':{'POSITION':aP,'NORMAL':aN,'TANGENT':aT,'TEXCOORD_0':aU},'indices':aI,'material':0}]}],
 'materials':[mat],'textures':textures,'images':images,'samplers':[{'magFilter':9729,'minFilter':9987}],
 'accessors':accs,'bufferViews':views,'buffers':[{'byteLength':len(bin)}]}
if ext_used: j['extensionsUsed']=ext_used
js=json.dumps(j,separators=(',',':')).encode();js+=b' '*((4-len(js)%4)%4)
body=struct.pack('<I',len(js))+b'JSON'+js+struct.pack('<I',len(bin))+b'BIN\0'+bin
open(out,'wb').write(b'glTF'+struct.pack('<II',2,12+len(body))+body)
print('tris',len(I)//3,'verts',len(P),'size %.1f MB'%((12+len(body))/1e6))
