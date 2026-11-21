// Only recorded WAV excerpts are scheduled. Each buffer contains seven slices.
export function createSound(prefs, report, hasFocus) {
  const files = new Map(), decoded = new Map(), voices = new Set(), lastIndex = new Map();
  const base = new URL('../assets/audio/', import.meta.url);
  let context, master, compressor, slices, indexRequest, idleTimer, generation = 0;
  function get(url) {
    return fetch(url).then(response => {
      if (!response.ok) throw Error('Audio unavailable');
      return response;
    });
  }
  function sampleFile(tone) {
    if (!files.has(tone)) {
      files.set(tone, get(new URL(tone+'.wav',base)).then(r=>r.arrayBuffer())
        .catch(error=>{ files.delete(tone); throw error; }));
    }
    return files.get(tone);
  }
  function loadIndex() {
    if (!indexRequest) indexRequest = get(new URL('sprites.json',base)).then(r=>r.json())
      .then(data=>{slices=data;}).catch(error=>{indexRequest=null; throw error;});
    return indexRequest;
  }
  function preload() {
    if (!prefs.muted && prefs.volume) {
      Promise.all([loadIndex(), sampleFile(prefs.tone)]).catch(()=>report('音檔載入失敗，可按試聽重試。'));
    }
  }
  function open() {
    if (context) return;
    const Audio = window.AudioContext || window.webkitAudioContext;
    context = new Audio({latencyHint:'interactive'});
    master = context.createGain();
    compressor = context.createDynamicsCompressor();
    compressor.threshold.value = -12;
    compressor.ratio.value = 6;
    master.connect(compressor).connect(context.destination);
    master.gain.value = prefs.muted ? 0 : prefs.volume/100;
  }
  function decode(tone) {
    if (!decoded.has(tone)) {
      decoded.set(tone, sampleFile(tone).then(data=>context.decodeAudioData(data.slice(0)))
        .catch(error=>{decoded.delete(tone);throw error;}));
    }
    return decoded.get(tone);
  }
  function halt() {
    generation++;
    clearTimeout(idleTimer);
    for (const voice of voices) voice.stop();
    voices.clear();
    if (context?.state === 'running') context.suspend().catch(()=>{});
  }
  async function play(code, audition=false) {
    if (prefs.muted || prefs.volume === 0 || !hasFocus()) return;
    const tone = prefs.tone, current = generation, time = performance.now();
    try {
      open();
      clearTimeout(idleTimer);
      const [,,buffer] = await Promise.all([context.resume(),loadIndex(),decode(tone)]);
      if (current !== generation || tone !== prefs.tone || prefs.muted || !hasFocus()) {
        if ((prefs.muted || !hasFocus()) && context.state==='running') context.suspend().catch(()=>{});
        return;
      }
      clearTimeout(idleTimer);
      idleTimer = setTimeout(()=>{if(context.state==='running') context.suspend().catch(()=>{});}, 1200);
      if (!audition && performance.now()-time > 160) return;
      if (voices.size >= 5) {
        const oldest = voices.values().next().value;
        oldest.stop(); voices.delete(oldest);
      }
      const special = {Space:4,Enter:5,Backspace:6}[code];
      let which = special;
      if (which === undefined) {
        const old = lastIndex.get(tone);
        which = old === undefined ? Math.floor(Math.random()*4) : (old+1+Math.floor(Math.random()*3))%4;
        lastIndex.set(tone,which);
      }
      const [offset,duration] = slices[tone][which];
      const voice = context.createBufferSource();
      voice.buffer = buffer;
      voice.connect(master);
      voices.add(voice);
      voice.onended = ()=>{ voices.delete(voice); voice.disconnect(); };
      voice.start(0,offset,duration);
      report('');
    } catch {
      if (current === generation) report('暫時無法播放錄音，請按試聽重試。');
    }
  }
  function sync() {
    if (master) master.gain.setTargetAtTime(prefs.muted ? 0 : prefs.volume/100,context.currentTime,.008);
    if (prefs.muted || prefs.volume===0) halt();
    else preload();
  }
  preload();
  return { play, sync, halt };
}
