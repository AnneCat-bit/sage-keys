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
  const [THREE, { createKeyboard }] = await Promise.all([
    import('../assets/three.module.min.js'), import('./model.js')
  ]);
  const renderer = new THREE.WebGLRenderer({
    alpha: true, antialias: true, powerPreference: 'low-power', stencil: false
  });
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
  let previousWidth, previousHeight, previousDpr;
  return {
    move: model.setDepth,
    draw(yaw, pitch, zoom, quality) {
      const width = host.clientWidth, height = host.clientHeight;
      if (!width || !height) return;
      const dpr = Math.min(devicePixelRatio || 1, quality === 'eco' ? 1.25 : 1.75);
      if (width !== previousWidth || height !== previousHeight || dpr !== previousDpr) {
        renderer.setPixelRatio(dpr);
        renderer.setSize(width, height, false);
        previousWidth = width; previousHeight = height; previousDpr = dpr;
      }
      const aspect = width / height;
      const span = Math.max(9.35, (width < 620 ? 18.5 : 20) / aspect) / zoom;
      camera.left = -span * aspect / 2;
      camera.right = -camera.left;
      camera.top = span / 2;
      camera.bottom = -camera.top;
      camera.updateProjectionMatrix();
      const radius = 26, centerY = .38;
      camera.position.set(radius*Math.sin(yaw)*Math.cos(pitch),
        centerY+radius*Math.sin(pitch),radius*Math.cos(yaw)*Math.cos(pitch));
      camera.lookAt(0, centerY, 0);
      renderer.render(scene, camera);
    }
  };
}

export function createView(host, quality, onChange) {
  const supported = new Set(keys.map(key => key.code));
  const pressed = new Set(), unpainted = new Set(), moving = new Map(), depths = new Map();
  const touches = new Map();
  let backend, flat = false, yaw = preset.yaw, pitch = preset.pitch, zoom = 1, view = 'angle';
  let raf = 0, last = -Infinity, active = !document.hidden && document.hasFocus();
  function notify() { onChange({ flat, zoom, view, active }); }
  function frame(now) {
    raf = 0;
    if (!backend || !active || document.hidden) return;
    const elapsed = now-last;
    const period = quality === 'eco' ? 1000/30 : 1000/60;
    if (elapsed < period-.6) { raf = requestAnimationFrame(frame); return; }
    for (const [code, released] of moving) {
      if (unpainted.has(code)) { moving.set(code, now); continue; }
      const depth = Math.max(0, 1-(now-released)/105)**2;
      backend.move(code, depth);
      if (depth === 0) { moving.delete(code); depths.delete(code); }
      else depths.set(code, depth);
    }
    backend.draw(yaw, pitch, zoom, quality);
    unpainted.clear();
    last = now;
    if (moving.size) raf = requestAnimationFrame(frame);
  }
  function requestDraw() {
    if (backend && active && !document.hidden && !raf) raf = requestAnimationFrame(frame);
  }
  function fallback() {
    flat = true;
    view = 'top';
    backend = makeFlat(host);
    for (const code of pressed) backend.move(code,1);
    notify(); requestDraw();
  }
  function setActive(value) {
    active = value;
    if (active) { last = -Infinity; requestDraw(); }
    else {
      if (raf) cancelAnimationFrame(raf);
      raf = 0;
      for (const code of depths.keys()) backend?.move(code, 0);
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
  new ResizeObserver(requestDraw).observe(host);
  makeScene(host, fallback).then(scene => {
    backend = scene;
    for (const [code,depth] of depths) backend.move(code,depth);
    // Render the initial static pose even in an unfocused visible preview.
    if (!document.hidden && !active) backend.draw(yaw,pitch,zoom,quality);
    notify(); requestDraw();
  }).catch(fallback);
  return {
    key(code, down) {
      if (!active || !supported.has(code)) return false;
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
    releaseChord() {
      for (const code of pressed) if (!/^(Meta|Shift|Alt|Control)/.test(code)) this.key(code,false);
    },
    selectView, setZoom, setActive,
    adjustZoom(factor) { setZoom(Math.round((zoom+factor)*100)/100); },
    reset() { setZoom(1); selectView('angle'); },
    setQuality(value) { quality = value; requestDraw(); }
  };
}
