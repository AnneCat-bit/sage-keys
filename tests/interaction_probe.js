// Test-only instrumentation. The deployed app never imports this file.
const probe = window.probe = {events:[], frames:[], draws:0, starts:[], peak:0, nonzero:0, states:[]};
for (const type of ['keydown','keyup','focus','blur','visibilitychange','compositionstart','compositionend']) {
  window.addEventListener(type,e=>{
    if (['focus','blur'].includes(type) && e.target!==window) return;
    probe.events.push([type,e.code||'',document.visibilityState,document.hasFocus(),e.isTrusted]);
  },true);
}
function pixels(x,y,w,h) {
  const gl=probe.gl;
  const data=new Uint8Array(w*h*4);
  gl.readPixels(x,y,w,h,gl.RGBA,gl.UNSIGNED_BYTE,data);
  return data;
}
probe.startFrames=()=>{
  const gl=probe.gl;
  probe.origin=pixels(0,0,gl.drawingBufferWidth,gl.drawingBufferHeight);
  probe.frames=[];
};
function difference(x,y,w,h) {
  const data=pixels(x,y,w,h), stride=probe.gl.drawingBufferWidth;
  let count=0, total=0;
  for(let row=0;row<h;row++) {
    let i=4*row*w, j=4*((row+y)*stride+x);
    for(let col=0;col<w;col++,i+=4,j+=4) {
      const delta=Math.max(Math.abs(data[i]-probe.origin[j]),Math.abs(data[i+1]-probe.origin[j+1]),
        Math.abs(data[i+2]-probe.origin[j+2]));
      if(delta>=8) count++;
      total+=delta;
    }
  }
  return {pixels:count,delta:total};
}
probe.finishFrames=()=>{
  const gl=probe.gl;
  const rest=difference(0,0,gl.drawingBufferWidth,gl.drawingBufferHeight);
  probe.origin=null;
  return {frames:probe.frames,rest};
};
for(const api of [WebGLRenderingContext,WebGL2RenderingContext]){
  const draw=api.prototype.drawElements;
  api.prototype.drawElements=function(...args){
    const result=draw.apply(this,args);
    probe.draws++;probe.gl=this;
    if (probe.origin && !probe.queued) {
      const area=this.isEnabled(this.SCISSOR_TEST) ? [...this.getParameter(this.SCISSOR_BOX)] :
        [0,0,this.drawingBufferWidth,this.drawingBufferHeight];
      probe.queued=true;
      queueMicrotask(()=>{
        probe.queued=false;
        if(!probe.origin) return;
        const frame={...difference(...area),area,time:Math.round(performance.now())};
        probe.frames.push(frame);
        if(frame.delta>0 && frame.delta<probe.captureBelow) {
          probe.capture=this.canvas.toDataURL();
          probe.captureBelow=0;
        }
      });
    }
    return result;
  };
}
// Put Chromium's unity-gain analyser in the real post-compressor output path
// in this test only. Its ring buffer covers short samples between UI polls.
const connect=AudioNode.prototype.connect;
AudioNode.prototype.connect=function(dest,...args) {
  if(dest===this.context.destination && this instanceof DynamicsCompressorNode) {
    const ctx=probe.context=this.context;
    probe.states.push(ctx.state);
    ctx.addEventListener('statechange',()=>probe.states.push(ctx.state));
    const analyser=probe.analyser=ctx.createAnalyser();
    analyser.fftSize=32768;
    probe.samples=new Float32Array(analyser.fftSize);
    connect.call(this,analyser);
    return connect.call(analyser,dest,...args);
  }
  return connect.call(this,dest,...args);
};
probe.resetMeter=()=>{
  probe.peak=0;
  probe.nonzero=0;
  probe.startTime=probe.context?.currentTime || 0;
};
probe.readMeter=()=>{
  if(probe.analyser) {
    const {context,analyser,samples}=probe;
    analyser.getFloatTimeDomainData(samples);
    const count=Math.round((context.currentTime-(probe.startTime||0))*context.sampleRate);
    let nonzero=0;
    for(let i=Math.max(0,samples.length-count);i<samples.length;i++) {
      const amp=Math.abs(samples[i]);
      if(amp>.0001) nonzero++;
      probe.peak=Math.max(probe.peak,amp);
    }
    probe.nonzero=Math.max(probe.nonzero||0,nonzero);
  }
  return {peak:probe.peak,nonzero_samples:probe.nonzero};
};
const start=AudioBufferSourceNode.prototype.start;
AudioBufferSourceNode.prototype.start=function(...args) {
  const result=start.apply(this,args);
  probe.starts.push({offset:args[1],duration:args[2],samples:this.buffer.length,state:this.context.state});
  return result;
};
