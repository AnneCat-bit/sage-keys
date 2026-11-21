import * as THREE from '../assets/three.module.min.js';
import { keys } from './layout.js';

const width = 16.95;
const depth = 6.94;
const deckHeight = .69;
const deckTilt = .035;
const travel = .18;
const colors = {
  ivory: '#eaece2', sage: '#9eb2a1', mint: '#bfceb9',
  forest: '#4d6858', evergreen: '#789381'
};
const linearColors = new Map();

function rgb(hex) {
  if (!linearColors.has(hex)) linearColors.set(hex, new THREE.Color(hex));
  return linearColors.get(hex);
}

// Build the entire frame and all 82 keycaps in batches. Each cap occupies one
// contiguous position range. A keystroke updates only that cap and its ink.
class Batch {
  positions = [];
  normals = [];
  colors = [];
  uvs = [];
  indices = [];

  get size() { return this.positions.length / 3; }

  vertex(x, y, z, nx, ny, nz, color, brightness = 1, uv) {
    const index = this.size;
    const scale = Math.hypot(nx, ny, nz) || 1;
    const c = rgb(color);
    this.positions.push(x, y, z);
    this.normals.push(nx / scale, ny / scale, nz / scale);
    this.colors.push(c.r * brightness, c.g * brightness, c.b * brightness);
    if (uv) this.uvs.push(...uv);
    return index;
  }

  mesh(material, moving = false) {
    const g = new THREE.BufferGeometry();
    const pos = new THREE.Float32BufferAttribute(this.positions, 3);
    if (moving) pos.setUsage(THREE.DynamicDrawUsage);
    g.setAttribute('position', pos);
    g.setAttribute('normal', new THREE.Float32BufferAttribute(this.normals, 3));
    g.setAttribute('color', new THREE.Float32BufferAttribute(this.colors, 3));
    if (this.uvs.length) g.setAttribute('uv', new THREE.Float32BufferAttribute(this.uvs, 2));
    g.setIndex(this.indices);
    return new THREE.Mesh(g, material);
  }
}

function rectangle(w, d, r, y, cx, cz, tilt, segments) {
  const result = [];
  const corners = [[1, -1], [1, 1], [-1, 1], [-1, -1]];
  for (let c = 0; c < 4; c++) {
    const [sx, sz] = corners[c];
    for (let j = 0; j <= segments; j++) {
      const theta = (c - 1 + j / segments) * Math.PI / 2;
      const nx = Math.cos(theta), nz = Math.sin(theta);
      const x = sx * (w / 2 - r) + r * nx;
      const z = sz * (d / 2 - r) + r * nz;
      result.push({x: cx + x, z: cz + z, y: y - tilt * z, nx, nz});
    }
  }
  return result;
}

function band(batch, lower, upper, color, tilt, lowerShade = 1, upperShade = 1) {
  const base = batch.size, n = lower.length;
  for (let i = 0; i < n; i++) {
    const a = lower[i], b = upper[i];
    const dy = b.y - a.y + tilt * (b.z - a.z);
    const ny = (a.x - b.x) * a.nx + (a.z - b.z) * a.nz;
    const nx = a.nx * dy, nz = a.nz * dy + tilt * ny;
    batch.vertex(a.x, a.y, a.z, nx, ny, nz, color, lowerShade);
    batch.vertex(b.x, b.y, b.z, nx, ny, nz, color, upperShade);
    const j = (i + 1) % n;
    batch.indices.push(base + 2*i, base + 2*i+1, base + 2*j+1,
      base + 2*i, base + 2*j+1, base + 2*j);
  }
}

function lid(batch, points, cx, cz, y, tilt, color, dish = 0, uv) {
  const center = batch.vertex(cx, y - dish, cz, 0, 1, tilt, color, 1, uv?.(cx, cz));
  const start = batch.size;
  for (const p of points) {
    batch.vertex(p.x, p.y, p.z, -dish*3*p.nx, 1, tilt - dish*3*p.nz, color, 1, uv?.(p.x,p.z));
  }
  for (let i = 0; i < points.length; i++) {
    batch.indices.push(center, start + (i+1) % points.length, start + i);
  }
}

function housing(batch) {
  // Keep the bottom flat on the desk, while the upper shell rises towards F1.
  const specs = [
    [width-.48, depth-.48, .37, .065, 0, '#63746a'],
    [width-.18, depth-.18, .38, .16, .012, '#94a39a'],
    [width-.08, depth-.08, .36, .245, .022, '#a8b6b1'],
    [width-.085, depth-.085, .36, .265, .022, '#64766d'],
    [width-.06, depth-.06, .36, .29, .022, '#e5e9e4'],
    [width, depth, .37, .36, deckTilt, '#aab7b1'],
    [width, depth, .37, deckHeight-.068, deckTilt, '#a0b0a8'],
    [width-.095, depth-.095, .33, deckHeight, deckTilt, '#d5ded6'],
    [width-.18, depth-.18, .295, deckHeight+.012, deckTilt, '#bcc9b9']
  ];
  let previous;
  for (const [w,d,r,h,tilt,c] of specs) {
    const points = rectangle(w, d, r, h, 0, 0, tilt, 6);
    if (previous) band(batch, previous, points, c, tilt);
    previous = points;
  }
  lid(batch, previous, 0, 0, deckHeight+.012, deckTilt, '#b3c0b6');
}

function sprig(ctx, x, y) {
  ctx.save();
  ctx.translate(x, y);
  ctx.scale(1.28,1.28);
  ctx.lineCap = 'round';
  ctx.strokeStyle = '#455e4a';
  ctx.fillStyle = '#526c55';
  ctx.lineWidth = 1.9;
  ctx.beginPath();
  ctx.moveTo(-19, 9); ctx.bezierCurveTo(-9, 10, 8, 0, 19, -12); ctx.stroke();
  for (const [lx,ly,a] of [[-9,8,-.15], [-3,5,-1.25], [4,1,-.05], [10,-4,-1.12], [15,-8,-.3]]) {
    ctx.save();
    ctx.translate(lx,ly); ctx.rotate(a);
    ctx.beginPath();
    ctx.moveTo(0,0); ctx.quadraticCurveTo(4,-6,11,-4.6);
    ctx.quadraticCurveTo(8,1,0,0); ctx.fill(); ctx.restore();
  }
  ctx.restore();
}

function makeInk() {
  const canvas = document.createElement('canvas');
  canvas.width = 1024; canvas.height = 1024;
  const ctx = canvas.getContext('2d');
  const tiles = new Map();
  let x = 2, y = 2;
  for (const key of keys) {
    const w = Math.ceil((key.w - .23) * 100), h = 75;
    if (x + w + 2 > canvas.width) { x = 2; y += h + 4; }
    tiles.set(key.code, {x, y, w, h});
    ctx.fillStyle = key.tone === 'forest' ? '#f3f1d9' : '#344438';
    ctx.textBaseline = 'middle';
    ctx.textAlign = 'center';
    const face = n => `${n >= 28 ? 500 : 600} ${n}px Arial, "DejaVu Sans", sans-serif`;
    if (key.code === 'Space') {
      sprig(ctx, x + w * .83, y + h * .53);
    } else if (key.upper && (key.w > 1.55 || /Left|Right/.test(key.code) && !key.code.startsWith('Bracket'))) {
      ctx.textAlign = 'left';
      ctx.font = face(24);
      ctx.fillText(key.upper, x+7, y+21);
      ctx.font = face(key.label.length > 5 && key.w < 1.4 ? 16 : 20);
      ctx.fillText(key.label, x+7, y+52, w-12);
    } else if (key.upper) {
      ctx.font = face(19); ctx.fillText(key.upper, x+w*.5, y+15);
      ctx.font = face(28); ctx.fillText(key.label, x+w*.5, y+50);
    } else {
      const size = key.code.startsWith('Key') ? 34 : key.code.startsWith('Arrow') ? 35 : 22;
      ctx.font = face(size);
      ctx.fillText(key.label, x+w/2, y+h*.5+1, w-8);
    }
    x += w + 4;
  }
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.anisotropy = 2;
  return {texture, tiles};
}

function keyHousing(batch, k, deck) {
  const {x,z,w} = k;
  const bottom = rectangle(w-.003,.993,.085,deck+.009,x,z,deckTilt,2);
  const lip = rectangle(w-.036,.959,.075,deck+.03,x,z,deckTilt,2);
  band(batch,bottom,lip,'#7a897b',deckTilt);
  lid(batch,lip,x,z,deck+.03,deckTilt,'#566258');
  // The switch collar and guide post sit below the skirt of each keycap.
  const guide = rectangle(.54,.53,.085,deck+.15,x,z,deckTilt,1);
  const guideFoot = rectangle(.64,.63,.1,deck+.045,x,z,deckTilt,1);
  band(batch,guideFoot,guide,'#747e70',deckTilt);
  lid(batch,guide,x,z,deck+.15,deckTilt,'#909f86');
  const stem = rectangle(.26,.26,.035,deck+.26,x,z,deckTilt,1);
  const foot = rectangle(.27,.27,.035,deck+.15,x,z,deckTilt,1);
  band(batch,foot,stem,'#889e78',deckTilt);
}

function cap(body, ink, key, tile, deck) {
  const {x,z,w,row} = key;
  const color = key.code === 'Space' ? '#a1b69f' : colors[key.tone];
  const tilt = [.08,.09,.055,.015,-.025,-.035][row];
  const y = deck + [.63,.61,.57,.54,.535,.54][row];
  // Flared skirt, short vertical base, tapered shoulders, and a softened rim.
  const specs = [
    [w-.088,.908,.079,deck+.13,0,.53],
    [w-.052,.946,.095,deck+.165,0,.69],
    [w-.066,.933,.099,deck+.245,-.003,.84],
    [w-.207,.786,.119,y-.065,-.026,.97],
    [w-.256,.730,.121,y-.018,-.031,1],
    [w-.302,.691,.106,y,-.032,1]
  ];
  let previous;
  for (let i=0;i<specs.length;i++) {
    const [sw,sd,r,h,shift,shade] = specs[i];
    const points = rectangle(sw,sd,r,h,x,z+shift,tilt,3);
    if (previous) band(body,previous,points,color,tilt,specs[i-1][5],shade);
    previous = points;
  }
  const topZ = z-.032;
  const dish = key.code === 'Space' ? 0 : .024;
  lid(body,previous,x,topZ,y,tilt,color,dish);
  if (key.code === 'KeyF' || key.code === 'KeyJ') {
    const barZ = topZ + .245, barY = y - tilt * .245 - dish * .28;
    const foot = rectangle(.18,.036,.014,barY,x,barZ,tilt,2);
    const top = rectangle(.154,.022,.009,barY+.012,x,barZ,tilt,2);
    band(body,foot,top,color,tilt,.83,1);
    lid(body,top,x,barZ,barY+.012,tilt,color);
  }
  const {x:tx,y:ty,w:tw,h:th} = tile;
  const uv = (px,pz) => [
    (tx + ((px-x)/(w-.302)+.5)*tw) / 1024,
    1 - (ty + ((pz-topZ)/.691+.5)*th) / 1024
  ];
  lid(ink,previous.map(p=>({...p,y:p.y+.002})),x,topZ,y+.002,tilt,'#ffffff',dish,uv);
}

// Turned-aluminium details share a batch, including the dial's actual knurls.
function circularRing(cx,cz,y,r,n,flute = 0) {
  return Array.from({length:n}, (_, i) => {
    const angle = i*2*Math.PI/n, nx = Math.cos(angle), nz = Math.sin(angle);
    const radius = r - (i%2)*flute;
    return {x:cx+nx*radius,z:cz+nz*radius,y,nx,nz};
  });
}
function knurledBand(batch, bottom, top, color) {
  for (let i = 0; i < bottom.length; i++) {
    const j = (i + 1) % bottom.length;
    const nx = bottom[j].z - bottom[i].z, nz = bottom[i].x - bottom[j].x;
    const start = batch.size;
    for (const p of [bottom[i],top[i],top[j],bottom[j]]) {
      batch.vertex(p.x,p.y,p.z,nx,0,nz,color);
    }
    batch.indices.push(start,start+1,start+2,start,start+2,start+3);
  }
}
function dialAndFasteners(batch) {
  const x = 7.58, z = -2.67, b = deckHeight - deckTilt*z;
  const specs = [
    [.495,b+.006,'#68776a'],[.495,b+.045,'#a3b1a1'],[.456,b+.066,'#e1e6d6'],
    [.413,b+.069,'#6b796d'],[.391,b+.12,'#69766c'],
    [.424,b+.145,'#c5cfbf'],[.424,b+.40,'#84998a'],
    [.416,b+.438,'#d5dfcf'],[.37,b+.467,'#aab6a4'],[.34,b+.468,'#516651']
  ];
  let last;
  for (const [r,y,color] of specs) {
    const rib = y===b+.145 || y===b+.40 ? .027 : 0;
    const ring = circularRing(x,z,y,r,96,rib);
    if (last) {
      if (y === b+.40) knurledBand(batch,last,ring,color);
      else band(batch,last,ring,color,0);
    }
    last=ring;
  }
  lid(batch,last,x,z,b+.468,0,'#81957c');
  // Recessed indicator on the brushed top face.
  const tick = rectangle(.045,.164,.017,b+.471,x,z-.205,0,2);
  lid(batch,tick,x,z-.205,b+.471,0,'#e1e4cd');
  for (const cx of [-8.17,8.17]) {
    for (const cz of [-3.175,3.175]) {
      const h=deckHeight+.013-deckTilt*cz;
      const edge=circularRing(cx,cz,h+.008,.077,12);
      const inner=circularRing(cx,cz,h+.015,.059,12);
      band(batch,edge,inner,'#738473',0);
      lid(batch,inner,cx,cz,h+.015,0,'#a8b7a5');
      const socket=circularRing(cx,cz,h+.017,.028,6);
      lid(batch,socket,cx,cz,h+.017,0,'#667968');
    }
  }
}

function shadow() {
  const canvas=document.createElement('canvas');
  canvas.width=640; canvas.height=320;
  const c=canvas.getContext('2d');
  const groundWidth=22.5, groundDepth=11.25, unit=canvas.width/groundWidth;
  const draw=(blur,dx,dz,extent,alpha)=>{
    const w=(width+extent)*unit, h=(depth+extent)*unit;
    c.filter=`blur(${blur}px)`;
    c.fillStyle=`rgba(43,60,46,${alpha})`;
    c.beginPath();
    c.roundRect((canvas.width-w)/2+dx*unit,(canvas.height-h)/2+dz*unit,w,h,.39*unit);
    c.fill();
  };
  draw(17,.2,.36,-.13,.23);
  draw(6,.10,.15,-.24,.28);
  draw(2,.045,.055,-.45,.35);
  const texture=new THREE.CanvasTexture(canvas);
  texture.colorSpace=THREE.SRGBColorSpace;
  const material=new THREE.MeshBasicMaterial({map:texture,transparent:true,depthWrite:false,toneMapped:false});
  const plane=new THREE.Mesh(new THREE.PlaneGeometry(groundWidth,groundDepth),material);
  plane.rotation.x=-Math.PI/2;
  plane.position.y=-.005;
  plane.renderOrder=-1;
  return plane;
}

export function createKeyboard() {
  const group = new THREE.Group();
  const shell = new Batch(), fixed = new Batch(), caps = new Batch(), legends = new Batch();
  const {texture,tiles} = makeInk();
  const moving = new Map(), perKey = [];
  const batches = [fixed,caps,legends];
  housing(shell);
  dialAndFasteners(shell);
  for (const key of keys) {
    const deck = deckHeight - deckTilt * key.z;
    const starts = batches.map(batch=>batch.indices.length);
    keyHousing(fixed,key,deck);
    const capStart=caps.size, inkStart=legends.size;
    cap(caps,legends,key,tiles.get(key.code),deck);
    perKey.push(batches.map((batch,i)=>[starts[i],batch.indices.length]));
    moving.set(key.code,{capStart,capEnd:caps.size,inkStart,inkEnd:legends.size,depth:0});
  }
  const shellMat=new THREE.MeshStandardMaterial({vertexColors:true,roughness:.51,metalness:.17});
  const plastic=new THREE.MeshLambertMaterial({vertexColors:true});
  const print=new THREE.MeshBasicMaterial({map:texture,transparent:true,depthWrite:false,toneMapped:false});
  const capMesh=caps.mesh(plastic,true), inkMesh=legends.mesh(print,true);
  const capPosition=capMesh.geometry.attributes.position, inkPosition=inkMesh.geometry.attributes.position;
  const capRest=capPosition.array.slice(), inkRest=inkPosition.array.slice();
  inkMesh.renderOrder=1;
  group.add(shadow(),shell.mesh(shellMat),fixed.mesh(plastic),capMesh,inkMesh);

  function move(attribute, rest, start, end, amount) {
    for (let i=start*3+1;i<end*3;i+=3) attribute.array[i]=rest[i]-travel*amount;
    attribute.addUpdateRange(start*3,(end-start)*3);
    attribute.needsUpdate=true;
  }
  function setDepth(code, amount) {
    const key=moving.get(code);
    if (!key) return;
    const val=Math.max(0,Math.min(1,amount));
    if (key.depth===val) return;
    key.depth=val;
    move(capPosition,capRest,key.capStart,key.capEnd,val);
    move(inkPosition,inkRest,key.inkStart,key.inkEnd,val);
  }
  function dispose() {
    const materials=new Set();
    for (const obj of group.children) {
      obj.geometry.dispose();
      materials.add(obj.material);
    }
    for (const mat of materials) {
      mat.map?.dispose();
      mat.dispose();
    }
    group.clear();
  }
  // For a partial redraw, submit only the keys whose projected bounds
  // overlap the scissor. Reuse the index buffer and keep the original order.
  const parts = group.children.slice(2).map(({geometry}) => {
    geometry.index.setUsage(THREE.DynamicDrawUsage);
    return {geometry, original:geometry.index.array.slice()};
  });
  let lastSelection=null;
  function cull(visible) {
    const signature=visible?.join(',') ?? null;
    if (signature === lastSelection) return;
    lastSelection=signature;
    for (const [part,{geometry,original}] of parts.entries()) {
      const index=geometry.index;
      let count=0;
      if (visible) {
        for (const key of visible) {
          const [start,end]=perKey[key][part];
          index.array.set(original.subarray(start,end),count);
          count+=end-start;
        }
      } else {
        index.array.set(original);
        count=original.length;
      }
      geometry.setDrawRange(0,count);
      if (count) {
        index.addUpdateRange(0,count);
        index.needsUpdate=true;
      }
    }
  }
  return {group,setDepth,width,depth,dispose,cull};
}
