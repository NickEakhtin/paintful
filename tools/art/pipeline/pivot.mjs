// Pivot: 'wall' = bottom-centre of the back face (back on z=0, front +Z); 'floor' = bottom-centre; 'ceiling' = top-centre (hangs down from y=0). Also renames node/mesh/material.
import {NodeIO} from '@gltf-transform/core';import {ALL_EXTENSIONS} from '@gltf-transform/extensions';import {prune} from '@gltf-transform/functions';import path from 'path';
const [,,inp,out,mode='wall',nm]=process.argv;const io=new NodeIO().registerExtensions(ALL_EXTENSIONS);const doc=await io.read(inp);
const name=nm||path.basename(out,'.glb').replace(/^out_/,'frame_');
for(const m of doc.getRoot().listMeshes()){m.setName(name);for(const p of m.listPrimitives()){const a=p.getAttribute('POSITION'),arr=a.getArray();
 let mn=[1e9,1e9,1e9],mx=[-1e9,-1e9,-1e9];for(let i=0;i<arr.length;i+=3)for(let k=0;k<3;k++){mn[k]=Math.min(mn[k],arr[i+k]);mx[k]=Math.max(mx[k],arr[i+k])}
 const o=[(mn[0]+mx[0])/2,mode==='ceiling'?mx[1]:mn[1],mode==='wall'?mn[2]:(mn[2]+mx[2])/2];for(let i=0;i<arr.length;i+=3)for(let k=0;k<3;k++)arr[i+k]-=o[k];a.setArray(arr);console.log(name,'size',mx.map((v,k)=>(v-mn[k]).toFixed(3)).join('x'))}}
for(const n of doc.getRoot().listNodes())n.setName(name);
for(const m of doc.getRoot().listMaterials())m.setName(name);
await doc.transform(prune());await io.write(out,doc);
