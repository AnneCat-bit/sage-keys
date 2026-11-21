import { createFloating } from './floating.js';
import { createView } from './view.js';
import { createSound } from './sound.js';

const byId = id => document.getElementById(id);
const prefKey = 'sage-keys.preferences.v1';
const prefs = {volume:55,muted:false,tone:'rainy',quality:'eco'};
try {
  const saved = JSON.parse(localStorage.getItem(prefKey)) || {};
  if (Number.isInteger(saved.volume) && saved.volume >= 0 && saved.volume <= 100) prefs.volume=saved.volume;
  if (typeof saved.muted === 'boolean') prefs.muted=saved.muted;
  if (['rainy','topre','brown'].includes(saved.tone)) prefs.tone=saved.tone;
  if (saved.quality === 'standard') prefs.quality='standard';
} catch { /* Storage can be disabled by the browser. */ }
function save() { try { localStorage.setItem(prefKey, JSON.stringify(prefs)); } catch {} }
const writing = byId('writing'), soundButton = byId('sound-toggle'), info = byId('info');
const host=byId('viewport');
let floating;
function hasFocus() {
  const mini=floating?.window?.document;
  return (!document.hidden && document.hasFocus()) || !!(mini && !mini.hidden && mini.hasFocus());
}
const sound = createSound(prefs, message => { byId('audio-status').textContent = message; });
const view = createView(host,prefs.quality,state=>{
  byId('model-mode').textContent = state.flat ? '2D VIEW' : 'MODEL VIEW';
  host.setAttribute('aria-label', state.flat ? 'Sage 75 二維省資源鍵盤' : '可旋轉的 Sage 75 立體鍵盤');
  byId('gesture').textContent = state.flat ? '平面模式' : '拖曳旋轉';
  byId('zoom').textContent = Math.round(state.zoom*100)+'%';
  byId('zoom-out').disabled = state.zoom <= .7;
  byId('zoom-in').disabled = state.zoom >= 1.6;
  byId('angle').disabled = state.flat;
  byId('top').disabled = state.flat;
  byId('angle').setAttribute('aria-pressed',state.view === 'angle');
  byId('top').setAttribute('aria-pressed',state.view === 'top');
  byId('live-state').textContent = state.active ? '互動已就緒' : '已暫停';
});
function syncControls() {
  floating?.sync(prefs);
  const audible = !prefs.muted && prefs.volume > 0;
  byId('tone').value = prefs.tone;
  byId('quality').value = prefs.quality;
  byId('volume').value = prefs.volume;
  byId('volume').style.setProperty('--fill',prefs.volume+'%');
  byId('vol-value').value = prefs.volume+'%';
  soundButton.setAttribute('aria-pressed',audible);
  soundButton.querySelector('use').setAttribute('href',audible ? '#i-volume' : '#i-mute');
  soundButton.querySelector('span').textContent = audible ? '聲音開啟' : '已靜音';
}
syncControls();
function toggleMute() {
  if (prefs.volume === 0) { prefs.volume=55; prefs.muted=false; }
  else prefs.muted=!prefs.muted;
  sound.sync(); syncControls(); save();
  if (!prefs.muted) sound.prepare();
}
soundButton.onclick=toggleMute;
byId('volume').oninput = event=>{
  prefs.volume=event.target.valueAsNumber;
  if (prefs.volume>0) prefs.muted=false;
  sound.sync(); syncControls(); save();
};
byId('tone').onchange = event=>{
  sound.halt(); prefs.tone=event.target.value;
  sound.sync(); save(); sound.play('KeyA');
};
byId('audition').onclick = ()=>{
  if (prefs.muted || prefs.volume===0) {
    byId('audio-status').textContent='請開啟聲音並調高音量後試聽。'; return;
  }
  sound.play('KeyA');
};
function setQuality(value) {
  prefs.quality=value;
  view.setQuality(value);
  syncControls();
  save();
}
byId('quality').onchange=event=>setQuality(event.target.value);
byId('angle').onclick = ()=>view.selectView('angle');
byId('top').onclick = ()=>view.selectView('top');
byId('zoom-in').onclick = ()=>view.adjustZoom(.1);
byId('zoom-out').onclick = ()=>view.adjustZoom(-.1);
byId('reset').onclick = ()=>view.reset();

// The browser owns text entry, composition and all shortcuts. Only physical codes
// are routed to the model. No code copies a keystroke into the textarea.
let inputDocument;
function onDown(event) {
  const doc=event.currentTarget;
  if (!event.isTrusted || doc.hidden || (doc===document && info.open) || event.repeat) return;
  // A key delivered by the browser is current evidence of input ownership,
  // even when a focus notification from the other window arrived late.
  cancelFocusCheck();
  if (inputDocument && inputDocument!==doc) view.releaseAll();
  inputDocument=doc;
  view.setActive(true);
  if (view.key(event.code,true)) sound.play(event.code);
}
function onUp(event) {
  if (!event.isTrusted) return;
  view.key(event.code,false);
  if (event.code === 'MetaLeft' || event.code === 'MetaRight') view.releaseChord();
}
const ime = byId('ime');
writing.addEventListener('compositionstart',()=>{ime.textContent='正在選字…';});
writing.addEventListener('compositionend',()=>{ime.textContent='支援中文輸入法';});
writing.addEventListener('blur',()=>{ime.textContent='支援中文輸入法';});
let focusCheck;
function cancelFocusCheck() {
  if (focusCheck) focusCheck.win.clearTimeout(focusCheck.id);
  focusCheck=null;
}
function syncFocus() {
  cancelFocusCheck();
  const active = hasFocus();
  view.setActive(active);
  if (!active) sound.halt();
}
function bindWindow(win) {
  const doc=win.document;
  function onBlur() {
    if (inputDocument===doc) view.releaseAll();
    cancelFocusCheck();
    // blur can precede the other Sage window's focus. Reconcile the pair
    // after that handoff, using the visible window's event loop.
    const clock=floating?.window || window;
    focusCheck={win:clock,id:clock.setTimeout(syncFocus,0)};
  }
  function onVisibility() {
    if (doc===host.ownerDocument) view.refreshSurface();
    if (doc.hidden) onBlur(); else syncFocus();
  }
  const listeners=[[win,'blur',onBlur],[win,'focus',syncFocus],[doc,'visibilitychange',onVisibility],
    [doc,'keydown',onDown],[doc,'keyup',onUp]];
  for (const [target,type,handler] of listeners) target.addEventListener(type,handler);
  return ()=>{
    for (const [target,type,handler] of listeners) target.removeEventListener(type,handler);
    if (inputDocument===doc) inputDocument=null;
  };
}
bindWindow(window);
writing.addEventListener('pointerdown',sound.prepare);
floating=createFloating({
  host,button:byId('float-mode'),view,bind:bindWindow,
  refresh(){syncControls();syncFocus();},
  prepare:sound.prepare, toggleMute,
  toggleEco(){setQuality(prefs.quality==='eco' ? 'standard' : 'eco');},
  unavailable(){showInfo('float-help','懸浮模式暫不可用');}
});
window.addEventListener('pagehide',()=>{
  view.setActive(false); sound.halt();
  writing.value=''; // Also clear the document retained by the back/forward cache.
});
window.addEventListener('pageshow',event=>{ if (event.persisted) writing.value=''; syncFocus(); });
function showInfo(id,title) {
    const template=byId(id);
    byId('info-title').textContent=title;
    byId('info-body').replaceChildren(template.content.cloneNode(true));
    info.setAttribute('aria-labelledby','info-title');
    info.showModal();
}
for (const button of document.querySelectorAll('[data-dialog]')) {
  button.onclick=()=>showInfo(button.dataset.dialog,button.textContent.trim());
}
info.querySelector('.close').onclick=()=>info.close();
info.addEventListener('click',event=>{
  const rect=info.getBoundingClientRect();
  if (event.target===info && (event.clientX<rect.left || event.clientX>rect.right || event.clientY<rect.top || event.clientY>rect.bottom)) info.close();
});
