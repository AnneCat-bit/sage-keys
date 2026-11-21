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
const sound = createSound(prefs, message => { byId('audio-status').textContent = message; },hasFocus);
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
soundButton.onclick = ()=>{
  if (prefs.volume === 0) { prefs.volume=55; prefs.muted=false; }
  else prefs.muted=!prefs.muted;
  sound.sync(); syncControls(); save();
};
byId('volume').oninput = event=>{
  prefs.volume=event.target.valueAsNumber;
  if (prefs.volume>0) prefs.muted=false;
  sound.sync(); syncControls(); save();
};
byId('tone').onchange = event=>{
  sound.halt(); prefs.tone=event.target.value;
  sound.sync(); save(); sound.play('KeyA',true);
};
byId('audition').onclick = ()=>{
  if (prefs.muted || prefs.volume===0) {
    byId('audio-status').textContent='請開啟聲音並調高音量後試聽。'; return;
  }
  sound.play('KeyA',true);
};
byId('quality').onchange = event=>{ prefs.quality=event.target.value; view.setQuality(prefs.quality); save(); };
byId('angle').onclick = ()=>view.selectView('angle');
byId('top').onclick = ()=>view.selectView('top');
byId('zoom-in').onclick = ()=>view.adjustZoom(.1);
byId('zoom-out').onclick = ()=>view.adjustZoom(-.1);
byId('reset').onclick = ()=>view.reset();

// The browser owns text entry, composition and all shortcuts. Only physical codes
// are routed to the model. No code copies a keystroke into the textarea.
function onDown(event) {
  const doc=event.currentTarget;
  if ((doc===document && info.open) || !doc.hasFocus() || doc.hidden || event.repeat) return;
  if (view.key(event.code,true)) sound.play(event.code);
}
function onUp(event) {
  view.key(event.code,false);
  if (event.code === 'MetaLeft' || event.code === 'MetaRight') view.releaseChord();
}
const ime = byId('ime');
writing.addEventListener('compositionstart',()=>{ime.textContent='正在選字…';});
writing.addEventListener('compositionend',()=>{ime.textContent='支援中文輸入法';});
writing.addEventListener('blur',()=>{ime.textContent='支援中文輸入法';});
function syncFocus() {
  const active = hasFocus();
  view.setActive(active);
  if (!active) sound.halt();
}
function bindWindow(win) {
  const doc=win.document;
  const listeners=[[win,'blur',syncFocus],[win,'focus',syncFocus],[doc,'visibilitychange',syncFocus],
    [doc,'keydown',onDown],[doc,'keyup',onUp]];
  for (const [target,type,handler] of listeners) target.addEventListener(type,handler);
  return ()=>{for (const [target,type,handler] of listeners) target.removeEventListener(type,handler);};
}
bindWindow(window);
floating=createFloating({
  host,button:byId('float-mode'),view,bind:bindWindow,
  refresh(){syncControls();syncFocus();},
  toggleMute(){soundButton.click();},
  toggleEco(){
    prefs.quality=prefs.quality==='eco' ? 'standard' : 'eco';
    view.setQuality(prefs.quality);syncControls();save();
  },
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
