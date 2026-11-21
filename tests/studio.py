"""Cloud browser checks. Run against a served project URL, including its trailing slash."""
import argparse
import json
import shutil
import time
from pathlib import Path
from urllib.parse import urlsplit
from playwright.sync_api import sync_playwright
from browser_support import configure_transport

parser = argparse.ArgumentParser()
parser.add_argument('url')
parser.add_argument('--capture', type=Path)
parser.add_argument('--fixture', action='store_true', help='Fulfill project URL from this checkout for pre-deployment QA')
parser.add_argument('--system-https', action='store_true', help='Use system CA trust for public HTTPS GETs in a cloud proxy environment')
args = parser.parse_args()
assert args.url.endswith('/')
checks = []

def passed(name):
    checks.append(name)
    print('PASS',name,flush=True)

# Observe the rendering and audio APIs only in the test context.
instrument = """
window.qa = {frames:[],draws:0,sounds:[],uploads:[],active:0,maxActive:0};
const raf = window.requestAnimationFrame.bind(window);
let timestamp = -1;
window.requestAnimationFrame = cb => raf(t=>{timestamp=t;cb(t)});
for(const name of ['WebGLRenderingContext','WebGL2RenderingContext']){
 const proto=window[name]?.prototype;
 if(!proto) continue;
 const draw=proto.drawElements;
 proto.drawElements=function(...args){
   qa.draws++;
   if(qa.frames.at(-1)!==timestamp) qa.frames.push(timestamp);
   return draw.apply(this,args);
 };
 const sub=proto.bufferSubData;
 proto.bufferSubData=function(...args){qa.uploads.push([args[1],args[4]]);return sub.apply(this,args)};
}
const src=AudioBufferSourceNode.prototype, start=src.start, stop=src.stop;
const target=AudioParam.prototype.setTargetAtTime;
AudioParam.prototype.setTargetAtTime=function(v,...args){qa.gain=v;return target.call(this,v,...args)};
const live=new Set();
function remove(voice){live.delete(voice);qa.active=live.size}
src.start=function(t,off,len){
 const a=this.buffer.getChannelData(0);
 const first=Math.round(off*this.buffer.sampleRate), n=Math.round(len*this.buffer.sampleRate);
 let energy=0;
 for(let i=first;i<first+n;i++) energy+=a[i]*a[i];
 qa.sounds.push([off,len,this.buffer.length,energy/n]);
 live.add(this);qa.active=live.size;qa.maxActive=Math.max(qa.maxActive,live.size);
 this.addEventListener('ended',()=>remove(this),{once:true});
 return start.call(this,t,off,len);
};
src.stop=function(...args){remove(this);return stop.apply(this,args)};
"""
with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path=shutil.which('chromium'),args=['--use-angle=swiftshader','--enable-unsafe-swiftshader','--disable-dev-shm-usage'])
    ctx = browser.new_context(viewport={'width':1440,'height':960},locale='zh-HK')
    configure_transport(ctx,args.url,args.fixture,args.system_https)
    ctx.add_init_script(instrument)
    page=ctx.new_page()
    errors=[]
    requests=[]
    page.on('pageerror',lambda e: errors.append(str(e)))
    page.on('request',lambda r: requests.append([r.method,r.url,r.post_data]))
    def wait_for(check, arg=None):
        deadline=time.monotonic()+15
        while not page.evaluate(check,arg):
            if time.monotonic()>deadline: raise AssertionError(check)
            page.wait_for_timeout(80)
    def ready():
        wait_for("document.querySelector('#viewport canvas') && qa.draws>=5")
        page.evaluate('document.fonts.ready')
    assert page.goto(args.url).ok
    ready()
    passed('3D starts under project subpath')
    if args.capture:
        args.capture.mkdir(exist_ok=True,parents=True)
        page.screenshot(path=str(args.capture/'studio.png'),full_page=True,animations='disabled')

    field=page.locator('#writing')
    field.click()
    page.keyboard.type('Sage Keys',delay=65)
    assert field.input_value()=='Sage Keys'
    page.keyboard.down('Shift')
    page.keyboard.down('KeyA')
    page.keyboard.down('KeyS')
    page.wait_for_timeout(120)
    down=page.evaluate('qa.uploads.length')
    page.keyboard.up('KeyS')
    wait_for('n=>qa.uploads.length>n',arg=down)
    page.keyboard.up('KeyA')
    page.keyboard.up('Shift')
    assert field.input_value()=='Sage KeysAS'
    # Check distinct movable ranges and exact return geometrically as well.
    assert page.evaluate("""async()=>{
      const {createKeyboard}=await import('./src/model.js');
      const model=createKeyboard();
      const att=model.group.children[3].geometry.attributes.position;
      const original=att.array.slice();
      const changed=new Set();
      model.setDepth('KeyA',1);
      for(let i=0;i<original.length;i++)if(att.array[i]!==original[i]) changed.add(i);
      model.setDepth('ShiftLeft',1); model.setDepth('KeyA',0);
      let shiftCount=0;
      for(let i=0;i<original.length;i++) if(att.array[i]!==original[i]){
        if(changed.has(i)) return false;
        shiftCount++;
      }
      model.setDepth('ShiftLeft',0);
      const ok=changed.size>0 && shiftCount>0 && original.every((v,i)=>v===att.array[i]);
      model.dispose();return ok;
    }""")
    passed('English, physical Shift chord, independent cap travel and return')

    page.keyboard.press('Control+a')
    assert field.evaluate('(e)=>e.selectionEnd-e.selectionStart')==len(field.input_value())
    page.keyboard.press('Backspace')
    cdp=ctx.new_cdp_session(page)
    for draft,commit in [('onf','你'),('ho','好'),('wen','文')]:
        cdp.send('Input.imeSetComposition',{'text':draft,'selectionStart':len(draft),'selectionEnd':len(draft)})
        assert page.locator('#ime').inner_text()=='正在選字…'
        cdp.send('Input.insertText',{'text':commit})
    assert field.input_value()=='你好文'
    cdp.send('Input.imeSetComposition',{'text':'abc','selectionStart':3,'selectionEnd':3})
    cdp.send('Input.imeSetComposition',{'text':'','selectionStart':0,'selectionEnd':0})
    assert field.input_value()=='你好文'
    page.keyboard.press('Enter')
    page.keyboard.type('test')
    assert field.input_value()=='你好文\ntest'
    passed('Native editing shortcut, three composition commits, cancelled composition, mixed text')

    for tone in ('rainy','topre','brown'):
        page.locator('#tone').select_option(tone)
        before=page.evaluate('qa.sounds.length')
        page.locator('#audition').click()
        wait_for('n=>qa.sounds.length>n',arg=before)
        field.focus()
        page.keyboard.press('Space')
        page.keyboard.press('Enter')
        page.keyboard.press('Backspace')
        page.wait_for_timeout(100)
        wants=page.evaluate("async(t)=>(await (await fetch('./assets/audio/sprites.json')).json())[t].slice(4)",tone)
        sounds=page.evaluate('qa.sounds.slice(-3)')
        assert [s[:2] for s in sounds]==wants and all(s[3]>.0001 for s in sounds),sounds
    assert len(set(page.evaluate('qa.sounds.map(s=>s[2])')))==3
    page.locator('#volume').focus()
    page.keyboard.press('Home')
    page.keyboard.press('ArrowRight')
    assert page.evaluate('Math.abs(qa.gain-.01)<.0001')
    page.keyboard.press('End')
    assert page.evaluate('qa.gain===1')
    field.focus()
    page.wait_for_timeout(200)
    prior=page.evaluate('qa.sounds.length')
    for i in range(8): page.keyboard.press('KeyA',delay=40)
    wait_for('n=>qa.sounds.length>=n+8',arg=prior)
    variants=page.evaluate('qa.sounds.slice(-8).map(s=>s[0])')
    assert all(a!=b for a,b in zip(variants,variants[1:]))
    page.keyboard.type('asdfghjkl'*4,delay=0)
    assert page.evaluate('qa.maxActive')<=5
    page.wait_for_timeout(180)
    page.locator('#sound-toggle').click()
    before=page.evaluate('qa.sounds.length')
    field.click()
    page.keyboard.type('muted')
    assert page.evaluate('qa.sounds.length')==before
    passed('All three WAV banks, non-silent special samples, polyphony cap, mute')

    page.locator('#top').click()
    assert page.locator('#top').get_attribute('aria-pressed')=='true'
    page.locator('#zoom-in').click()
    assert page.locator('#zoom').inner_text()=='110%'
    box=page.locator('#viewport').bounding_box()
    x,y=box['x']+box['width']*.5,box['y']+box['height']*.5
    page.mouse.move(x,y);page.mouse.down();page.mouse.move(x+80,y+18,steps=4);page.mouse.up()
    assert page.locator('#top').get_attribute('aria-pressed')=='false'
    page.mouse.wheel(0,-80);page.wait_for_timeout(80)
    assert int(page.locator('#zoom').inner_text().strip('%'))>110
    page.locator('#reset').click()
    assert page.locator('#angle').get_attribute('aria-pressed')=='true'
    assert page.locator('#zoom').inner_text()=='100%'
    page.locator('#quality').select_option('standard')
    passed('Orbit drag, wheel zoom, presets, reset and quality switch')

    page.wait_for_timeout(350)
    before=page.evaluate('qa.frames.length')
    page.wait_for_timeout(1000)
    assert page.evaluate('qa.frames.length')==before
    # Simulate a browser that has lost window focus before emitting blur.
    cdp.send('Emulation.setFocusEmulationEnabled',{'enabled':False})
    page.evaluate("""()=>{Object.defineProperty(document,'hasFocus',{configurable:true,value:()=>false});window.dispatchEvent(new Event('blur'))}""")
    page.evaluate("document.dispatchEvent(new KeyboardEvent('keydown',{code:'KeyQ'}))")
    page.wait_for_timeout(150)
    assert page.locator('#live-state').inner_text()=='已暫停'
    assert page.evaluate('qa.frames.length')==before
    page.evaluate("""()=>{delete document.hasFocus;window.dispatchEvent(new Event('focus'))}""")
    passed('Zero idle frames, simulated window blur pauses drawing and input')

    assert all(r[0]=='GET' and not r[2] and urlsplit(r[1]).netloc==urlsplit(args.url).netloc for r in requests)
    saved=page.evaluate('Object.fromEntries(Object.entries(localStorage))')
    assert set(saved)=={'sage-keys.preferences.v1'}
    assert set(json.loads(next(iter(saved.values()))))=={'volume','muted','tone','quality'}
    assert page.reload().ok
    ready()
    assert field.input_value()==''
    assert page.locator('#tone').input_value()=='brown'
    assert page.locator('#quality').input_value()=='standard'
    page.get_by_role('button',name='錄音來源').click()
    assert page.locator('dialog:modal a').count()==3
    page.keyboard.press('Escape')
    assert not page.locator('dialog').is_visible()
    passed('Local preferences only, same-origin GETs, refresh, credits and native Escape')

    page.set_viewport_size({'width':390,'height':844})
    page.wait_for_timeout(200)
    assert page.evaluate('document.documentElement.scrollWidth===innerWidth')
    if args.capture: page.screenshot(path=str(args.capture/'mobile.png'),full_page=True)
    page.add_init_script("""const get=HTMLCanvasElement.prototype.getContext;
      HTMLCanvasElement.prototype.getContext=function(type,...args){return type.includes('webgl')?null:get.call(this,type,...args)}""")
    assert page.reload().ok
    page.locator('.fallback-board').wait_for()
    assert page.locator('.fallback-board i').count()==82
    field.click()
    page.keyboard.down('a')
    assert page.locator('.fallback-board .is-down').count()==1
    page.evaluate('''() => {
      const cap=document.querySelector('.fallback-board .is-down');
      document.addEventListener('keyup',()=>{window.releaseAt=performance.now();},{once:true});
      const observer=new MutationObserver(()=>{
        if (!cap.classList.contains('is-down')) {
          window.releaseMs=performance.now()-window.releaseAt;
          const [rebound]=cap.getAnimations();
          window.returnDuration=rebound?.effect.getTiming().duration;
          window.flatSettled=rebound?.finished.then(()=>getComputedStyle(cap).transform);
          observer.disconnect();
        }
      });
      observer.observe(cap,{attributes:true,attributeFilter:['class']});
    }''')
    page.keyboard.up('a')
    page.locator('.fallback-board .is-down').wait_for(state='detached',timeout=1000)
    assert page.locator('.fallback-board .is-down').count()==0
    assert page.evaluate('window.releaseMs')<100
    assert page.evaluate('window.returnDuration')==105
    assert page.evaluate('window.flatSettled')=='none'
    print('2D cap released after',round(page.evaluate('window.releaseMs'),1),'ms',flush=True)
    assert field.input_value()=='a'
    passed('Mobile width, WebGL-disabled fallback and physical typing')
    assert not errors,errors
    print(json.dumps({'browser':browser.version,'checks':len(checks),'verified':args.url,'fixture':args.fixture},ensure_ascii=False))
    browser.close()
