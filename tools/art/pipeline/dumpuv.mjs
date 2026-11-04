// Dump POSITION / TEXCOORD_0 / indices of the first primitive to d_pos.bin, d_uv.bin, d_idx.bin (input for emclean.py)
import {NodeIO} from '@gltf-transform/core';import fs from 'fs';
const doc=await new NodeIO().read(process.argv[2]);const p=doc.getRoot().listMeshes()[0].listPrimitives()[0];
fs.writeFileSync('d_pos.bin',Buffer.from(p.getAttribute('POSITION').getArray().buffer));
fs.writeFileSync('d_uv.bin',Buffer.from(p.getAttribute('TEXCOORD_0').getArray().buffer));
fs.writeFileSync('d_idx.bin',Buffer.from(Uint32Array.from(p.getIndices().getArray()).buffer));
