// Rotate a model -90 deg about X (an upright disc facing +Z ends up lying flat, face up). Usage: node lay_flat.mjs in out
import {NodeIO} from '@gltf-transform/core';import {ALL_EXTENSIONS} from '@gltf-transform/extensions';
const [,,inp,out]=process.argv;const io=new NodeIO().registerExtensions(ALL_EXTENSIONS);const d=await io.read(inp);
for(const m of d.getRoot().listMeshes())for(const p of m.listPrimitives())for(const s of ['POSITION','NORMAL']){const a=p.getAttribute(s);if(!a)continue;const r=a.getArray().slice();
 for(let i=0;i<r.length;i+=3){const y=r[i+1],z=r[i+2];r[i+1]=z;r[i+2]=-y}a.setArray(r)}
await io.write(out,d);
