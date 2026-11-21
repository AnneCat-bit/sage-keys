// Only the separately compiled QA bundle injects this probe.
const qa=window.qa={draws:0,frames:0,requests:0,starts:0,contexts:0,decodes:[],requestsOut:0};
const originalFrame=window.requestAnimationFrame.bind(window);
window.requestAnimationFrame=fn=>{qa.requests++;return originalFrame(t=>{qa.frames++;fn(t);});};
const get=HTMLCanvasElement.prototype.getContext;
HTMLCanvasElement.prototype.getContext=function(type,...args){
  const ctx=get.call(this,type,...args);
  if(type.startsWith('webgl') && ctx && ctx!==qa.gl){qa.gl=ctx;qa.contexts++;}
  return ctx;
};
for(const gl of [window.WebGL2RenderingContext,window.WebGLRenderingContext].filter(Boolean)){
  const orig=gl.prototype.drawElements;
  gl.prototype.drawElements=function(...args){qa.draws++;return orig.apply(this,args);};
}
qa.pixels=()=>{
  const gl=qa.gl;if(!gl || gl.isContextLost())return -1;
  const w=gl.drawingBufferWidth,h=gl.drawingBufferHeight;
  const rgba=new Uint8Array(w*h*4);gl.readPixels(0,0,w,h,gl.RGBA,gl.UNSIGNED_BYTE,rgba);
  if(!qa.rest || qa.rest.length!==rgba.length){qa.rest=rgba;return 0;}
  let n=0;
  for(let i=0;i<rgba.length;i+=4){
    if(Math.max(...[0,1,2].map(c=>Math.abs(rgba[i+c]-qa.rest[i+c])))>=8)n++;
  }
  return n;
};
const start=AudioBufferSourceNode.prototype.start;
AudioBufferSourceNode.prototype.start=function(when,off,len){
  const result=start.call(this,when,off,len);
  const buffer=this.buffer,samples=buffer.getChannelData(0),first=Math.floor(off*buffer.sampleRate);
  let sum=0;const count=Math.min(Math.floor(len*buffer.sampleRate),samples.length-first);
  for(let i=first;i<first+count;i++)sum+=samples[i]*samples[i];
  qa.starts++;qa.audio=this.context;
  qa.last={state:this.context.state,length:buffer.length,duration:len,rms:Math.sqrt(sum/count)};
  return result;
};
const fetchOriginal=window.fetch;
window.fetch=(...args)=>{qa.requestsOut++;return fetchOriginal(...args);};
qa.policyBlocks=0;
document.addEventListener('securitypolicyviolation',event=>{
  if(event.effectiveDirective==='connect-src') qa.policyBlocks++;
});
const connect=AudioNode.prototype.connect;
AudioNode.prototype.connect=function(dest,...rest){
  if(this instanceof DynamicsCompressorNode && dest===this.context.destination){
    const meter=qa.meter=this.context.createAnalyser();
    meter.fftSize=32768;
    connect.call(this,meter);
    return connect.call(meter,dest,...rest);
  }
  return connect.call(this,dest,...rest);
};
qa.mixPeak=()=>{
  if(!qa.meter || !qa.audio) return 0;
  const a=new Float32Array(qa.meter.fftSize);
  qa.meter.getFloatTimeDomainData(a);
  const count=Math.round((qa.audio.currentTime-(qa.mark||0))*qa.audio.sampleRate);
  let peak=0;
  for(let i=Math.max(0,a.length-count);i<a.length;i++) peak=Math.max(peak,Math.abs(a[i]));
  return peak;
};
