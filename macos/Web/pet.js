import {createView} from '../../src/view.js';
import {createSound} from '../../src/sound.js';
import {keys} from '../../src/layout.js';
import rainy from '../../assets/audio/rainy.wav';
import topre from '../../assets/audio/topre.wav';
import brown from '../../assets/audio/brown.wav';
import index from '../../assets/audio/sprites.json';

const banks={rainy,topre,brown};
const audio={index,sample(tone) {
  const bytes=atob(banks[tone]);
  return Uint8Array.from(bytes,c=>c.charCodeAt(0)).buffer;
}};
const prefs={tone:'rainy',volume:55,muted:false,quality:'eco'};
const held=new Set(), allowed=new Set(keys.map(k=>k.code));
const send=(kind,value)=>window.webkit?.messageHandlers.pet?.postMessage({kind,value});
let paused=false, closed=false, pose='angle';
const sound=createSound(prefs,text=>{if(text) send('audio',text);},audio);
const view=createView(document.querySelector('#viewport'),prefs.quality,()=>{},{
  frameRate:q=>q==='eco'?15:30, pixelLimit:q=>q==='eco'?1:1.25,
  ready:flat=>send('ready',flat?'2D':'3D')
});
view.setActive(true);

window.sagePet=Object.freeze({
  // Swift sends a bounded snapshot. No characters or event timestamps cross the bridge.
  keys(codes) {
    if(paused || closed || !Array.isArray(codes)) return;
    const next=new Set(codes.filter(k=>allowed.has(k)));
    for(const k of held) if(!next.has(k)) {view.key(k,false);held.delete(k);}
    for(const k of next) if(!held.has(k)) {
      held.add(k);
      if(view.key(k,true)) void sound.play(k);
    }
  },
  settings(s) {
    if(closed) return;
    if(s.tone!==prefs.tone && Object.hasOwn(banks,s.tone)) {sound.halt();prefs.tone=s.tone;}
    prefs.muted=!!s.muted;
    sound.sync();
    if(s.quality!==prefs.quality) {prefs.quality=s.quality;view.setQuality(prefs.quality);}
    if(s.pose!==pose) {pose=s.pose;view.selectView(pose);}
  },
  pause(value) {
    paused=value;
    if(paused) {held.clear();sound.halt();}
    view.setSuspended(value);
  },
  reset() {
    held.clear();sound.halt();view.setSuspended(true);view.setSuspended(paused);
  },
  close() {
    if(closed) return;
    closed=true;held.clear();view.dispose();return sound.dispose();
  }
});
window.addEventListener('pagehide',()=>window.sagePet.close(),{once:true});
