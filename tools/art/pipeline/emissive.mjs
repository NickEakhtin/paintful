// Attach an emissive map to every material: node emissive.mjs in.glb emissive.png strength out.glb
import {NodeIO} from '@gltf-transform/core';import {KHRMaterialsEmissiveStrength,ALL_EXTENSIONS} from '@gltf-transform/extensions';import fs from 'fs';
const [,,inp,img,strength,out]=process.argv;const io=new NodeIO().registerExtensions(ALL_EXTENSIONS);const doc=await io.read(inp);
const ext=doc.createExtension(KHRMaterialsEmissiveStrength);
const tex=doc.createTexture('emissive').setImage(fs.readFileSync(img)).setMimeType(img.endsWith('.jpg')?'image/jpeg':'image/png');
for(const m of doc.getRoot().listMaterials()){m.setEmissiveTexture(tex).setEmissiveFactor([1,1,1]);m.setExtension('KHR_materials_emissive_strength',ext.createEmissiveStrength().setEmissiveStrength(+strength))}
await io.write(out,doc);
