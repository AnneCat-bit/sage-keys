"""Exercise actual PiP focus, WebGL framebuffer pixels and post-mix audio in headed Chromium."""
import argparse
import base64
import json
import time
from pathlib import Path
from playwright.sync_api import sync_playwright
from browser_support import configure_transport
from native_browser import native_chromium

parser=argparse.ArgumentParser()
parser.add_argument('url')
parser.add_argument('--fixture',action='store_true')
parser.add_argument('--system-https',action='store_true')
parser.add_argument('--output',required=True,type=Path)
parser.add_argument('--capture',type=Path)
args=parser.parse_args()
results={'url':args.url,'checkout_fixture':args.fixture,'holds':{},'bursts':{},'modes':[]}
probe=Path(__file__).with_name('interaction_probe.js').read_text()
keys=['KeyA','KeyS','Space','Enter']

with sync_playwright() as pw, native_chromium(pw) as (browser,ctx):
    results['browser']=browser.version
    configure_transport(ctx,args.url,args.fixture,args.system_https)
    ctx.add_init_script(probe)
    page=ctx.new_page()
    errors=[]
    ctx.on('page',lambda p:p.on('pageerror',lambda e:errors.append(str(e))))
    page.on('pageerror',lambda e:errors.append(str(e)))
    def wait(test,reason):
        deadline=time.monotonic()+8
        while not test():
            if time.monotonic()>deadline: raise AssertionError(reason)
            page.wait_for_timeout(30)
    def snap(name,expression="probe.gl.canvas.toDataURL()"):
        if args.capture:
            args.capture.mkdir(parents=True,exist_ok=True)
            data=page.evaluate(expression+".split(',')[1]")
            (args.capture/(name+'.png')).write_bytes(base64.b64decode(data))
    def state(win):
        return win.evaluate('({visibility:document.visibilityState,focus:document.hasFocus(),target:document.activeElement?.tagName})')
    def meter_reset():
        page.evaluate('probe.resetMeter()')
        return page.evaluate('probe.starts.length')
    def meter(prior):
        return page.evaluate('n=>({sources:probe.starts.slice(n),...probe.readMeter()})',prior)
    def audible(prior):
        try:
            wait(lambda:page.evaluate('n=>probe.starts.length>n && probe.readMeter().peak>.0001',prior),'no post-mix signal')
        except AssertionError as e:
            raise AssertionError({'audio':meter(prior),'states':page.evaluate('probe.states'),
                                  'opener':state(page),'recent':page.evaluate('probe.events.slice(-8)'),
                                  'status':page.locator('#audio-status').inner_text()}) from e
        return meter(prior)
    def check_hold(name,source,key):
        page.evaluate('probe.startFrames()')
        image_test=name=='top' and key=='KeyA'
        if image_test: snap('top-rest')
        start_events=source.evaluate('probe.events.length')
        count=meter_reset()
        source.keyboard.down(key)
        wait(lambda:page.evaluate('probe.frames.some(f=>f.pixels>0)'),'no depressed pixels in '+name)
        sound=audible(count)
        if image_test: snap('top-pressed')
        # A held cap must remain still until release. Record the framebuffer
        # read after each rendered pass, rather than screenshotting on a timer.
        source.wait_for_timeout(160)
        at_release=page.evaluate('probe.frames.length')
        if image_test and args.capture: page.evaluate('probe.captureBelow=probe.frames.at(-1).delta;probe.best=Infinity')
        source.keyboard.up(key)
        wait(lambda:page.evaluate('n=>probe.frames.length>n && probe.frames.at(-1).pixels===0',at_release),
             'no return to rest in '+name)
        source.wait_for_timeout(140)  # Include the last, sub-threshold travel before comparing rest.
        data=page.evaluate('probe.finishFrames()')
        frames=data['frames']
        peak=max(f['delta'] for f in frames[:at_release])
        intermediate=[f for f in frames[at_release:] if 0<f['delta']<peak]
        if image_test and args.capture:
            snap('top-rebound','probe.capture')
            page.evaluate('probe.captureBelow=0')
        assert data['rest']['delta']==0,(name,key,data['rest'])
        assert intermediate,(name,key,frames)
        assert max(f['pixels'] for f in frames)>80,(name,key,frames)
        results['holds'][name+' '+key]={
            'pixels':[f['pixels'] for f in frames], 'max_channel_delta_sum':[f['delta'] for f in frames],
            'first_scissor':frames[0]['area'],'rest':data['rest'],'audio':sound,
            'events':source.evaluate("n=>probe.events.slice(n).filter(e=>e[0]==='keydown'||e[0]==='keyup')",start_events)
        }
    def burst(name,source):
        page.wait_for_timeout(240)
        before=page.locator('#writing').evaluate('t=>[t.value,t.selectionStart,t.selectionEnd]')
        count=meter_reset()
        initial_draws=page.evaluate('probe.draws')
        start=source.evaluate('probe.events.length')
        for _ in range(2):
            for key in keys: source.keyboard.press(key,delay=18)
        source.wait_for_timeout(250)
        events=source.evaluate("n=>probe.events.slice(n).filter(e=>e[0]==='keydown' || e[0]==='keyup')",start)
        sound=meter(count)
        draws=page.evaluate('probe.draws')-initial_draws
        assert [e[1] for e in events if e[0]=='keydown']==keys*2 and len(events)==16 and all(e[4] for e in events)
        assert len(sound['sources'])==8 and sound['peak']>.001 and draws>=10,(name,sound,draws)
        after=page.locator('#writing').input_value()
        expected=before[0]
        if source==page:
            expected=expected[:before[1]]+'as \nas \n'+expected[before[2]:]
        assert after==expected,(name,after,expected)
        results['bursts'][name]={'events':events,'draws':draws,'audio':sound,'writer_matches':True}
        print('PASS',name,'8 strokes,',draws,'draw calls, post-mix peak',round(sound['peak'],4),flush=True)
    assert page.goto(args.url).ok
    page.locator('#viewport canvas').wait_for()
    wait(lambda:page.evaluate('probe.draws>=5'),'initial draw')
    page.evaluate('window.firstGL=probe.gl;window.firstCanvas=probe.gl.canvas')
    # A real first decode is deliberately held beyond the old 160 ms deadline.
    page.evaluate("""()=>{const decode=AudioContext.prototype.decodeAudioData;
      AudioContext.prototype.decodeAudioData=async function(...args){
        const buffer=await decode.apply(this,args);
        await new Promise(r=>setTimeout(r,400));return buffer;
      }}""")
    writer=page.locator('#writing')
    writer.focus()
    prior=meter_reset()
    page.keyboard.press('KeyA')
    results['cold_decode_400ms']=audible(prior)
    for name in ['angle','top']:
        page.locator('#'+name).click()
        writer.click();page.wait_for_timeout(200)
        for key in keys: check_hold(name,page,key)
        burst(name,page)
    writer.fill('')
    cdp=ctx.new_cdp_session(page)
    for draft,text in [('onf','你'),('ho','好')]:
        cdp.send('Input.imeSetComposition',{'text':draft,'selectionStart':len(draft),'selectionEnd':len(draft)})
        assert page.locator('#ime').inner_text()=='正在選字…'
        cdp.send('Input.insertText',{'text':text})
    cdp.send('Input.imeSetComposition',{'text':'abc','selectionStart':3,'selectionEnd':3})
    cdp.send('Input.imeSetComposition',{'text':'','selectionStart':0,'selectionEnd':0})
    results['ime']={'text':writer.input_value(),'events':page.evaluate("probe.events.filter(e=>e[0].startsWith('composition')).map(e=>e[0])")}
    assert results['ime']['text']=='你好' and len(results['ime']['events'])==6
    page.locator('#angle').click()
    with ctx.expect_page() as opening: page.locator('#float-mode').click()
    mini=opening.value
    mini.locator('.mini-bar').wait_for()
    # Some Linux window managers choose a larger initial window. Exercise
    # the target 400 × 250 content size using the browser's real window.
    mini_cdp=ctx.new_cdp_session(mini)
    bounds=mini_cdp.send('Browser.getWindowForTarget')
    dw,dh=mini.evaluate('[outerWidth-innerWidth,outerHeight-innerHeight]')
    mini_cdp.send('Browser.setWindowBounds',{'windowId':bounds['windowId'],
                                             'bounds':{'width':400+dw,'height':250+dh}})
    wait(lambda:mini.evaluate('innerWidth===400 && innerHeight===250 && document.querySelector("canvas").width===400'),
         'mini content did not resize and redraw')
    results['pip_size']=mini.evaluate('[innerWidth,innerHeight]')
    def mode(expected):
        toggle=mini.locator('[data-mini=eco]')
        expected_text='省電模式' if expected=='eco' else '標準模式'
        assert page.locator('#quality').input_value()==expected
        assert toggle.get_attribute('aria-pressed')==str(expected=='eco').lower()
        assert toggle.inner_text()==expected_text
        results['modes'].append([expected,expected_text,toggle.get_attribute('aria-pressed')])
    mode('eco')
    assert page.evaluate("firstCanvas===documentPictureInPicture.window.document.querySelector('canvas') && firstGL===firstCanvas.getContext('webgl2') && !document.querySelector('canvas')")
    mini.locator('.mini-stage').click()
    check_hold('mini',mini,'KeyA')
    burst('mini focus',mini)
    mini.locator('[data-mini=eco]').click();mode('standard')
    burst('mini standard',mini)
    page.bring_to_front()
    page.locator('#quality').select_option('eco');mode('eco')
    writer.click()
    results['focus_main']=[state(page),state(mini)]
    assert results['focus_main'][0]['focus'] and not results['focus_main'][1]['focus']
    check_hold('main to mini',page,'KeyS')
    burst('main drives mini',page)
    page.locator('#quality').select_option('standard');mode('standard')
    mini.bring_to_front()
    mini.locator('[data-mini=eco]').click();mode('eco')
    # Pointer toggles must restore the typing surface, not reactivate on Space.
    mini.locator('[data-mini=mute]').click()
    prior=meter_reset();mini.keyboard.press('Space');mini.wait_for_timeout(260)
    results['muted_space']=meter(prior)
    assert not results['muted_space']['sources'] and results['muted_space']['peak']==0
    assert page.locator('#sound-toggle').get_attribute('aria-pressed')=='false'
    mini.locator('[data-mini=mute]').click()
    prior=meter_reset();mini.keyboard.press('Space')
    results['unmuted_space']=audible(prior)
    assert page.locator('#sound-toggle').get_attribute('aria-pressed')=='true'
    mini.keyboard.press('Tab')
    assert mini.evaluate("document.activeElement.dataset.mini==='mute'")
    mini.keyboard.press('Space')
    assert page.locator('#sound-toggle').get_attribute('aria-pressed')=='false'
    mini.keyboard.press('Enter')
    assert page.locator('#sound-toggle').get_attribute('aria-pressed')=='true'
    assert mini.evaluate("document.activeElement.dataset.mini==='mute'")
    results['keyboard_controls']=['Tab to mute','Space muted','Enter unmuted','button kept focus']
    for tone in ['rainy','topre','brown']:
        page.bring_to_front()
        page.locator('#tone').select_option(tone)
        page.wait_for_timeout(300)
        prior=meter_reset();page.locator('#audition').click()
        results.setdefault('auditions',{})[tone]=audible(prior)
    assert len({s['sources'][-1]['samples'] for s in results['auditions'].values()})==3
    # Explicitly create a tab in the same native top-level Chrome window.
    with ctx.expect_page() as new_tab:
        browser.new_browser_cdp_session().send('Target.createTarget',
            {'url':'about:blank','newWindow':False,'background':False})
    other=new_tab.value
    other.bring_to_front()
    other.set_content('<textarea autofocus></textarea>')
    other.locator('textarea').click()
    wait(lambda:page.evaluate('document.hidden'),'opener was never actually hidden')
    wait(lambda:page.evaluate("probe.context.state==='suspended'"),'audio did not suspend')
    page.wait_for_timeout(160)
    def activity():
        return page.evaluate('[probe.draws,probe.starts.length,probe.frameRequests]')+[mini.evaluate('probe.frameRequests')]
    start=activity()
    other.keyboard.type('outside')
    other.wait_for_timeout(350)
    assert start==activity()
    results['other_tab']={'main':state(page),'mini':state(mini),'added_draws':0,'added_sources':0,'added_frame_requests':0}
    mini.bring_to_front();mini.locator('.mini-stage').click()
    results['focus_mini_hidden_main']=[state(page),state(mini)]
    assert page.evaluate('document.hidden') and mini.evaluate('document.hasFocus()')
    check_hold('hidden main',mini,'Enter')
    burst('visible mini, hidden main',mini)
    wait(lambda:page.evaluate("probe.context.state==='suspended'"),'visible PiP idle audio did not suspend')
    results['hidden_opener_idle_audio']=page.evaluate('probe.context.state')
    quiet=activity()
    mini.wait_for_timeout(500)
    assert quiet==activity()
    results['focused_mini_idle']={'ms':500,'added_draws':0,'added_frame_requests':0,'added_sources':0}
    results['mini_focus_events']=mini.evaluate("probe.events.filter(e=>['focus','blur','visibilitychange'].includes(e[0]))")
    other.close()
    mini.locator('[data-mini=back]').click()
    page.bring_to_front()
    writer.click()
    assert page.evaluate("firstCanvas===document.querySelector('canvas') && firstGL===firstCanvas.getContext('webgl2') && !firstGL.isContextLost()")
    results['context_restored']=True
    check_hold('returned',page,'KeyA')
    burst('returned main',page)
    results['audio_states']=page.evaluate('probe.states')
    results['main_focus_events']=page.evaluate("probe.events.filter(e=>['focus','blur','visibilitychange'].includes(e[0]))")
    # First-ever gesture on a new document opens PiP. No typing, auditions or
    # audio unlock in the opener precede the first physical key in the mini.
    fresh=ctx.new_page()
    assert fresh.goto(args.url).ok
    fresh.locator('#viewport canvas').wait_for()
    assert fresh.evaluate('!probe.context')
    with ctx.expect_page() as created: fresh.locator('#float-mode').click()
    first_mini=created.value
    first_mini.locator('.mini-stage').wait_for()
    first_mini.keyboard.press('KeyA')
    wait(lambda:fresh.evaluate('probe.starts.length===1 && probe.readMeter().peak>.001'),'first gesture PiP audio missing')
    results['fresh_pip']=fresh.evaluate('({sources:probe.starts,states:probe.states,peak:probe.peak})')
    first_mini.close();fresh.close()
    assert not errors,errors
    print('PASS framebuffer rebound, focus handoff, cold audio, mute/unmute, auditions, native IME, canvas return',flush=True)
args.output.write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n')
