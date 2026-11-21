"""Use an isolated Chromium profile with the browser's own focus/visibility policy."""
import shutil
import subprocess
import tempfile
import time
from contextlib import contextmanager
from pathlib import Path

@contextmanager
def native_chromium(playwright):
    # Playwright-managed contexts normally force document.hasFocus() to true.
    # Attach to the default context without those overrides for PiP handoffs.
    with tempfile.TemporaryDirectory(prefix='sage-chrome-',ignore_cleanup_errors=True) as profile:
        args=[shutil.which('chromium'), '--no-sandbox', '--no-first-run', '--no-default-browser-check',
              '--disable-background-networking', '--disable-dev-shm-usage', '--remote-debugging-port=0',
              '--use-angle=swiftshader', '--enable-unsafe-swiftshader',
              '--autoplay-policy=user-gesture-required','--window-size=1152,850',
              '--user-data-dir='+profile,'about:blank']
        process=subprocess.Popen(args,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        browser=None
        try:
            port_file=Path(profile,'DevToolsActivePort')
            deadline=time.monotonic()+15
            while not port_file.exists():
                if process.poll() is not None or time.monotonic()>deadline:
                    raise RuntimeError('Chromium failed to start on the test display')
                time.sleep(.05)
            port=port_file.read_text().splitlines()[0]
            browser=playwright.chromium.connect_over_cdp('http://127.0.0.1:'+port,no_defaults=True)
            yield browser,browser.contexts[0]
        finally:
            if browser and browser.is_connected():
                try:
                    browser.new_browser_cdp_session().send('Browser.close')
                except Exception:
                    pass  # DevTools can disconnect before acknowledging close.
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=5)
