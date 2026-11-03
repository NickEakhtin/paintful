// Get or replace a material texture in a .glb: node teximg.mjs get in.glb BaseColorTexture out.png | node teximg.mjs set in.glb BaseColorTexture new.jpg out.glb
import {NodeIO} from '@gltf-transform/core';import {ALL_EXTENSIONS} from '@gltf-transform/extensions';import fs from 'fs';
const [,,mode,inp,slot,file,out]=process.argv;const io=new NodeIO().registerExtensions(ALL_EXTENSIONS);const doc=await io.read(inp);
const t=doc.getRoot().listTextures().find(t=>doc.getRoot().listMaterials().some(m=>m['get'+slot]()===t));
if(mode==='get'){fs.writeFileSync(file,t.getImage());console.log(t.getMimeType())}
else{t.setImage(fs.readFileSync(file)).setMimeType(file.endsWith('.jpg')?'image/jpeg':'image/png');await io.write(out,doc)}
