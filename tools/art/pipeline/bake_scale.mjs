// Bake a uniform scale into a .glb (vertex positions and node translations), so the model is real-size at Scale 1.
// Usage: node bake_scale.mjs in.glb out.glb factor
import {NodeIO} from '@gltf-transform/core';import {ALL_EXTENSIONS} from '@gltf-transform/extensions';
const [,,inp,out,f]=process.argv;const k=+f;const io=new NodeIO().registerExtensions(ALL_EXTENSIONS);const doc=await io.read(inp);
const done=new Set();
for(const m of doc.getRoot().listMeshes())for(const p of m.listPrimitives()){
  for(const a of [p.getAttribute('POSITION'),...p.listTargets().map(t=>t.getAttribute('POSITION'))]){
    if(!a||done.has(a))continue;done.add(a);const arr=a.getArray().slice();for(let i=0;i<arr.length;i++)arr[i]*=k;a.setArray(arr)}}
for(const n of doc.getRoot().listNodes()){const t=n.getTranslation();n.setTranslation([t[0]*k,t[1]*k,t[2]*k])}
await io.write(out,doc);
