// Rodin single-mesh cabinet generated with its doors standing OPEN -> separate door nodes, closed, hinged.
// Triangles in front of the facade (z > zFront) and |x| > xMin are door triangles (left by x<0, right by x>0).
// Each door: principal direction in XZ gives the open angle; the hinge is the door end nearest the facade.
// Geometry is rotated back to closed (door lying along X in the plane z = zFront) and the node origin is the hinge.
// Each closed door is then stretched along X so the two doors meet in the middle of the opening.
// Usage: node split_doors.mjs in.glb out.glb zFront xMin
import {NodeIO} from '@gltf-transform/core';import {ALL_EXTENSIONS} from '@gltf-transform/extensions';import {prune} from '@gltf-transform/functions';
const [,,inp,out,zF,xM]=process.argv;const zFront=+zF,xMin=+xM;
const io=new NodeIO().registerExtensions(ALL_EXTENSIONS);const doc=await io.read(inp);const root=doc.getRoot();
const prim=root.listMeshes()[0].listPrimitives()[0];const P=prim.getAttribute('POSITION').getArray(),N=prim.getAttribute('NORMAL').getArray(),UV=prim.getAttribute('TEXCOORD_0').getArray(),I=prim.getIndices().getArray();
const groups={body:[],door_left:[],door_right:[]};
for(let t=0;t<I.length;t+=3){let cx=0,cz=0;for(let k=0;k<3;k++){cx+=P[3*I[t+k]];cz+=P[3*I[t+k]+2]}cx/=3;cz/=3;
 const g=(cz>zFront&&Math.abs(cx)>xMin)?(cx<0?'door_left':'door_right'):'body';groups[g].push(I[t],I[t+1],I[t+2])}
const buf=root.listBuffers()[0];const scene=root.listScenes()[0];const mat=prim.getMaterial();
function build(name,tris,rot,sx=1){const map=new Map();const pos=[],nor=[],uv=[],idx=[];
 for(const v of tris){if(!map.has(v)){map.set(v,pos.length/3);pos.push(P[3*v],P[3*v+1],P[3*v+2]);nor.push(N[3*v],N[3*v+1],N[3*v+2]);uv.push(UV[2*v],UV[2*v+1])}idx.push(map.get(v))}
 let origin=[0,0,0];
 if(rot){const [hx,hz,ang]=rot;const c=Math.cos(ang),s=Math.sin(ang);origin=[hx,0,hz];
  for(let i=0;i<pos.length;i+=3){const x=pos[i]-hx,z=pos[i+2]-hz;pos[i]=(c*x+s*z)*sx;pos[i+2]=-s*x+c*z;
   const nx=nor[i],nz=nor[i+2];nor[i]=c*nx+s*nz;nor[i+2]=-s*nx+c*nz}}
 const acc=(arr,type)=>doc.createAccessor().setType(type).setArray(arr).setBuffer(buf);
 const p=doc.createPrimitive().setAttribute('POSITION',acc(new Float32Array(pos),'VEC3')).setAttribute('NORMAL',acc(new Float32Array(nor),'VEC3'))
  .setAttribute('TEXCOORD_0',acc(new Float32Array(uv),'VEC2')).setIndices(acc(pos.length/3>65535?new Uint32Array(idx):new Uint16Array(idx),'SCALAR')).setMaterial(mat);
 const node=doc.createNode(name).setMesh(doc.createMesh(name).addPrimitive(p)).setTranslation(origin);return node}
function doorParams(tris,side){const vs=[...new Set(tris)];let mx=0,mz=0;for(const v of vs){mx+=P[3*v];mz+=P[3*v+2]}mx/=vs.length;mz/=vs.length;
 let sxx=0,sxz=0,szz=0;for(const v of vs){const dx=P[3*v]-mx,dz=P[3*v+2]-mz;sxx+=dx*dx;sxz+=dx*dz;szz+=dz*dz}
 const th=0.5*Math.atan2(2*sxz,sxx-szz);let dx=Math.cos(th),dz=Math.sin(th);
 // project vertices on the door direction; hinge end = the end closer to the facade (smaller z)
 let lo=1e9,hi=-1e9;for(const v of vs){const t=(P[3*v]-mx)*dx+(P[3*v+2]-mz)*dz;lo=Math.min(lo,t);hi=Math.max(hi,t)}
 let A=[mx+lo*dx,mz+lo*dz],B=[mx+hi*dx,mz+hi*dz];if(A[1]>B[1])[A,B]=[B,A];
 // direction hinge -> free edge, and the closed target direction (towards the cabinet centre)
 const d=[B[0]-A[0],B[1]-A[1]];const target=side==='door_left'?[1,0]:[-1,0];
 const a=Math.atan2(d[1],d[0]),b=Math.atan2(target[1],target[0]);let ang=b-a;
 // rotation in the XZ plane used in build(): x' = c x + s z, z' = -s x + c z  (a turn by -ang around Y in math terms)
 return {hinge:A,width:Math.hypot(...d),openAngleDeg:(a*180/Math.PI),rot:-ang}}
const out_={};const nodes=[build('body',groups.body,null)];
const qs={door_left:doorParams(groups.door_left,'door_left'),door_right:doorParams(groups.door_right,'door_right')};
const mid=(qs.door_left.hinge[0]+qs.door_right.hinge[0])/2;
for(const side of ['door_left','door_right']){const q=qs[side];q.sx=Math.abs(mid-q.hinge[0])/q.width;out_[side]=q;
 // rotate around the hinge so the door closes, stretch it to the middle, keep the node origin at the hinge
 nodes.push(build(side,groups[side],[q.hinge[0],q.hinge[1],q.rot],q.sx))}
const parent=doc.createNode('wall_cabinet');for(const n of nodes)parent.addChild(n);
for(const c of scene.listChildren())scene.removeChild(c);scene.addChild(parent);
await doc.transform(prune());await io.write(out,doc);
console.log(JSON.stringify(Object.fromEntries(Object.entries(out_).map(([k,v])=>[k,{hinge:v.hinge.map(x=>+x.toFixed(3)),width:+v.width.toFixed(3),openDirDeg:+v.openAngleDeg.toFixed(1),rotDeg:+(v.rot*180/Math.PI).toFixed(1),stretch:+v.sx.toFixed(3)}]))),'tris',{body:groups.body.length/3,left:groups.door_left.length/3,right:groups.door_right.length/3});
