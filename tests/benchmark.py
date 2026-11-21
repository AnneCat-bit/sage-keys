"""Measure a dedicated cloud Chromium instance. No instrumentation ships in the app."""
import argparse
import json
import shutil
import time
from pathlib import Path
from browser_support import configure_transport
from playwright.sync_api import sync_playwright

parser=argparse.ArgumentParser()
parser.add_argument('url')
parser.add_argument('--system-https',action='store_true')
parser.add_argument('--output',type=Path)
args=parser.parse_args()
with sync_playwright() as pw:
    browser=pw.chromium.launch(executable_path=shutil.which('chromium'),args=[
        '--use-angle=swiftshader','--enable-unsafe-swiftshader','--disable-dev-shm-usage'])
    device=browser.new_browser_cdp_session()
    ctx=browser.new_context(no_viewport=True)
    configure_transport(ctx,args.url,system_https=args.system_https)
    ctx.add_init_script("""
      window.bench={draws:0};
      for (const api of [WebGL2RenderingContext,WebGLRenderingContext]){
        const original=api.prototype.drawElements;
        api.prototype.drawElements=function(...args){bench.draws++;return original.apply(this,args)}
      }
    """)
    page=ctx.new_page()
    session=ctx.new_cdp_session(page)
    session.send('Emulation.setDeviceMetricsOverride',{'width':1280,'height':800,'deviceScaleFactor':1,'mobile':False})
    session.send('Performance.enable')
    report={'browser':browser.version,'viewport':[1280,800],'dpr':1,'url':args.url,'rows':[]}
    def sample():
        processes=device.send('SystemInfo.getProcessInfo')['processInfo']
        pss=0
        for proc in processes:
            try:
                lines=Path('/proc',str(proc['id']),'smaps_rollup').read_text().splitlines()
                pss+=int(next(x for x in lines if x.startswith('Pss:')).split()[1])/1024
            except (OSError,StopIteration): pass
        metrics={x['name']:x['value'] for x in session.send('Performance.getMetrics')['metrics']}
        return (sum(p['cpuTime'] for p in processes),pss,metrics['JSHeapUsedSize']/2**20,
                page.evaluate('window.bench?.draws || 0'),time.monotonic())
    def measure(label,action):
        first=sample()
        count=action()
        last=sample()
        duration=last[4]-first[4]
        draws=last[3]-first[3]
        data={'scenario':label,'seconds':round(duration,2),'keystrokes':count or 0,
              'cpu_one_core_percent':round(100*(last[0]-first[0])/duration,2),
              'browser_pss_mib':round(last[1],1),'js_heap_mib':round(last[2],2),
              'draw_calls':draws,'frames':draws//5,'fps':round(draws/5/duration,2)}
        report['rows'].append(data)
        print(data,flush=True)
    def idle():time.sleep(8)
    def type_sample():
        start=time.monotonic()
        count=0
        while time.monotonic()-start<8:
            page.keyboard.press('KeyA' if count%2==0 else 'KeyS')
            count+=1
            time.sleep(max(0,min(.125,start+count*.125-time.monotonic())))
        return count
    page.goto('about:blank')
    page.wait_for_timeout(1800)
    measure('blank browser',idle)
    assert page.goto(args.url).ok
    page.locator('#viewport canvas').wait_for()
    page.evaluate('document.fonts.ready')
    page.locator('#writing').click()
    page.keyboard.type('warmup',delay=120)
    page.wait_for_timeout(4000)
    report['gpu']=device.send('SystemInfo.getInfo')['gpu']['auxAttributes'].get('glRenderer')
    canvas=page.locator('#viewport canvas')
    report['canvas']=canvas.evaluate('(c)=>[c.width,c.height]')
    measure('eco idle',idle)
    measure('eco typing with sound',type_sample)
    page.locator('#quality').select_option('standard')
    page.locator('#writing').focus()
    page.wait_for_timeout(500)
    measure('standard typing with sound',type_sample)
    page.wait_for_timeout(1800)
    measure('settled after typing',idle)
    page.locator('#quality').select_option('eco')
    with ctx.expect_page() as created:
        page.locator('#float-mode').click()
    mini=created.value
    mini.locator('canvas').wait_for()
    report['pip_size']=mini.evaluate('[innerWidth,innerHeight]')
    mini.wait_for_timeout(1500)
    measure('eco PiP idle',idle)
    def mini_typing():
        start=time.monotonic()
        count=0
        while time.monotonic()-start<8:
            mini.keyboard.press('KeyA' if count%2==0 else 'KeyS')
            count+=1
            time.sleep(max(0,min(.125,start+count*.125-time.monotonic())))
        return count
    measure('eco PiP typing with sound',mini_typing)
    mini.wait_for_timeout(1800)
    measure('eco PiP settled',idle)
    assert report['pip_size']==[400,250]
    for row in report['rows']:
        if 'idle' in row['scenario'] or 'settled' in row['scenario']:
            assert row['draw_calls']==0,row
        if row['keystrokes']:
            assert row['draw_calls']>0,row
    if args.output: args.output.write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
    browser.close()
