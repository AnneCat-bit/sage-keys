"""Document Picture-in-Picture regression checks using real Chromium windows."""
import argparse
import shutil
import time
from pathlib import Path
from playwright.sync_api import sync_playwright
from browser_support import configure_transport

parser=argparse.ArgumentParser()
parser.add_argument('url')
parser.add_argument('--system-https',action='store_true')
parser.add_argument('--fixture',action='store_true')
parser.add_argument('--capture',type=Path)
args=parser.parse_args()
with sync_playwright() as pw:
    browser=pw.chromium.launch(executable_path=shutil.which('chromium'),args=[
        '--use-angle=swiftshader','--enable-unsafe-swiftshader','--disable-dev-shm-usage'])
    ctx=browser.new_context(no_viewport=True)
    configure_transport(ctx,args.url,args.fixture,args.system_https)
    ctx.add_init_script("""
      window.observed={draws:0,sounds:0};
      for(const api of [WebGL2RenderingContext,WebGLRenderingContext]){
        const draw=api.prototype.drawElements;
        api.prototype.drawElements=function(...args){observed.draws++;return draw.apply(this,args)};
      }
      const start=AudioBufferSourceNode.prototype.start;
      AudioBufferSourceNode.prototype.start=function(...args){observed.sounds++;return start.apply(this,args)};
    """)
    page=ctx.new_page()
    errors=[]
    def watch(p): p.on('pageerror',lambda e:errors.append(str(e)))
    watch(page)
    def wait(check):
        deadline=time.monotonic()+12
        while not check():
            if time.monotonic()>deadline: raise AssertionError('Timed out waiting for browser state')
            page.wait_for_timeout(60)
    page.goto(args.url)
    page.locator('#viewport canvas').wait_for()
    page.evaluate("""()=>{window.original=document.querySelector('#viewport canvas');
      window.originalGL=original.getContext('webgl2')||original.getContext('webgl')}""")
    page.locator('#writing').fill('小窗測試 Sage')
    def open_mini():
        with ctx.expect_page() as event:
            page.locator('#float-mode').click()
        mini=event.value
        watch(mini)
        mini.locator('.mini-bar').wait_for()
        wait(lambda:page.locator('#float-placeholder').is_visible())
        assert page.locator('canvas').count()==0
        assert page.evaluate("""()=>{const m=documentPictureInPicture.window.document;
          const c=m.querySelector('canvas');return m.querySelectorAll('canvas').length===1 &&
          c===original && (c.getContext('webgl2')||c.getContext('webgl'))===originalGL}""")
        assert mini.locator('textarea,header,main,script[src]').count()==0
        return mini
    def restored():
        wait(lambda:page.locator('#viewport canvas').count()==1)
        assert page.evaluate("document.querySelector('#viewport canvas')===original")
        assert page.locator('#writing').input_value().startswith('小窗測試 Sage')
        assert page.locator('#float-mode').get_attribute('aria-pressed')=='false'
    mini=open_mini()
    wait(lambda:mini.evaluate('innerWidth===400 && innerHeight===250'))
    mini.evaluate('document.fonts.ready')
    mini.wait_for_timeout(150)
    if args.capture:
        args.capture.mkdir(parents=True,exist_ok=True)
        mini.screenshot(path=str(args.capture/'floating.png'))
    cdp=ctx.new_cdp_session(mini)
    native=cdp.send('Browser.getWindowForTarget')
    bounds=native['bounds']
    native_id=native['windowId']
    dw=bounds['width']-400; dh=bounds['height']-250
    cdp.send('Browser.setWindowBounds',{'windowId':native_id,'bounds':{'width':300+dw,'height':190+dh,'left':32,'top':34}})
    wait(lambda:mini.evaluate('innerWidth===300 && innerHeight===190'))
    assert mini.evaluate('document.documentElement.scrollWidth===innerWidth && document.documentElement.scrollHeight===innerHeight')
    assert cdp.send('Browser.getWindowBounds',{'windowId':native_id})['bounds']['left']==32
    print('PASS native 400×250 window, reposition, resize to 300×190, same canvas and GL context',flush=True)

    # Real keyboard events go to the separate PiP document and use the existing audio context.
    d,s=page.evaluate('[observed.draws,observed.sounds]')
    mini.keyboard.press('KeyA',delay=85)
    wait(lambda:page.evaluate('observed.draws')>d and page.evaluate('observed.sounds')>s)
    mini.get_by_role('button',name='靜音',exact=True).click()
    assert page.locator('#sound-toggle').get_attribute('aria-pressed')=='false'
    before=page.evaluate('observed.sounds')
    mini.keyboard.press('KeyS')
    assert page.evaluate('observed.sounds')==before
    mini.locator('[data-mini=eco]').click()
    assert page.locator('#quality').input_value()=='standard'
    mini.locator('[data-mini=eco]').click()
    assert page.locator('#quality').input_value()=='eco'
    page.bring_to_front()
    page.locator('#writing').click()
    begin=page.evaluate('observed.draws')
    page.keyboard.press('End');page.keyboard.type('!')
    assert page.locator('#writing').input_value().endswith('!')
    wait(lambda:page.evaluate('observed.draws')>begin)
    print('PASS keyboard feedback from both Sage Keys windows, synchronized mute and quality',flush=True)

    other=ctx.new_page()
    other.set_content('<textarea autofocus></textarea>')
    other.locator('textarea').click()
    page.wait_for_timeout(1000)
    before=page.evaluate('[observed.draws,observed.sounds]')
    other.keyboard.type('external input',delay=30)
    page.wait_for_timeout(500)
    assert page.evaluate('[observed.draws,observed.sounds]')==before
    assert not mini.is_closed()
    other.close()
    mini.bring_to_front()
    mini.get_by_role('button',name='返回完整工作室').click()
    restored()
    mini=open_mini()
    mini.close()
    restored()
    mini=open_mini()
    page.reload()
    wait(lambda:mini.is_closed())
    page.locator('#viewport canvas').wait_for()
    assert page.locator('#writing').input_value()==''
    print('PASS separate page typing causes no feedback, return button, native close, opener refresh',flush=True)

    page.add_init_script("Object.defineProperty(window,'documentPictureInPicture',{value:undefined})")
    page.reload()
    page.locator('#float-mode').click()
    assert page.get_by_role('dialog').is_visible()
    assert '桌面版 Chrome' in page.get_by_role('dialog').inner_text()
    page.keyboard.press('Escape')
    page.locator('#viewport canvas').wait_for()
    page.locator('#writing').click()
    page.keyboard.type('normal')
    assert page.locator('#writing').input_value()=='normal'
    assert not errors,errors
    print('PASS unsupported API hint and continued main studio use',flush=True)
    browser.close()
