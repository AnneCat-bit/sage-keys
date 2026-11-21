// A Document PiP window adopts the existing viewport. Its document has no app
// entry point, renderer or audio context of its own.
export function createFloating({host,button,view,bind,refresh,unavailable,prepare,toggleMute,toggleEco}) {
  const parent = host.parentNode;
  const slot = document.createComment('keyboard viewport');
  host.before(slot);
  const placeholder = document.getElementById('float-placeholder');
  const template = document.getElementById('mini-controls');
  let mini = null, opening = false, unbind = null;

  function sync(prefs) {
    if (!mini || mini.closed) return;
    const mute = mini.document.querySelector('[data-mini="mute"]');
    const eco = mini.document.querySelector('[data-mini="eco"]');
    if (!mute || !eco) return;
    const silent = prefs.muted || !prefs.volume;
    mute.querySelector('use').setAttribute('href',silent ? '#i-mute' : '#i-volume');
    mute.setAttribute('aria-label',silent ? '開啟聲音' : '靜音');
    mute.setAttribute('aria-pressed',silent);
    const saving=prefs.quality==='eco';
    eco.querySelector('span').textContent=saving ? '省電模式' : '標準模式';
    eco.setAttribute('aria-pressed',saving);
    eco.title=saving ? '目前為省電模式，點選切換為標準模式' : '目前為標準模式，點選啟用省電模式';
  }
  function restore(win) {
    if (mini !== win) return;
    unbind?.(); unbind=null;
    mini=null;
    parent.insertBefore(host,slot.nextSibling);
    placeholder.hidden=true;
    button.setAttribute('aria-pressed','false');
    button.querySelector('span').textContent='懸浮模式';
    view.rehost();
    refresh();
  }
  function close(focus = true) {
    if (!mini) return;
    const win=mini;
    if (focus && !win.closed) window.focus();
    restore(win);
    if (!win.closed) win.close();
    if (focus) button.focus({preventScroll:true});
  }
  async function toggle() {
    if (mini) { close(); return; }
    if (opening) return;
    if (!window.isSecureContext || window.top !== window || !window.documentPictureInPicture?.requestWindow) {
      unavailable(); return;
    }
    opening=true;
    let win;
    try {
      prepare();
      win=await window.documentPictureInPicture.requestWindow({
        width:400,height:250,preferInitialWindowPlacement:true
      });
      mini=win;
      win.addEventListener('pagehide',()=>restore(win),{once:true});
      const doc=win.document;
      doc.documentElement.lang='zh-Hant';
      doc.title='Sage 75 · Sage Keys';
      // Install already loaded same-origin rules synchronously. The canvas
      // must have a bounded container before the size observer follows it.
      const style=doc.createElement('style');
      const sheet=document.querySelector('link[rel="stylesheet"]').sheet;
      style.textContent=Array.from(sheet.cssRules).filter(rule=>rule.type!==CSSRule.FONT_FACE_RULE)
        .map(rule=>rule.cssText).join('\n');
      doc.head.append(style);
      doc.body.className='pip-page';
      doc.body.tabIndex=-1;
      doc.body.append(document.querySelector('.symbols').cloneNode(true),template.content.cloneNode(true));
      const stage=doc.querySelector('.mini-stage');
      stage.append(host);
      // A pointer-operated toggle should not consume the next Space/Enter.
      // Tab/keyboard activation keeps native button focus and semantics.
      function control(action) {
        return event=>{
          action();
          if (event.detail>0) doc.body.focus({preventScroll:true});
        };
      }
      doc.querySelector('[data-mini="mute"]').onclick=control(toggleMute);
      doc.querySelector('[data-mini="eco"]').onclick=control(toggleEco);
      doc.querySelector('[data-mini="back"]').onclick=()=>close();
      placeholder.hidden=false;
      button.setAttribute('aria-pressed','true');
      button.querySelector('span').textContent='收回小窗';
      view.rehost();
      unbind=bind(win);
      doc.body.focus({preventScroll:true});
      refresh();
    } catch {
      if (win) { restore(win); if (!win.closed) win.close(); }
      unavailable();
    } finally { opening=false; }
  }
  button.addEventListener('click',toggle);
  document.getElementById('return-here').addEventListener('click',()=>close());
  window.addEventListener('pagehide',()=>close(false));
  return {sync,get window(){return mini;}};
}
