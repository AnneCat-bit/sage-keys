// Only recorded WAV excerpts are scheduled. Each buffer contains seven slices.
export function createSound(prefs, report) {
  const files = new Map(), decoded = new Map(), voices = new Set(), lastIndex = new Map();
  const base = new URL('../assets/audio/', import.meta.url);
  let context, master, compressor, slices, indexRequest, idleTimer, generation = 0, pending;
  const buffers = new Map();
  let wanted=false, suspending;
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
    context.addEventListener('statechange',()=>{
      if (!wanted && context.state==='running') suspend();
    });
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
        .then(buffer=>{buffers.set(tone,buffer);return buffer;})
        .catch(error=>{decoded.delete(tone);throw error;}));
    }
    return decoded.get(tone);
  }
  function suspend() {
    wanted=false;
    if (context?.state==='running' && !suspending) {
      suspending=context.suspend().catch(()=>{}).finally(()=>{suspending=null;});
    }
  }
  function halt() {
    generation++; pending=null;
    clearTimeout(idleTimer);
    for (const voice of voices) voice.stop();
    voices.clear();
    suspend();
  }
  function idle() {
    clearTimeout(idleTimer);
    idleTimer=setTimeout(suspend,1200);
  }
  function ready(tone) {
    wanted=true;
    clearTimeout(idleTimer);
    open();
    // Call resume in the trusted gesture, before waiting for network or decode.
    const resume=context.resume();
    // If an earlier suspend is still settling, wait for its state change
    // before scheduling the recording on the newly resumed context.
    const running=suspending ? Promise.all([suspending,resume]).then(()=>{
      if (wanted && context.state!=='running') return context.resume();
    }) : resume;
    return Promise.all([running,loadIndex(),decode(tone)]);
  }
  function prepare() {
    if (prefs.muted || !prefs.volume) return;
    const current=generation;
    try {
      ready(prefs.tone).then(()=>{
        if (current===generation) idle();
      }).catch(()=>{if (current===generation) idle();});
    } catch { /* A later gesture can retry. */ }
  }
  function schedule(code,tone,buffer) {
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
    idle();
  }
  async function play(code) {
    if (prefs.muted || !prefs.volume) return;
    const tone=prefs.tone;
    try {
      if (wanted && !suspending && context?.state==='running' && slices && buffers.has(tone)) {
        pending=null;
        schedule(code,tone,buffers.get(tone));
        return;
      }
      // Keep one pending strike on a cold start, including a slow first
      // decode. A burst cannot build up a queue to replay later.
      const strike={};
      pending=strike;
      clearTimeout(idleTimer);
      await ready(tone);
      if (pending!==strike) return;
      pending=null;
      schedule(code,tone,buffers.get(tone));
    } catch {
      if (!prefs.muted && tone===prefs.tone) report('暫時無法播放錄音，請按試聽重試。');
      if (context) idle();
    }
  }
  function sync() {
    if (master) master.gain.setTargetAtTime(prefs.muted ? 0 : prefs.volume/100,context.currentTime,.008);
    if (prefs.muted || prefs.volume===0) halt();
    else preload();
  }
  preload();
  return { play, prepare, sync, halt };
}
