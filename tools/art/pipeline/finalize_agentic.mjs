// Agentic (n-gons) Rodin model -> game prop: one primitive per material (few draw calls), simplified, box-projected
// UVs with tileable wear textures on iron / bronze, Godot-friendly glass (alpha blend instead of transmission),
// brighter filament, pivot at the base centre, real height.
// Usage: node finalize_agentic.mjs in.glb out.glb height simplify_ratio texdir
import {NodeIO} from '@gltf-transform/core';import {ALL_EXTENSIONS, KHRMaterialsEmissiveStrength} from '@gltf-transform/extensions';
import {flatten, join, weld, simplify, dedup, prune, getBounds} from '@gltf-transform/functions';
import {MeshoptSimplifier} from 'meshoptimizer';import fs from 'fs';
const [,,inp,out,H,ratio,texdir]=process.argv;
const io=new NodeIO().registerExtensions(ALL_EXTENSIONS);const doc=await io.read(inp);const root=doc.getRoot();
for(const m of root.listMeshes())for(const p of m.listPrimitives())for(const s of p.listSemantics())if(s!=='POSITION'&&s!=='NORMAL')p.setAttribute(s,null);
await doc.transform(flatten(),join({keepNamed:false}),weld(),simplify({simplifier:MeshoptSimplifier,ratio:+ratio,error:0.0006}),dedup(),prune());
// bake node transforms into vertices, scale to height, move pivot to the base centre
const sc=root.listScenes()[0];const b0=getBounds(sc);const k=(+H)/(b0.max[1]-b0.min[1]);
const nodes=root.listNodes().filter(n=>n.getMesh());
const base=[0,0];
for(const n of nodes){const M=n.getWorldMatrix();for(const p of n.getMesh().listPrimitives()){const a=p.getAttribute('POSITION'),arr=a.getArray().slice(),nr=p.getAttribute('NORMAL'),na=nr?nr.getArray().slice():null;
 for(let i=0;i<arr.length;i+=3){const x=arr[i],y=arr[i+1],z=arr[i+2];arr[i]=M[0]*x+M[4]*y+M[8]*z+M[12];arr[i+1]=M[1]*x+M[5]*y+M[9]*z+M[13];arr[i+2]=M[2]*x+M[6]*y+M[10]*z+M[14];
  if(na){const u=na[i],v=na[i+1],w=na[i+2];let X=M[0]*u+M[4]*v+M[8]*w,Y=M[1]*u+M[5]*v+M[9]*w,Z=M[2]*u+M[6]*v+M[10]*w;const l=Math.hypot(X,Y,Z)||1;na[i]=X/l;na[i+1]=Y/l;na[i+2]=Z/l}}
 a.setArray(arr);if(na)nr.setArray(na)}n.setMatrix([1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1])}
for(const n of root.listNodes())if(n!==nodes[0]&&!n.getMesh()&&!n.listChildren().length)n.dispose();
// base centre = centre of the lowest 3% of vertices
let ymin=1e9,ymax=-1e9;const P=[];for(const n of nodes)for(const p of n.getMesh().listPrimitives()){const a=p.getAttribute('POSITION').getArray();for(let i=0;i<a.length;i+=3){P.push([a[i],a[i+1],a[i+2]]);ymin=Math.min(ymin,a[i+1]);ymax=Math.max(ymax,a[i+1])}}
const low=P.filter(v=>v[1]<ymin+(ymax-ymin)*0.03);const cx=(Math.min(...low.map(v=>v[0]))+Math.max(...low.map(v=>v[0])))/2,cz=(Math.min(...low.map(v=>v[2]))+Math.max(...low.map(v=>v[2])))/2;
const TILE=0.22;   // metres per texture tile
for(const n of nodes)for(const p of n.getMesh().listPrimitives()){const a=p.getAttribute('POSITION'),arr=a.getArray().slice(),nr=p.getAttribute('NORMAL').getArray();const uv=new Float32Array(arr.length/3*2);
 for(let i=0,j=0;i<arr.length;i+=3,j+=2){arr[i]=(arr[i]-cx)*k;arr[i+1]=(arr[i+1]-ymin)*k;arr[i+2]=(arr[i+2]-cz)*k;
  const ax=Math.abs(nr[i]),ay=Math.abs(nr[i+1]),az=Math.abs(nr[i+2]);let u,v;
  if(ay>=ax&&ay>=az){u=arr[i];v=arr[i+2]}else if(ax>=az){u=arr[i+2];v=arr[i+1]}else{u=arr[i];v=arr[i+1]}
  uv[j]=u/TILE;uv[j+1]=-v/TILE}
 a.setArray(arr);p.setAttribute('TEXCOORD_0',doc.createAccessor().setType('VEC2').setArray(uv).setBuffer(root.listBuffers()[0]))}
const tex=(f,mime)=>doc.createTexture(f).setImage(fs.readFileSync(texdir+'/'+f)).setMimeType(mime);
const es=doc.createExtension(KHRMaterialsEmissiveStrength);
for(const m of root.listMaterials()){const nm=m.getName();
 if(/enamel/i.test(nm)){m.setBaseColorFactor([1,1,1,1]).setBaseColorTexture(tex('iron_bc.jpg','image/jpeg')).setMetallicRoughnessTexture(tex('iron_mr.png','image/png')).setMetallicFactor(1).setRoughnessFactor(1)}
 else if(/bronze/i.test(nm)){m.setBaseColorFactor([1,1,1,1]).setBaseColorTexture(tex('bronze_bc.jpg','image/jpeg')).setMetallicRoughnessTexture(tex('bronze_mr.png','image/png')).setMetallicFactor(1).setRoughnessFactor(1)}
 else if(/glass/i.test(nm)){for(const e of m.listExtensions())m.setExtension(e.extensionName,null);m.setAlphaMode('BLEND').setBaseColorFactor([1.0,0.62,0.25,0.3]).setRoughnessFactor(0.04).setMetallicFactor(0).setDoubleSided(true).setEmissiveFactor([1,0.42,0.1]);m.setExtension('KHR_materials_emissive_strength',es.createEmissiveStrength().setEmissiveStrength(0.5))}
 else if(/filament/i.test(nm)){m.setBaseColorFactor([1,0.55,0.15,1]).setEmissiveFactor([1,0.45,0.1]);m.setExtension('KHR_materials_emissive_strength',es.createEmissiveStrength().setEmissiveStrength(18))}
}
for(const e of root.listExtensionsUsed())if(!root.listMaterials().some(m=>m.getExtension(e.extensionName))&&e.extensionName!=='KHR_materials_emissive_strength')e.dispose();
await doc.transform(prune());
await io.write(out,doc);
let tris=0;for(const m of root.listMeshes())for(const p of m.listPrimitives())tris+=p.getIndices().getCount()/3;
console.log('draw calls',root.listMeshes().reduce((s,m)=>s+m.listPrimitives().length,0),'tris',tris,'height',H,'scale',k.toFixed(4));
