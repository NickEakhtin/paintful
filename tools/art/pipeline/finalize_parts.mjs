// Agentic (n-gons) Rodin model -> game prop with movable parts. Config (JSON file):
//  { "height": m, "ratio": simplify ratio, "tile": m per texture tile, "texdir": dir,
//    "materials": [{"match": regex, "bc": png, "mr": png} | {"match": regex, "keep": true}],
//    "remat": {"part-name regex": "material name"} (optional: move parts to another material),
//    "groups": [{"name": node, "names": regex (parts by name), "box": [x0,x1,y0,y1,zmin] (parts whose centre is inside),
//               "exclude": regex, "pivot": [x,y,z] (source coords; node origin = hinge / slide origin)}] }
// Parts not claimed by a group go to "body". Each group becomes one node with one primitive per material.
// Usage: node finalize_parts.mjs in.glb out.glb config.json
import {NodeIO} from '@gltf-transform/core';import {ALL_EXTENSIONS} from '@gltf-transform/extensions';
import {flatten, join, weld, simplify, dedup, prune, getBounds} from '@gltf-transform/functions';
import {MeshoptSimplifier} from 'meshoptimizer';import fs from 'fs';
const [,,inp,out,cfgf]=process.argv;const C=JSON.parse(fs.readFileSync(cfgf));
const io=new NodeIO().registerExtensions(ALL_EXTENSIONS);const doc=await io.read(inp);const root=doc.getRoot();const scene=root.listScenes()[0];
for(const m of root.listMeshes())for(const p of m.listPrimitives())for(const s of p.listSemantics())if(s!=='POSITION'&&s!=='NORMAL')p.setAttribute(s,null);
await doc.transform(flatten());
for(const [re,mn] of Object.entries(C.remat||{})){const mat=root.listMaterials().find(m=>m.getName()===mn);for(const n of root.listNodes())if(n.getMesh()&&new RegExp(re).test(n.getName())){const mesh=n.getMesh().clone();for(const p of mesh.listPrimitives())p.setMaterial(mat);n.setMesh(mesh)}}
const b0=getBounds(scene);const k=C.height/(b0.max[1]-b0.min[1]);
const groups=[...C.groups,{name:'body'}].map(g=>({...g,node:doc.createNode(g.name),re:g.names&&new RegExp(g.names),ex:g.exclude&&new RegExp(g.exclude)}));
for(const g of groups)scene.addChild(g.node);
for(const n of root.listNodes().filter(n=>n.getMesh())){
  const b=getBounds(n);const c=[0,1,2].map(i=>(b.min[i]+b.max[i])/2);const nm=n.getName();
  const g=groups.find(g=>g.name==='body'||(!(g.ex&&g.ex.test(nm))&&((g.re&&g.re.test(nm))||(g.box&&c[0]>=g.box[0]&&c[0]<=g.box[1]&&c[1]>=g.box[2]&&c[1]<=g.box[3]&&c[2]>=g.box[4]))));
  const M=n.getWorldMatrix();n.getParentNode()?.removeChild(n);scene.removeChild(n);g.node.addChild(n);n.setMatrix(M);}
await doc.transform(join({keepNamed:false}),weld(),simplify({simplifier:MeshoptSimplifier,ratio:C.ratio,error:0.0005}),dedup(),prune({keepLeaves:false}));
// ground = lowest vertex; centre x/z of the whole model; bake everything into group-local coordinates
const cx=(b0.min[0]+b0.max[0])/2,cz=(b0.min[2]+b0.max[2])/2,y0=b0.min[1];
const tex=(f)=>doc.createTexture(f).setImage(fs.readFileSync(C.texdir+'/'+f)).setMimeType(f.endsWith('.jpg')?'image/jpeg':'image/png');const cache={};const T=f=>cache[f]||(cache[f]=tex(f));
let tris=0,draws=0;
for(const g of groups){const pv=g.pivot||[cx,y0,cz];const P0=[(pv[0]-cx)*k,(pv[1]-y0)*k,(pv[2]-cz)*k];g.node.setTranslation(P0);
 for(const n of g.node.listChildren()){const M=n.getMatrix();for(const p of n.getMesh()?.listPrimitives()||[]){
  const a=p.getAttribute('POSITION'),arr=a.getArray().slice(),nr=p.getAttribute('NORMAL'),na=nr.getArray().slice();const uv=new Float32Array(arr.length/3*2);
  for(let i=0,j=0;i<arr.length;i+=3,j+=2){const x=arr[i],y=arr[i+1],z=arr[i+2];
   const wx=M[0]*x+M[4]*y+M[8]*z+M[12],wy=M[1]*x+M[5]*y+M[9]*z+M[13],wz=M[2]*x+M[6]*y+M[10]*z+M[14];
   const X=(wx-cx)*k,Y=(wy-y0)*k,Z=(wz-cz)*k;arr[i]=X-P0[0];arr[i+1]=Y-P0[1];arr[i+2]=Z-P0[2];
   const u=na[i],v=na[i+1],w=na[i+2];let nx=M[0]*u+M[4]*v+M[8]*w,ny=M[1]*u+M[5]*v+M[9]*w,nz=M[2]*u+M[6]*v+M[10]*w;const l=Math.hypot(nx,ny,nz)||1;na[i]=nx/l;na[i+1]=ny/l;na[i+2]=nz/l;
   const ax=Math.abs(na[i]),ay=Math.abs(na[i+1]),az=Math.abs(na[i+2]);let U,V;
   if(ay>=ax&&ay>=az){U=X;V=Z}else if(ax>=az){U=Z;V=Y}else{U=X;V=Y}
   uv[j]=U/C.tile;uv[j+1]=-V/C.tile}
  a.setArray(arr);nr.setArray(na);p.setAttribute('TEXCOORD_0',doc.createAccessor().setType('VEC2').setArray(uv).setBuffer(root.listBuffers()[0]));
  tris+=p.getIndices().getCount()/3;draws++}
  n.setMatrix([1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]);n.setName(g.name+'_mesh')}}
for(const m of root.listMaterials()){const r=C.materials.find(r=>new RegExp(r.match,'i').test(m.getName()));if(!r||r.keep)continue;
 m.setBaseColorFactor([1,1,1,1]).setBaseColorTexture(T(r.bc)).setMetallicRoughnessTexture(T(r.mr)).setMetallicFactor(1).setRoughnessFactor(1)}
await doc.transform(prune());await io.write(out,doc);
console.log('groups',groups.map(g=>g.name+':'+g.node.listChildren().reduce((s,n)=>s+(n.getMesh()?.listPrimitives().length||0),0)).join(' '),'| draw calls',draws,'| tris',tris,'| scale',k.toFixed(4));
