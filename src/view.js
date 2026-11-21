import { keys } from './layout.js';

const shape = { width: 16.95, depth: 6.94 };
const preset = { yaw: -.24, pitch: .80 };
const clamp = (value, low, high) => Math.max(low, Math.min(value, high));

function makeFlat(host) {
  const board = document.createElement('div');
  board.className = 'fallback-board';
  const caps = new Map();
  for (const key of keys) {
    const cap = document.createElement('i');
    cap.textContent = key.label;
    cap.dataset.tone = key.tone;
    cap.style.left = (50 + (key.x - key.w / 2 + .025) / shape.width * 100) + '%';
    cap.style.top = (50 + (key.z - .46) / shape.depth * 100) + '%';
    cap.style.width = ((key.w - .05) / shape.width * 100) + '%';
    cap.style.height = (0.91 / shape.depth * 100) + '%';
    board.append(cap);
    caps.set(key.code, cap);
  }
  host.replaceChildren(board);
  return {
    move(code, down) { caps.get(code)?.classList.toggle('is-down', down > .4); },
    draw(_, __, zoom) { board.style.setProperty('--scale', zoom); }
  };
}

async function makeScene(host, onLost) {
  const canvas = document.createElement('canvas');
  const options = {alpha:true, antialias:true, powerPreference:'low-power', stencil:false, preserveDrawingBuffer:true};
  const context = canvas.getContext('webgl2',options) || canvas.getContext('webgl',options);
  if (!context) throw Error('WebGL unavailable');
  const [THREE, { createKeyboard }] = await Promise.all([
    import('../assets/three.module.min.js'), import('./model.js')
  ]);
  const renderer = new THREE.WebGLRenderer({canvas,context,...options});
  const scene = new THREE.Scene();
  const camera = new THREE.OrthographicCamera(-10,10,5,-5,.1,100);
  scene.add(new THREE.HemisphereLight(0xfffefa, 0xb2bbba, 1.70));
  const light = new THREE.DirectionalLight(0xfffcf5, 1.83);
  light.position.set(-6, 10, 5);
  scene.add(light);
  const fill = new THREE.DirectionalLight(0xe4efef, .45);
  fill.position.set(6, 5, -4);
  scene.add(fill);
  const model = createKeyboard();
  scene.add(model.group);
  renderer.setClearColor(0x000000,0);
  renderer.domElement.addEventListener('webglcontextlost', event => {
    event.preventDefault();
    model.dispose();
    renderer.dispose();
    onLost();
  }, { once:true });
  host.replaceChildren(renderer.domElement);
  const byCode = new Map(keys.map((key,i)=>[key.code,i]));
  const changed = new Set();
  const point = new THREE.Vector3();
  let previousWidth, previousHeight, previousDpr, previousPose;
  // Keep the static frame and redraw only the projected key bounds during a
  // press. The scene still resolves depth/occlusion inside the scissor box.
  let footprint=[];
  function keyBounds(key,width,height) {
    let left=width, bottom=height, right=0, top=0;
      for (const x of [key.x-key.w/2,key.x+key.w/2]) {
        for (const z of [key.z-.55,key.z+.55]) {
          for (const y of [.35,1.55]) {
            point.set(x,y,z).project(camera);
            const px=(point.x+1)*width/2, py=(point.y+1)*height/2;
            left=Math.min(left,px); right=Math.max(right,px);
            bottom=Math.min(bottom,py); top=Math.max(top,py);
          }
        }
      }
    return [Math.floor(left)-3,Math.floor(bottom)-3,Math.ceil(right)+3,Math.ceil(top)+3];
  }
  return {
    move(code,value) { model.setDepth(code,value); changed.add(code); },
    invalidate() { previousPose=null; },
    draw(yaw, pitch, zoom, quality) {
      const width = host.clientWidth, height = host.clientHeight;
      if (!width || !height) return;
      const dpr = Math.min(host.ownerDocument.defaultView.devicePixelRatio || 1, quality === 'eco' ? 1.25 : 1.75);
      const pose = [width,height,dpr,yaw,pitch,zoom].join(',');
      if (pose===previousPose && !changed.size) return;
      if (width !== previousWidth || height !== previousHeight || dpr !== previousDpr) {
        renderer.setPixelRatio(dpr);
        renderer.setSize(width, height, false);
        previousWidth = width; previousHeight = height; previousDpr = dpr;
      }
      const aspect = width / height;
      const span = Math.max(9.35, (width < 620 ? 19.5 : 20) / aspect) / zoom;
      camera.left = -span * aspect / 2;
      camera.right = -camera.left;
      camera.top = span / 2;
      camera.bottom = -camera.top;
      camera.updateProjectionMatrix();
      const radius = 26, centerY = width < 620 && host.ownerDocument === document ? -.12 : .38;
      camera.position.set(radius*Math.sin(yaw)*Math.cos(pitch),
        centerY+radius*Math.sin(pitch),radius*Math.cos(yaw)*Math.cos(pitch));
      camera.lookAt(0, centerY, 0);
      if (pose===previousPose) {
        const dirty=[...changed].map(code=>footprint[byCode.get(code)]);
        const l=Math.max(0,Math.min(...dirty.map(box=>box[0])));
        const b=Math.max(0,Math.min(...dirty.map(box=>box[1])));
        const r=Math.min(width,Math.max(...dirty.map(box=>box[2])));
        const t=Math.min(height,Math.max(...dirty.map(box=>box[3])));
        renderer.setScissor(l,b,Math.max(0,r-l),Math.max(0,t-b));
        renderer.setScissorTest(true);
        const visible=[];
        for (let i=0;i<footprint.length;i++) {
          const [left,bottom,right,top]=footprint[i];
          if (left<=r && right>=l && bottom<=t && top>=b) visible.push(i);
        }
        model.cull(visible);
      } else {
        camera.updateMatrixWorld();
        footprint=keys.map(k=>keyBounds(k,width,height));
        model.cull(null);
      }
      renderer.render(scene, camera);
      renderer.setScissorTest(false);
      previousPose=pose;
      changed.clear();
    }
  };
}

export function createView(host, quality, onChange) {
  const supported = new Set(keys.map(key => key.code));
  const pressed = new Set(), unpainted = new Set(), moving = new Map(), depths = new Map();
  const touches = new Map();
  let backend, flat = false, yaw = preset.yaw, pitch = preset.pitch, zoom = 1, view = 'angle';
  let surface=host.ownerDocument.defaultView;
  let raf=0, last=-Infinity, active=!document.hidden && document.hasFocus();
  let observer;
  function drawVisible() {
    if (backend && !surface.document.hidden) backend.draw(yaw,pitch,zoom,quality);
  }
  function notify() { onChange({ flat, zoom, view, active }); }
  function frame(stamp) {
    raf = 0;
    if (!backend || surface.document.hidden) return;
    const elapsed = stamp-last;
    const period = quality === 'eco' ? 1000/30 : 1000/60;
    if (elapsed < period-.6) { raf = surface.requestAnimationFrame(frame); return; }
    // rAF timestamps pace frames on the canvas owner. Key events and
    // rebound progress use the same clock regardless of document.
    const now=performance.now();
    for (const [code, released] of moving) {
      if (unpainted.has(code)) { moving.set(code, now); continue; }
      const depth = Math.max(0, 1-(now-released)/105)**2;
      backend.move(code, depth);
      if (depth === 0) { moving.delete(code); depths.delete(code); }
      else depths.set(code, depth);
    }
    backend.draw(yaw, pitch, zoom, quality);
    unpainted.clear();
    last = stamp;
    if (moving.size) raf = surface.requestAnimationFrame(frame);
  }
  function requestDraw() {
    if (backend && !surface.document.hidden && !raf) raf = surface.requestAnimationFrame(frame);
  }
  function fallback() {
    flat = true;
    view = 'top';
    backend = makeFlat(host);
    for (const code of pressed) backend.move(code,1);
    notify(); requestDraw();
  }
  function setActive(value) {
    if (active === value) return;
    active = value;
    if (active) { last = -Infinity; requestDraw(); }
    else {
      if (raf) surface.cancelAnimationFrame(raf);
      raf = 0;
      for (const code of depths.keys()) backend?.move(code, 0);
      if (depths.size) drawVisible();
      pressed.clear(); unpainted.clear(); moving.clear(); depths.clear(); touches.clear();
      host.classList.remove('dragging');
    }
    notify();
  }
  function setZoom(value) {
    zoom = clamp(value,.7,1.6); notify(); requestDraw();
  }
  function selectView(next) {
    if (flat) return;
    view = next;
    yaw = next === 'top' ? 0 : preset.yaw;
    pitch = next === 'top' ? Math.PI/2-.001 : preset.pitch;
    notify(); requestDraw();
  }
  function delta(a,b) { return Math.hypot(a.x-b.x,a.y-b.y); }
  host.addEventListener('pointerdown', e => {
    if (e.button !== 0) return;
    host.setPointerCapture(e.pointerId);
    touches.set(e.pointerId, {x:e.clientX,y:e.clientY});
    host.classList.add('dragging');
  });
  host.addEventListener('pointermove', e => {
    const old = touches.get(e.pointerId);
    if (!old) return;
    const point = {x:e.clientX,y:e.clientY};
    const other = [...touches].find(([id]) => id !== e.pointerId)?.[1];
    if (other) {
      const distance = delta(old,other);
      if (distance > 1) setZoom(zoom*delta(point,other)/distance);
    } else if (!flat && (old.x !== point.x || old.y !== point.y)) {
      yaw -= (point.x-old.x)*.009;
      pitch = clamp(pitch+(point.y-old.y)*.008,.19,Math.PI/2-.01);
      view = 'custom'; notify(); requestDraw();
    }
    touches.set(e.pointerId, point);
  });
  host.addEventListener('lostpointercapture', e => {
    touches.delete(e.pointerId);
    if (!touches.size) host.classList.remove('dragging');
  });
  host.addEventListener('wheel', e => {
    if (e.ctrlKey || e.metaKey || e.altKey || e.shiftKey) return;
    e.preventDefault();
    const factor = e.deltaMode === 1 ? 16 : e.deltaMode === 2 ? host.clientHeight : 1;
    setZoom(zoom*Math.exp(-clamp(e.deltaY*factor,-400,400)*.0014));
  }, {passive:false});
  function refreshSize() {
    if (active) requestDraw(); else drawVisible();
  }
  function refreshSurface() {
    // A previously requested frame can be parked while this document is
    // hidden. On display/ownership changes start from a complete frame.
    if (raf) surface.cancelAnimationFrame(raf);
    raf=0; last=-Infinity;
    backend?.invalidate?.();
    if (!surface.document.hidden) {
      drawVisible();
      if (moving.size) requestDraw();
    }
  }
  function rehost() {
    observer?.disconnect();
    if (raf) surface.cancelAnimationFrame(raf);
    raf=0; last=-Infinity;
    for (const code of depths.keys()) backend?.move(code,0);
    depths.clear(); pressed.clear(); moving.clear(); unpainted.clear(); touches.clear();
    surface=host.ownerDocument.defaultView;
    observer=new surface.ResizeObserver(refreshSize);
    observer.observe(host);
    refreshSurface();
  }
  rehost();
  makeScene(host, fallback).then(scene => {
    backend = scene;
    for (const [code,depth] of depths) backend.move(code,depth);
    // Render the initial static pose even in an unfocused visible preview.
    if (!active) drawVisible();
    notify(); requestDraw();
  }).catch(fallback);
  return {
    key(code, down) {
      if (!supported.has(code)) return false;
      if (down) {
        if (pressed.has(code)) return false;
        pressed.add(code); unpainted.add(code); moving.delete(code); depths.set(code,1);
        backend?.move(code,1);
      } else {
        if (!pressed.delete(code)) return false;
        moving.set(code,performance.now());
      }
      requestDraw();
      return true;
    },
    releaseAll() {
      for (const code of pressed) this.key(code,false);
    },
    releaseChord() {
      for (const code of pressed) if (!/^(Meta|Shift|Alt|Control)/.test(code)) this.key(code,false);
    },
    selectView, setZoom, setActive, rehost, refreshSurface,
    adjustZoom(factor) { setZoom(Math.round((zoom+factor)*100)/100); },
    reset() { setZoom(1); selectView('angle'); },
    setQuality(value) { quality = value; requestDraw(); }
  };
}
