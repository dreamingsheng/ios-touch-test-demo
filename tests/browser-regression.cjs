// Run a local static server for docs/ and Chrome with --remote-debugging-port=9333.
// SITE and CDP_ENDPOINT can point at other test instances. Node >=22 required.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const site = process.env.SITE || 'http://127.0.0.1:8765/';
const endpoint = process.env.CDP_ENDPOINT || 'http://127.0.0.1:9333';
const delay = ms => new Promise(r => setTimeout(r, ms));
async function main(){
  const target = await fetch(endpoint+'/json/new?'+encodeURIComponent(site),{method:'PUT'}).then(r=>r.json());
  const ws = new WebSocket(target.webSocketDebuggerUrl), pending=new Map(), errors=[];let seq=0;
  ws.onmessage=e=>{const m=JSON.parse(e.data);if(m.id){pending.get(m.id)?.(m);pending.delete(m.id)}if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails.exception?.description||m.params.exceptionDetails.text)};
  await new Promise((resolve,reject)=>{ws.onopen=resolve;ws.onerror=reject});
  const call=(method,params={})=>new Promise((resolve,reject)=>{const id=++seq;pending.set(id,m=>m.error?reject(Error(JSON.stringify(m.error))):resolve(m.result));ws.send(JSON.stringify({id,method,params}))});
  const evalv=async expression=>{const r=await call('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(r.exceptionDetails)throw Error(r.exceptionDetails.exception?.description);return r.result.value};
  const select=mode=>evalv(`document.querySelector('[data-mode="${mode}"]').click()`);
  const point=(id,x,y)=>({id,x,y,radiusX:8,radiusY:8,force:.8});
  const touch=(type,touchPoints)=>call('Input.dispatchTouchEvent',{type,touchPoints});
  const metrics=async(width,height)=>{await call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:true,screenWidth:width,screenHeight:height});await delay(100)};
  const passes=[];
  try{
    await call('Runtime.enable');await call('Page.enable');await call('Emulation.setTouchEmulationEnabled',{enabled:true,maxTouchPoints:10});await metrics(390,844);await call('Page.navigate',{url:site});await delay(700);
    await select('aim');const before=await evalv(`parseFloat(document.querySelector('#crosshair').style.left)`);
    await touch('touchStart',[point(1,250,400)]);await touch('touchMove',[point(1,300,360)]);
    const after=await evalv(`parseFloat(document.querySelector('#crosshair').style.left)`);assert.ok(Math.abs(after-before-50)<1,'crosshair must move by actual drag delta');await touch('touchEnd',[]);passes.push('aim actual 50px displacement');
    await select('hold');const center=await evalv(`(()=>{const r=document.querySelector('#holdMark').getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2}})()`);
    await touch('touchStart',[point(1,center.x,center.y)]);await delay(1150);assert.ok(parseFloat(await evalv('v0.textContent'))>=1,'stationary hold timer');await touch('touchEnd',[]);passes.push('stationary hold timer');
    await select('read');await touch('touchStart',[point(1,330,400)]);await touch('touchMove',[point(1,70,400)]);await touch('touchCancel',[]);assert.equal(await evalv('v0.textContent'),'1/3','cancel must not turn page');passes.push('cancel does not commit page turn');
    await select('pinch');await touch('touchStart',[point(1,120,400),point(2,260,400)]);await touch('touchEnd',[]);assert.equal(await evalv('v0.textContent'),'0');passes.push('gesture touch count clears on release');
    await select('menu');const menu=await evalv(`(()=>{document.querySelector('.menu-row').click();document.querySelector('.menu-row').click();const i=document.querySelector('input[type=checkbox]');i.click();const depth=v0.textContent;menuBack.click();document.querySelector('.menu-row').click();return{depth,checked:document.querySelector('input[type=checkbox]').checked,nested:document.querySelectorAll('button input').length,scrollable:document.querySelector('.menu-test').scrollHeight>document.querySelector('.menu-test').clientHeight}})()`);
    assert.equal(menu.depth,'3');assert.equal(menu.checked,true);assert.equal(menu.nested,0);assert.equal(menu.scrollable,true);passes.push('finite menu navigation, state persistence and real long list');
    // Feed deliberately bent intermediate samples and inspect canvas pixels at the bend.
    await select('multi');const sampleResult=await evalv(`(()=>{const s=document.querySelector('#stage'),r=s.getBoundingClientRect(),base={pointerId:901,pointerType:'touch',bubbles:true,clientX:r.x+40,clientY:r.y+150,width:12,height:18,pressure:.7};const d=new PointerEvent('pointerdown',base);s.setPointerCapture=()=>{};s.dispatchEvent(d);const m=new PointerEvent('pointermove',{...base,clientX:r.x+200,clientY:r.y+150});Object.defineProperty(m,'getCoalescedEvents',{value:()=>[new PointerEvent('pointermove',{...base,clientX:r.x+120,clientY:r.y+250}),m]});s.dispatchEvent(m);const c=document.querySelector('#surface'),p=c.width/r.width,pixel=c.getContext('2d').getImageData(Math.round(120*p),Math.round(250*p),1,1).data[3];s.dispatchEvent(new PointerEvent('pointerup',base));return pixel})()`);assert.ok(sampleResult>0,'intermediate coalesced samples must be drawn');passes.push('coalesced samples preserve actual bend');
    for(const [width,height] of [[390,844],[844,390],[320,568]]){
      await metrics(width,height);
      const modes=await evalv(`[...document.querySelectorAll('[data-mode]')].map(b=>b.dataset.mode)`);assert.equal(modes.length,21);
      for(const mode of modes){await select(mode);const layout=await evalv(`(()=>{const a=document.querySelector('#app').getBoundingClientRect(),n=document.querySelector('#nav').getBoundingClientRect(),s=document.querySelector('#stage').getBoundingClientRect();return{app:a.bottom,nav:n.bottom,stage:s.height,scroll:document.documentElement.scrollWidth}})()`);assert.ok(layout.app<=height+1&&layout.nav<=height+1&&layout.stage>100&&layout.scroll<=width,JSON.stringify({width,height,mode,layout}));}
      await select('aim');await delay(100);if(process.env.SCREENSHOT_DIR){const shot=await call('Page.captureScreenshot',{format:'png'});fs.writeFileSync(process.env.SCREENSHOT_DIR+`/aim-${width}.png`,Buffer.from(shot.data,'base64'))}
      passes.push(`21 modes fit ${width}x${height}`);
    }
    await evalv(`Promise.race([navigator.serviceWorker.ready.then(async()=>{for(let i=0;i<50;i++){if((await caches.keys()).includes('touch-test-v7'))return true;await new Promise(r=>setTimeout(r,100))}throw Error('v7 cache missing')}),new Promise((_,reject)=>setTimeout(()=>reject(Error('service worker timeout')),8000))])`);
    await call('Page.reload');await delay(600);
    assert.equal(await evalv('!!navigator.serviceWorker.controller'),true);
    await call('Network.enable');await call('Network.emulateNetworkConditions',{offline:true,latency:0,downloadThroughput:-1,uploadThroughput:-1});
    await call('Page.reload');await delay(600);
    assert.equal(await evalv(`document.querySelectorAll('[data-mode]').length`),21,'offline app shell');
    await select('menu');assert.equal(await evalv('!!document.querySelector("#menuList")'),true,'offline application JS');
    await call('Network.emulateNetworkConditions',{offline:false,latency:0,downloadThroughput:-1,uploadThroughput:-1});passes.push('offline reload retains all 21 modes and application logic');
    assert.deepEqual(errors,[]);console.log(JSON.stringify({passed:passes,errors},null,2));
  }finally{ws.close();await fetch(endpoint+'/json/close/'+target.id)}
}
main().catch(e=>{console.error(e);process.exitCode=1});
