// Multi-node prop: shift the root node so the model sits on y=0, centred in X, with its back on z=0 (mode wall)
// or centred in Z (mode floor). Node hierarchy (hinges etc.) is kept. Usage: node place_root.mjs in out wall|floor
import {NodeIO,getBounds} from '@gltf-transform/core';import {ALL_EXTENSIONS} from '@gltf-transform/extensions';
const [,,inp,out,mode='wall']=process.argv;const io=new NodeIO().registerExtensions(ALL_EXTENSIONS);const d=await io.read(inp);
const sc=d.getRoot().listScenes()[0];const b=getBounds(sc);const root=sc.listChildren()[0];const t=root.getTranslation();
root.setTranslation([t[0]-(b.min[0]+b.max[0])/2,t[1]-b.min[1],t[2]-(mode==='wall'?b.min[2]:(b.min[2]+b.max[2])/2)]);
await io.write(out,d);console.log('size',b.max.map((v,i)=>(v-b.min[i]).toFixed(3)).join('x'));
