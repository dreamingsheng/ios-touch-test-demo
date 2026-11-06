(() => {
  'use strict';
  const $ = s => document.querySelector(s);
  const stage = $('#stage'), canvas = $('#surface'), overlay = $('#overlay'), panel = $('#modePanel');
  const ctx = canvas.getContext('2d'), octx = overlay.getContext('2d');
  const active = new Map(), trails = new Map();
  const palette = ['#39d7ff','#ff5b69','#47e68b','#ffd166','#b388ff','#ff8f4c','#56c7ff','#ff77b7','#89f06d','#f5ef71'];
  const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent)||(navigator.platform==='MacIntel'&&navigator.maxTouchPoints>1);
  const isStandalone = window.touchTestNative === true || matchMedia('(display-mode: standalone)').matches || matchMedia('(display-mode: fullscreen)').matches || navigator.standalone === true;
  const copy = {
    multi:['多点轨迹','多根手指同时滑动，检查断线、跳点和最大触点数'],
    draw:['自由画画','用一根或多根手指连续绘画，观察断线和异常笔迹'],
    line:['引导划线','沿横线、竖线和斜线反复描画，覆盖率越高越好'],
    ghost:['鬼点监测','请勿触摸测试区域；自动记录意外触控事件'],
    auto:['自动跟随','按住并跟随移动靶点，统计连续跟随误差'],
    grid:['坏点网格','涂满 12×24 网格；未变绿区域可能是触控盲区'],
    edge:['边缘测试','沿屏幕四边滑动，点亮全部 80 个边缘段'],
    pinch:['图片拖拽缩放','单指拖拽，双指缩放，检查手势是否顺滑'],
    map:['地图手势','像地图一样单指平移、双指缩放并观察跳动'],
    read:['阅读翻页','默认上下连续阅读；也可切换左右翻页，测试滚动、点击和字号调节'],
    video:['短视频滑动','上下滑动切换视频，测试进度条、点赞和连续手势'],
    moba:['MOBA 轮盘','左手轮盘移动，同时按右侧技能键测试多点并发'],
    aim:['射击瞄准','左手移动、右侧拖动准星并同时点击开火'],
    ui:['设置切换','测试开关、分段按钮、滑块、选择框和页面滚动'],
    menu:['多级设置菜单','进入多级菜单、返回、切换开关并测试长列表滚动'],
    type:['键盘打字','点击输入框调出键盘，测试连续输入、删除和中英文切换'],
    cross:['十字轴与光标','左半区测试大十字轴，右半区移动光标，可同时多指'],
    tap:['点击精度','准确点击黄色圆靶，记录中心偏差'],
    hold:['长按漂移','按住蓝色圆圈不要移动，测量坐标漂移'],
    colors:['显示色彩','轻点切换黑白红绿蓝灰，观察坏点与色斑'],
    bars:['标准色条','观察颜色、灰阶和显示异常']
  };

  let mode = 'multi', maxTouches = 0, eventBucket = 0, modeTimer = null, animationToken = 0;
  let gridCells = [], edgeSegments = [], lineHit = new Set(), ghostCount = 0, ghostLeft = 20;
  let tapHits = 0, tapTotal = 0, hold = null, gesture = null, joystickId = null, aimId = null, crossIds = {axis:null,cursor:null};
  let skillPointers = new Map(), shots = 0, autoScore = {sum:0,count:0}, sceneSwipe = null, readPage = 0, videoIndex = 0;
  let videoStates=[],videoPaused=false,videoMediaState='loading',videoMediaError='',readMode='vertical';
  let photoState={source:'./assets/lake-photo-v1.png',name:'内置湖景',objectUrl:null};
  let immersivePreferred=true,layoutDrag=null,joystickHomeStyle=null;
  let hudLayouts={};try{hudLayouts=JSON.parse(localStorage.getItem('touch-hud-layouts')||'{}')}catch(_){}
  const layoutKey=()=>mode+':'+(innerWidth>innerHeight?'landscape':'portrait');
  function restoreHudLayout(){const saved=hudLayouts[layoutKey()]||{},r=stage.getBoundingClientRect();panel.querySelectorAll('[data-layout-key]').forEach(el=>{const p=saved[el.dataset.layoutKey];el.style.translate=p?`${p.x*r.width}px ${p.y*r.height}px`:''})}
  function startLayoutDrag(e){
    if(!document.body.classList.contains('layout-edit'))return false;
    const el=e.target.closest('[data-layout-key]');if(!el)return true;
    e.preventDefault();stage.setPointerCapture?.(e.pointerId);
    const r=el.getBoundingClientRect(),s=stage.getBoundingClientRect(),saved=hudLayouts[layoutKey()]?.[el.dataset.layoutKey]||{x:0,y:0};
    layoutDrag={id:e.pointerId,el,x:e.clientX,y:e.clientY,dx:saved.x*s.width,dy:saved.y*s.height,rect:r,stage:s};return true;
  }
  function moveLayoutDrag(e){if(layoutDrag?.id!==e.pointerId)return false;e.preventDefault();const d=layoutDrag,dx=Math.max(d.stage.left-d.rect.left,Math.min(d.stage.right-d.rect.right,e.clientX-d.x)),dy=Math.max(d.stage.top-d.rect.top,Math.min(d.stage.bottom-d.rect.bottom,e.clientY-d.y));d.el.style.translate=`${d.dx+dx}px ${d.dy+dy}px`;d.position={x:(d.dx+dx)/d.stage.width,y:(d.dy+dy)/d.stage.height};return true}
  function finishLayoutDrag(e){if(layoutDrag?.id!==e.pointerId)return false;const d=layoutDrag;if(d.position){hudLayouts[layoutKey()]??={};hudLayouts[layoutKey()][d.el.dataset.layoutKey]=d.position;try{localStorage.setItem('touch-hud-layouts',JSON.stringify(hudLayouts))}catch(_){}}layoutDrag=null;return true}
  const sessionStarted=new Date().toISOString(), sampleLimit=10000, samples=[], modeResults=new Map();
  let sampleCount=0,nextTouchOrder=1;
  function recordSample(e,p,phase,source='dispatched'){
    sampleCount++;
    if(samples.length>=sampleLimit)return;
    const r=stage.getBoundingClientRect();
    samples.push({mode,phase,source,pointerId:e.pointerId,pointerType:e.pointerType||'unknown',trusted:e.isTrusted===true,timeStamp:Number.isFinite(e.timeStamp)?e.timeStamp:performance.now(),x:p.x,y:p.y,pressure:p.pressure,contactWidth:p.contactWidth,contactHeight:p.contactHeight,stageWidth:r.width,stageHeight:r.height});
  }
  function snapshotMode(){modeResults.set(mode,{name:copy[mode][0],observedAt:new Date().toISOString(),metrics:Array.from({length:4},(_,i)=>({label:$(`#l${i}`).textContent,value:$(`#v${i}`).textContent})),verdict:'未人工验收'})}
  function reportData(includeSamples=false){
    const data={version:15,startedAt:sessionStarted,exportedAt:new Date().toISOString(),deviceNotes:$('#reportDevice').value,environment:{userAgent:navigator.userAgent,platform:navigator.platform,pixelRatio:devicePixelRatio,viewport:[innerWidth,innerHeight],standalone:isStandalone,coalescedEventsAvailable:typeof PointerEvent!=='undefined'&&typeof PointerEvent.prototype.getCoalescedEvents==='function'},limits:{coordinateUnit:'CSS px relative to test stage',timeUnit:'browser event timeStamp in ms; system/browser processed input, not IC raw reports',sampleLimit,retained:samples.length,totalObserved:sampleCount,dropped:sampleCount-samples.length,hardwareVerdict:'未人工验收'},modes:[...modeResults.entries()].map(([key,value])=>({key,...value}))};
    if(includeSamples)data.samples=samples;return data;
  }
  function refreshReport(){snapshotMode();$('#reportPreview').value=JSON.stringify(reportData(),null,2);$('#reportStatus').textContent=`保留 ${samples.length} / ${sampleCount} 条采样 · 丢弃 ${sampleCount-samples.length} 条（上限 ${sampleLimit}）`}
  function openReport(){cancelActive();refreshReport();const dialog=$('#reportDialog');if(typeof dialog.showModal==='function')dialog.showModal();else dialog.setAttribute('open','')}
  function downloadReport(format){
    refreshReport();let content,type;
    if(format==='json'){content=JSON.stringify(reportData(true),null,2);type='application/json'}
    else{const keys=['mode','phase','source','pointerId','pointerType','trusted','timeStamp','x','y','pressure','contactWidth','contactHeight','stageWidth','stageHeight'];const cell=value=>'"'+String(value??'').replaceAll('"','""')+'"';content=keys.join(',')+'\r\n'+samples.map(row=>keys.map(key=>cell(row[key])).join(',')).join('\r\n');type='text/csv;charset=utf-8'}
    const filename='touch-test-'+sessionStarted.replaceAll(':','-')+'.'+format;
    if(window.touchTestNative&&window.webkit?.messageHandlers?.touchTestNative){window.webkit.messageHandlers.touchTestNative.postMessage({action:'export',content,filename});return}
    const blob=new Blob([content],{type}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=filename;document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),30000);
  }

  function syncViewport(){
    const vv = window.visualViewport;
    const focused=document.activeElement,type=(focused?.getAttribute?.('type')||'text').toLowerCase();
    const textInput=focused?.matches?.('textarea,[contenteditable]:not([contenteditable="false"]),input:not([type])')||focused?.matches?.('input')&&['text','search','email','url','tel','password','number'].includes(type);
    const keyboardTarget=!!textInput&&focused?.getAttribute?.('inputmode')!=='none';
    const layoutHeight=Math.max(document.documentElement.clientHeight||0,innerHeight||0);
    const keyboardCompressed=keyboardTarget&&vv&&vv.height>0&&vv.height<layoutHeight-80;
    const root=document.documentElement;
    if(keyboardCompressed){root.style.setProperty('--app-height',`${Math.round(vv.height)}px`);root.style.setProperty('--app-top',`${Math.round(vv.offsetTop||0)}px`);root.dataset.viewportMode='keyboard'}
    else{root.style.removeProperty('--app-height');root.style.removeProperty('--app-top');root.dataset.viewportMode='dynamic'}
    if(isIOS&&isStandalone&&!window.touchTestNative&&Math.min(screen.width,screen.height)<500&&Math.max(screen.width,screen.height)>=812){
      const landscape=innerWidth>innerHeight,root=document.documentElement.style;
      root.setProperty('--fallback-safe-top',landscape?'0px':'59px');root.setProperty('--fallback-safe-bottom',landscape?'21px':'34px');root.setProperty('--fallback-safe-left',landscape?'59px':'0px');root.setProperty('--fallback-safe-right',landscape?'59px':'0px');
    }
    resize();
  }
  function applySafeInsets(){const root=document.documentElement.style;for(const side of ['top','bottom']){const value=Math.max(0,Math.min(100,+$(`#${side}Inset`).value||0));root.setProperty(`--manual-${side}`,value+'px');$(`#${side}InsetValue`).textContent=value}try{localStorage.setItem('touch-safe-insets',JSON.stringify({top:$('#topInset').value,bottom:$('#bottomInset').value}))}catch(_){}syncViewport();$('#safeMetrics').textContent='额外边距只调整内容区，背景和系统状态栏保持透明。'}
  function resize(){
    const r = stage.getBoundingClientRect(), p = Math.min(devicePixelRatio || 1, 3);
    if(canvas.width===Math.max(1,Math.round(r.width*p))&&canvas.height===Math.max(1,Math.round(r.height*p)))return;
    for(const c of [canvas, overlay]){c.width=Math.max(1,Math.round(r.width*p));c.height=Math.max(1,Math.round(r.height*p));c.style.width=r.width+'px';c.style.height=r.height+'px'}
    ctx.setTransform(p,0,0,p,0,0);octx.setTransform(p,0,0,p,0,0);
    if(mode==='line') drawGuides();
    if(mode==='hold') placeHold();
  }
  function pos(e){const r=stage.getBoundingClientRect();return{x:e.clientX-r.left,y:e.clientY-r.top}}
  function pointFromEvent(e, previous={}){
    const width=Number.isFinite(e.width)&&e.width>0?e.width:(previous.contactWidth||1);
    const height=Number.isFinite(e.height)&&e.height>0?e.height:(previous.contactHeight||1);
    return {...previous,...pos(e),contactWidth:width,contactHeight:height,radius:Math.max(1,(width+height)/4),pressure:Number.isFinite(e.pressure)?e.pressure:(previous.pressure||0),timeStamp:e.timeStamp};
  }
  function movementSamples(e){
    let samples=[];
    try{samples=typeof e.getCoalescedEvents==='function'?e.getCoalescedEvents():[]}catch(_){samples=[]}
    if(!samples.length)return[e];
    return samples;
  }
  function setStats(labels, values=['0','0','0','—']){for(let i=0;i<4;i++){ $(`#l${i}`).textContent=labels[i]; $(`#v${i}`).textContent=values[i] }}
  function val(i,value){$(`#v${i}`).textContent=value}
  function showPanel(html, transparent=false){panel.className='show';panel.style.background=transparent?'transparent':'';panel.innerHTML=html}
  function hidePanel(){panel.className='';panel.style.background='';panel.innerHTML='';panel.onclick=null}
  function clearCanvases(){ctx.clearRect(0,0,canvas.width,canvas.height);octx.clearRect(0,0,overlay.width,overlay.height)}
  function drawPoint(p,color){const r=stage.getBoundingClientRect(),rx=Math.max(18,(p.contactWidth||18)/2),ry=Math.max(18,(p.contactHeight||18)/2);octx.save();octx.strokeStyle=color+'66';octx.lineWidth=1;octx.beginPath();octx.moveTo(p.x,0);octx.lineTo(p.x,r.height);octx.moveTo(0,p.y);octx.lineTo(r.width,p.y);octx.stroke();octx.beginPath();octx.ellipse(p.x,p.y,rx,ry,0,0,Math.PI*2);octx.fillStyle=color+'55';octx.fill();octx.lineWidth=2;octx.strokeStyle=color;octx.stroke();octx.fillStyle='#fff';octx.font='bold 14px -apple-system';octx.textAlign='center';octx.fillText(String(p.order),p.x,p.y+5);octx.textAlign='left';octx.font='10px ui-monospace,monospace';octx.fillText(`${Math.round(p.x)},${Math.round(p.y)} P${(p.pressure||0).toFixed(2)}`,Math.max(3,Math.min(r.width-130,p.x+rx+4)),Math.max(12,p.y-ry-4));octx.restore()}
  function redrawOverlay(){octx.clearRect(0,0,overlay.width,overlay.height);if(['multi','draw','line','auto','ghost'].includes(mode))for(const p of active.values())drawPoint(p,p.color)}
  function drawTrail(a,b,color,width=4){ctx.beginPath();ctx.moveTo(a.x,a.y);ctx.lineTo(b.x,b.y);ctx.lineWidth=width;ctx.lineCap='round';ctx.strokeStyle=color;ctx.stroke()}
  function updateTouchStats(){if(['multi','draw','line'].includes(mode)){val(0,active.size);val(1,maxTouches)}}

  function pointerDown(e){
    if(['moba','aim'].includes(mode)&&startLayoutDrag(e))return;
    if(['ui','menu','type'].includes(mode)) return;
    if(mode==='read'&&readMode==='vertical')return;
    if(mode==='video'&&$('.video-sheet'))return;
    if(e.target.closest('button,input,textarea,select,label') && !e.target.closest('.fire')) return;
    e.preventDefault(); stage.setPointerCapture?.(e.pointerId);
    const order=nextTouchOrder++;const p={...pointFromEvent(e),order,color:palette[(order-1)%palette.length],start:performance.now()};
    recordSample(e,p,'down');
    active.set(e.pointerId,p);trails.set(e.pointerId,p);maxTouches=Math.max(maxTouches,active.size);eventBucket++;updateTouchStats();
    if(mode==='ghost') registerGhost();
    if(['multi','draw','line'].includes(mode)){ctx.beginPath();ctx.arc(p.x,p.y,mode==='draw'?3:2,0,Math.PI*2);ctx.fillStyle=p.color;ctx.fill()}
    if(mode==='tap') scoreTap(p);
    if(mode==='hold') startHold(e.pointerId,p);
    if(mode==='pinch'||mode==='map') gesture.last=gestureSnapshot();
    if(mode==='moba') gameDown(e,p,false);
    if(mode==='aim') gameDown(e,p,true);
    if(mode==='cross') crossDown(e.pointerId,p);
    if(mode==='read'||mode==='video')sceneSwipe={id:e.pointerId,startX:p.x,startY:p.y,x:p.x,y:p.y};
    redrawOverlay();
  }
  function pointerMove(e,record=true){
    if(moveLayoutDrag(e))return;
    if(!active.has(e.pointerId))return;e.preventDefault();
    const previous=active.get(e.pointerId);let old=previous,p=old;
    const movement=movementSamples(e);
    for(const sample of movement){
      p=pointFromEvent(sample,old);if(record)eventBucket++;
      if(record)recordSample(sample,p,'move',sample===e?'dispatched':'coalesced');
      if(mode==='multi'||mode==='draw'||mode==='line'){drawTrail(old,p,p.color,mode==='draw'?6:4);if(mode==='line')scoreLine(p)}
      if(mode==='grid')hitGrid(p);
      if(mode==='edge')hitEdge(p);
      old=p;
    }
    active.set(e.pointerId,p);
    trails.set(e.pointerId,p);
    if(mode==='pinch'||mode==='map') updateGesture();
    if(mode==='moba') gameMove(e.pointerId,p,false);
    if(mode==='aim') gameMove(e.pointerId,p,true,previous);
    if(mode==='cross') crossMove(e.pointerId,p);
    if(mode==='hold') updateHold(e.pointerId,p);
    if(sceneSwipe?.id===e.pointerId){sceneSwipe.x=p.x;sceneSwipe.y=p.y}
    redrawOverlay();
  }
  function pointerUp(e){
    if(finishLayoutDrag(e))return;
    const p=active.get(e.pointerId);if(!p)return;eventBucket++;
    if(e.type==='pointerup'&&Number.isFinite(e.clientX)&&Number.isFinite(e.clientY)){
      const end=pointFromEvent(e,p);
      if(end.x!==p.x||end.y!==p.y)pointerMove(e,false);
    }
    recordSample(e,e.type==='pointerup'?pointFromEvent(e,active.get(e.pointerId)):active.get(e.pointerId),e.type==='pointerup'?'up':'cancel');
    if(mode==='hold') endHold(e.pointerId,p);
    if(mode==='moba'||mode==='aim') gameUp(e.pointerId);
    if(mode==='cross') crossUp(e.pointerId);
    if(sceneSwipe?.id===e.pointerId){if(e.type==='pointercancel'||e.type==='lostpointercapture')sceneSwipe=null;else finishSceneSwipe()}
    active.delete(e.pointerId);trails.delete(e.pointerId);
    if(['ghost','auto'].includes(mode))val(mode==='ghost'?1:0,active.size);
    if(mode==='hold')val(3,active.size);
    if((mode==='pinch'||mode==='map')&&gesture)gesture.last=gestureSnapshot();
    if(mode==='pinch'||mode==='map')renderGesture();
    updateTouchStats();redrawOverlay();
  }

  function drawGuides(){const r=stage.getBoundingClientRect();ctx.save();ctx.strokeStyle='#ffffff35';ctx.lineWidth=18;ctx.setLineDash([14,12]);for(const [a,b] of [[{x:0,y:r.height/2},{x:r.width,y:r.height/2}],[{x:r.width/2,y:0},{x:r.width/2,y:r.height}],[{x:0,y:r.height*.18},{x:r.width,y:r.height*.82}]]){ctx.beginPath();ctx.moveTo(a.x,a.y);ctx.lineTo(b.x,b.y);ctx.stroke()}ctx.restore()}
  function scoreLine(p){const r=stage.getBoundingClientRect(), near=[];if(Math.abs(p.y-r.height/2)<24)near.push(['h',p.x/r.width]);if(Math.abs(p.x-r.width/2)<24)near.push(['v',p.y/r.height]);const expected=r.height*.18+(p.x/r.width)*r.height*.64;if(Math.abs(p.y-expected)<24)near.push(['d',p.x/r.width]);for(const [g,t] of near)lineHit.add(`${g}:${Math.max(0,Math.min(49,Math.floor(t*50)))}`);val(3,Math.round(lineHit.size/150*100)+'%')}

  function buildGhost(){ghostCount=0;ghostLeft=20;const deadline=performance.now()+20000;showPanel('<div class="ghost-card" id="ghostCard"><span>前台观察剩余时间</span><strong id="ghostTime">20s</strong><p id="ghostText">请将手机平放并且不要触摸测试区</p><small>仅记录网页测试区内的触控；未发现输入不等于硬件完全正常。</small></div>');setStats(['意外触点','当前触点','事件/秒','倒计时'],['0','0','0','20s']);modeTimer=setInterval(()=>{ghostLeft=Math.max(0,Math.ceil((deadline-performance.now())/1000));val(3,ghostLeft+'s');$('#ghostTime').textContent=ghostLeft+'s';if(ghostLeft<=0){clearInterval(modeTimer);modeTimer=null;$('#ghostText').textContent=ghostCount===0?'观察结束：20 秒内未记录到触控':'观察结束：记录到 '+ghostCount+' 次触控';$('#message').textContent=$('#ghostText').textContent}},200)}
  function registerGhost(){if(ghostLeft<=0)return;ghostCount++;val(0,ghostCount);val(1,active.size);$('#ghostCard')?.classList.add('bad');if($('#ghostText'))$('#ghostText').textContent=`检测到第 ${ghostCount} 次意外触控`}

  function buildAuto(){autoScore={sum:0,count:0};showPanel('<div class="auto-card"><span>跟随靶点移动</span><strong id="autoError">—</strong><p>手指保持按住黄色圆点，系统自动扫描全屏</p></div>',true);setStats(['当前触点','采样数','事件/秒','平均误差'],['0','0','0','—']);$('#target').style.display='block';const token=++animationToken;const loop=()=>{if(token!==animationToken||mode!=='auto')return;const r=stage.getBoundingClientRect(),t=performance.now()/1000,x=r.width*(.5+.38*Math.sin(t*.83)),y=r.height*(.5+.35*Math.sin(t*1.27+1));const el=$('#target');el.style.left=x+'px';el.style.top=y+'px';const first=active.values().next().value;if(first){const d=Math.hypot(first.x-x,first.y-y);autoScore.sum+=d;autoScore.count++;const avg=autoScore.sum/autoScore.count;val(0,active.size);val(1,autoScore.count);val(3,avg.toFixed(1)+'px');$('#autoError').textContent=avg.toFixed(1)+'px'}requestAnimationFrame(loop)};requestAnimationFrame(loop)}

  function buildGrid(){showPanel('<div id="grid"></div>');gridCells=[];const g=$('#grid');for(let i=0;i<288;i++){const c=document.createElement('div');c.className='cell';g.append(c);gridCells.push(c)}setStats(['当前触点','已覆盖','事件/秒','完成度'],['0','0/288','0','0%'])}
  function hitGrid(p){const r=stage.getBoundingClientRect(),col=Math.max(0,Math.min(11,Math.floor(p.x/r.width*12))),row=Math.max(0,Math.min(23,Math.floor(p.y/r.height*24)));gridCells[row*12+col]?.classList.add('hit');const n=gridCells.filter(c=>c.classList.contains('hit')).length;val(0,active.size);val(1,`${n}/288`);val(3,Math.round(n/288*100)+'%')}
  function buildEdge(){showPanel('<div id="edge"></div>');edgeSegments=[];const box=$('#edge'),n=20,t=18;for(const side of ['top','bottom','left','right'])for(let i=0;i<n;i++){const el=document.createElement('div');el.className='edge-seg';el.dataset.side=side;el.dataset.i=i;if(side==='top'||side==='bottom'){el.style.left=i/n*100+'%';el.style.width=100/n+'%';el.style.height=t+'px';el.style[side]=0}else{el.style.top=i/n*100+'%';el.style.height=100/n+'%';el.style.width=t+'px';el.style[side]=0}box.append(el);edgeSegments.push(el)}setStats(['当前触点','已点亮','事件/秒','剩余'],['0','0/80','0','80'])}
  function hitEdge(p){const r=stage.getBoundingClientRect(),t=34,n=20,marks=[];if(p.y<t)marks.push(['top',Math.floor(p.x/r.width*n)]);if(p.y>r.height-t)marks.push(['bottom',Math.floor(p.x/r.width*n)]);if(p.x<t)marks.push(['left',Math.floor(p.y/r.height*n)]);if(p.x>r.width-t)marks.push(['right',Math.floor(p.y/r.height*n)]);for(const [s,i] of marks)edgeSegments.find(x=>x.dataset.side===s&&+x.dataset.i===Math.max(0,Math.min(n-1,i)))?.classList.add('hit');const done=edgeSegments.filter(x=>x.classList.contains('hit')).length;val(0,active.size);val(1,`${done}/80`);val(3,80-done)}

  function buildGesture(kind){gesture={x:0,y:0,scale:kind==='map'?.65:1,last:null};if(kind==='map'){
    showPanel('<div class="map-canvas"><div class="transform-world map-world" id="transformWorld"><i class="map-pin p1"></i><i class="map-pin p2"></i><i class="map-pin p3"></i></div><form class="map-search" id="mapSearch"><span>⌕</span><input id="mapQuery" type="search" placeholder="搜索地图" aria-label="搜索地图"><button>搜索</button></form><button class="map-locate" id="mapLocate" aria-label="回到当前位置">◎</button><div class="map-sheet"><span class="sheet-grip"></span><h3 id="mapPlace">探索附近</h3><p id="mapDetail">离线手势测试地图 · 不使用真实定位</p><div><button id="mapRoute">路线</button><button id="mapFavorite">收藏</button></div></div></div>');
    $('#mapSearch').onsubmit=e=>{e.preventDefault();gesture.x=-70;gesture.y=50;gesture.scale=1;renderGesture();$('#mapPlace').textContent=$('#mapQuery').value.trim()||'东方公园';$('#mapDetail').textContent='步行 800 米 · 约 10 分钟（测试数据）'};
    $('#mapLocate').onclick=()=>{gesture.x=gesture.y=0;gesture.scale=.65;renderGesture();$('#mapPlace').textContent='当前位置（测试）'};
    $('#mapRoute').onclick=()=>{$('#mapDetail').textContent='路线已展开 · 可继续双指缩放';$('#transformWorld').classList.toggle('route-visible')};
    $('#mapFavorite').onclick=e=>{e.currentTarget.classList.toggle('selected');e.currentTarget.textContent=e.currentTarget.classList.contains('selected')?'已收藏':'收藏'};
  }else{
    showPanel('<div class="photo-tools"><button id="photoBuiltIn">内置图</button><label class="photo-file">选择本地图片<input id="photoFile" type="file" accept="image/*"></label><label>大小 <input id="photoSize" type="range" min="50" max="150" value="100"></label><span id="photoName"></span></div><div class="transform-world photo-world" id="transformWorld"><img id="photoImage" alt="触控缩放测试图片"></div>');
    const image=$('#photoImage'),size=$('#photoSize');image.src=photoState.source;$('#photoName').textContent=photoState.name;
    $('#photoBuiltIn').onclick=()=>{photoState.source='./assets/lake-photo-v1.png';photoState.name='内置湖景';image.src=photoState.source;$('#photoName').textContent=photoState.name};
    $('#photoFile').onchange=e=>{const file=e.target.files?.[0];if(!file)return;if(photoState.objectUrl)URL.revokeObjectURL(photoState.objectUrl);photoState.objectUrl=URL.createObjectURL(file);photoState.source=photoState.objectUrl;photoState.name=file.name;image.src=photoState.source;$('#photoName').textContent=photoState.name};
    size.oninput=()=>{gesture.baseScale=+size.value/100;renderGesture()};gesture.baseScale=1;
  }setStats(['触点','缩放','事件/秒','平移'],['0',gesture.scale.toFixed(2)+'×','0','0,0']);renderGesture()}
  function gestureSnapshot(){const pts=[...active.values()];if(!pts.length)return null;const center=pts.reduce((a,p)=>({x:a.x+p.x/pts.length,y:a.y+p.y/pts.length}),{x:0,y:0});return{count:pts.length,center,dist:pts.length>1?Math.hypot(pts[0].x-pts[1].x,pts[0].y-pts[1].y):0}}
  function updateGesture(){
    const now=gestureSnapshot(),last=gesture.last;
    if(now&&last){
      const r=stage.getBoundingClientRect();let scale=gesture.scale;
      if(now.count>1&&last.count>1&&last.dist>4)scale=Math.max(.25,Math.min(5,gesture.scale*now.dist/last.dist));
      const ratio=scale/gesture.scale;
      // Keep the content under the previous finger centroid under the new centroid.
      gesture.x=now.center.x-r.width/2-(last.center.x-r.width/2-gesture.x)*ratio;
      gesture.y=now.center.y-r.height/2-(last.center.y-r.height/2-gesture.y)*ratio;
      gesture.scale=scale;renderGesture();
    }
    gesture.last=now;
  }
  function renderGesture(){const w=$('#transformWorld');if(!w)return;const displayScale=gesture.scale*(gesture.baseScale||1);w.style.transform=`translate(-50%,-50%) translate(${gesture.x}px,${gesture.y}px) scale(${displayScale})`;val(0,active.size);val(1,displayScale.toFixed(2)+'×');val(3,`${Math.round(gesture.x)},${Math.round(gesture.y)}`)}

  const readingPages=[
    ['第一章 · 触摸与反馈','手指落在屏幕上，细微的移动被设备转换成连续坐标。可靠的触控应该保持轨迹连贯，不突然跳跃，也不在抬手之后继续产生输入。\n\n左右滑动进入下一页，并观察快速翻页时是否出现停顿或误触。'],
    ['第二章 · 多点协作','双指缩放、游戏轮盘与虚拟按键都依赖多个触点同时存在。每个触点必须拥有独立身份，移动和抬起不能影响其他手指。\n\n本测试把阅读场景与底层采样分开，便于发现滑动、点击和边缘返回区域的问题。'],
    ['第三章 · 边缘与稳定','屏幕边缘往往最容易出现响应迟缓。请从左右两边开始翻页，再尝试短距离、慢速和快速滑动。\n\n完成阅读后，可以进入边缘、网格与长按测试进一步定位问题。']
  ];
  function buildRead(){readPage=0;readMode='vertical';showPanel('<div class="reader"><div class="reader-bar"><button id="fontDown">A−</button><span>Touch Test 阅读</span><button id="readMode">横向翻页</button><button id="fontUp">A＋</button></div><article id="readerPage"></article><div class="page-dots" id="pageDots"></div></div>');setStats(['章节','翻页次数','事件/秒','手势'],['全部 3 章','0','0','上下滚动']);let font=18;const article=$('#readerPage');$('#fontDown').onclick=()=>{font=Math.max(14,font-2);article.style.fontSize=font+'px'};$('#fontUp').onclick=()=>{font=Math.min(28,font+2);article.style.fontSize=font+'px'};$('#readMode').onclick=()=>{readMode=readMode==='vertical'?'horizontal':'vertical';readPage=0;panel.dataset.turns='0';renderRead()};panel.dataset.turns='0';renderRead()}
  function renderRead(){const article=$('#readerPage');if(!article)return;const vertical=readMode==='vertical';$('.reader').classList.toggle('horizontal',!vertical);$('#readMode').textContent=vertical?'横向翻页':'上下阅读';if(vertical){article.innerHTML=readingPages.map(page=>`<section><h2>${page[0]}</h2>${page[1].split('\n\n').map(x=>`<p>${x}</p>`).join('')}</section>`).join('');$('#pageDots').innerHTML='';val(0,`全部 ${readingPages.length} 章`);val(3,'上下滚动')}else{const page=readingPages[readPage];article.innerHTML=`<section><h2>${page[0]}</h2>${page[1].split('\n\n').map(x=>`<p>${x}</p>`).join('')}</section>`;$('#pageDots').innerHTML=readingPages.map((_,i)=>`<i class="${i===readPage?'on':''}"></i>`).join('');val(0,`${readPage+1}/${readingPages.length}`);val(3,'左右滑动')}article.scrollTop=0}
  function buildVideo(){
    videoIndex=0;videoPaused=false;videoMediaState='loading';videoMediaError='';videoStates=Array.from({length:4},()=>({progress:0,liked:false,comments:[]}));
    showPanel('<div class="video-feed" id="videoFeed"><video id="feedVideo" src="./assets/flower-cc0.mp4" autoplay muted loop playsinline preload="auto"></video><div class="video-scene" id="videoScene"><span id="playState">加载中…</span></div><button id="videoRetry" hidden>重试播放</button><div class="feed-tabs"><button>关注</button><button class="chosen">推荐</button><button>⌕</button></div><div class="video-side"><button class="feed-avatar" aria-label="个人资料">T<small>＋</small></button><button data-video-action="like" aria-label="点赞">♥<small id="likeCount">128</small></button><button data-video-action="comment">●<small>评论</small></button><button data-video-action="share">➦<small>分享</small></button><i class="music-disc">♫</i></div><div class="video-caption"><b id="videoUser"></b><p id="videoText"></p><small>♫ 原声 · 本地播放测试</small><input id="videoProgress" aria-label="播放进度" type="range" min="0" max="100" step="0.1" value="0"></div><div class="feed-bottom"><span>首页</span><span>朋友</span><button data-feed-plus>＋</button><span>消息</span><span>我</span></div><div id="videoSheetHost"></div></div>');
    setStats(['当前视频','切换次数','事件/秒','进度'],['1/4','0','0','0%']);panel.dataset.turns='0';
    panel.querySelector('[data-video-action="like"]').onclick=()=>{videoStates[videoIndex].liked=!videoStates[videoIndex].liked;renderVideo()};
    panel.querySelector('[data-video-action="comment"]').onclick=()=>openVideoSheet('comment');
    panel.querySelector('[data-video-action="share"]').onclick=()=>openVideoSheet('share');
    const bottom=$('.feed-bottom');bottom.querySelectorAll('span').forEach(item=>{const button=document.createElement('button');button.dataset.feedTab=item.textContent;button.textContent=item.textContent;item.replaceWith(button);button.onclick=()=>openFeedPage(button.dataset.feedTab)});
    $('.feed-avatar').onclick=()=>openFeedPage('我');$('.feed-tabs').querySelectorAll('button').forEach(tab=>{tab.style.cursor='pointer';tab.onclick=()=>{if(tab.textContent==='⌕')openFeedPage('搜索');else{panel.querySelectorAll('.feed-tabs button').forEach(x=>x.classList.toggle('chosen',x===tab));$('#videoText').textContent=tab.textContent==='关注'?'已关注的测试创作者':'推荐 · 本地视频片段'}}});
    const video=$('#feedVideo');video.muted=true;video.addEventListener('loadedmetadata',updateVideoMediaUI);video.addEventListener('canplay',()=>{videoMediaState='ready';videoMediaError='';updateVideoMediaUI()});video.addEventListener('playing',()=>{videoMediaState='ready';videoMediaError='';updateVideoMediaUI()});video.addEventListener('waiting',()=>{if(!videoPaused){videoMediaState='loading';updateVideoMediaUI()}});video.addEventListener('stalled',()=>{if(!videoPaused){videoMediaState='loading';updateVideoMediaUI()}});video.addEventListener('error',()=>{videoMediaState='error';videoMediaError=video.error?.message||`媒体错误 ${video.error?.code||'未知'}`;updateVideoMediaUI()});$('#videoRetry').onclick=retryVideo;
    panel.querySelector('[data-feed-plus]').onclick=()=>openVideoSheet('comment');
    $('#videoProgress').oninput=e=>{videoStates[videoIndex].progress=+e.target.value;if(Number.isFinite(video.duration))video.currentTime=video.duration*(+e.target.value)/100;renderVideoProgress()};
    modeTimer=setInterval(()=>{if(!videoPaused&&!document.hidden&&!$('.video-sheet')&&!active.size){const s=videoStates[videoIndex];s.progress=Number.isFinite(video.duration)?video.currentTime/video.duration*100:0;renderVideoProgress()}},100);
    renderVideo();
  }
  function renderVideoProgress(){const s=videoStates[videoIndex];if(!s||!$('#videoProgress'))return;$('#videoProgress').value=s.progress;val(3,s.progress.toFixed(0)+'%')}
  function updateVideoMediaUI(){const state=$('#playState'),retry=$('#videoRetry'),feed=$('#videoFeed');if(!state||!retry||!feed)return;retry.hidden=videoMediaState!=='error';if(videoMediaState==='error'){state.textContent='视频加载失败';state.title=retry.title=videoMediaError}else if(videoMediaState==='loading'){state.textContent='加载中…';state.title='正在缓冲视频'}else if(videoPaused){state.textContent='▶';state.title='已暂停'}else{state.textContent='播放中 · 轻点暂停';state.title=''}feed.classList.toggle('paused',videoPaused);feed.classList.toggle('media-loading',videoMediaState==='loading');feed.classList.toggle('media-error',videoMediaState==='error')}
  function retryVideo(){const video=$('#feedVideo');if(!video)return;videoMediaState='loading';videoMediaError='';videoPaused=false;updateVideoMediaUI();video.load();const attempt=video.play();if(attempt?.catch)attempt.catch(error=>{videoMediaState='error';videoMediaError=error?.message||'无法开始播放';updateVideoMediaUI()})}
  function renderVideo(){const scene=$('#videoScene');if(!scene)return;$('#videoUser').textContent='@touch_test_'+(videoIndex+1);$('#videoText').textContent=['花园随拍','花朵特写','自然记录','午后光影'][videoIndex]+' · 本地视频片段';val(0,`${videoIndex+1}/4`);const state=videoStates[videoIndex],video=$('#feedVideo');panel.querySelector('[data-video-action="like"]').classList.toggle('liked',state.liked);$('#likeCount').textContent=state.liked?'129':'128';if(videoPaused)video.pause();else{const attempt=video.play();if(attempt?.catch)attempt.catch(error=>{videoMediaState='error';videoMediaError=error?.message||'无法开始播放';updateVideoMediaUI()})}updateVideoMediaUI();renderVideoProgress()}
  function openVideoSheet(kind){
    sceneSwipe=null;const host=$('#videoSheetHost');
    host.innerHTML='<section class="video-sheet" role="dialog" aria-modal="true" aria-label="'+(kind==='comment'?'评论':'分享')+'"><div class="sheet-heading"><b>'+(kind==='comment'?'评论':'分享测试')+'</b><button id="closeVideoSheet">关闭</button></div><div id="sheetBody"></div></section>';
    $('#closeVideoSheet').onclick=()=>{host.innerHTML=''};
    const body=$('#sheetBody');
    if(kind==='comment'){
      const list=document.createElement('div');list.className='comment-list';body.append(list);
      const draw=()=>{list.replaceChildren();const entries=videoStates[videoIndex].comments;for(const text of entries.slice(-3)){const p=document.createElement('p');p.textContent=text;list.append(p)}if(!entries.length)list.textContent='输入评论，测试打字与发送。'};draw();
      const form=document.createElement('form');form.innerHTML='<textarea id="videoComment" aria-label="评论内容" maxlength="200" placeholder="写下测试评论…"></textarea><button type="submit">发送</button>';body.append(form);
      form.onsubmit=e=>{e.preventDefault();const input=$('#videoComment'),text=input.value.trim();if(text){videoStates[videoIndex].comments.push(text);input.value='';draw()}};
    }else{
      body.innerHTML='<p>复制当前场景链接，在另一窗口测试打开。</p><button id="copyVideoLink">复制链接</button><p id="shareResult" role="status"></p>';
      $('#copyVideoLink').onclick=async()=>{const url=new URL(location.href);url.hash='video';try{await navigator.clipboard.writeText(url.href);$('#shareResult').textContent='链接已复制'}catch(_){$('#shareResult').textContent=url.href}};
    }
  }
  function openFeedPage(name){
    if(name==='首页'){videoIndex=0;renderVideo();return}
    openVideoSheet('share');$('.video-sheet').setAttribute('aria-label',name);$('.sheet-heading b').textContent=name;const body=$('#sheetBody');
    if(name==='我'){body.innerHTML='<div class="feed-profile"><div class="profile-circle">T</div><h2>触控测试用户</h2><p>测试号 touch_test · 本地操作场景</p><div class="profile-counts"><b>128 获赞</b><b>36 关注</b><b>256 粉丝</b></div><button id="editProfile">编辑资料</button></div>';$('#editProfile').onclick=()=>{body.innerHTML='<label>昵称<input id="profileName" value="触控测试用户" maxlength="20"></label><button id="saveProfile">保存</button>';$('#saveProfile').onclick=()=>{body.textContent='资料已保存：'+$('#profileName').value}}}
    else if(name==='搜索'){body.innerHTML='<form id="feedSearch"><input id="feedSearchText" type="search" placeholder="搜索测试内容"><button>搜索</button></form><p id="feedSearchResult">可测试键盘输入和搜索提交</p>';$('#feedSearch').onsubmit=e=>{e.preventDefault();$('#feedSearchResult').textContent='搜索：'+$('#feedSearchText').value+' · 共 4 条本地测试内容'}}
    else{body.innerHTML=['系统通知','测试助手','触控反馈'].map((x,i)=>`<button class="feed-list-item" data-detail="${i}"><i>${x[0]}</i><span>${x}<small>${name==='朋友'?'点击查看测试资料':'点击查看测试消息'}</small></span><b>›</b></button>`).join('');body.querySelectorAll('button').forEach(button=>button.onclick=()=>{body.textContent=name==='朋友'?'测试用户资料：可返回继续切换列表。':'测试消息详情：本地消息点击已响应。'})}
  }
  function finishSceneSwipe(){
    const s=sceneSwipe;sceneSwipe=null;if(!s)return;const dx=s.x-s.startX,dy=s.y-s.startY;
    if(mode==='read'&&readMode==='horizontal'&&Math.abs(dx)>55&&Math.abs(dx)>Math.abs(dy)){
      const next=Math.max(0,Math.min(readingPages.length-1,readPage+(dx<0?1:-1)));
      if(next!==readPage){readPage=next;panel.dataset.turns=String((+panel.dataset.turns||0)+1);val(1,panel.dataset.turns);renderRead()}
      val(3,dx<0?'向左翻页':'向右翻页');
    }
    if(mode==='video'){
      if(Math.abs(dy)>55&&Math.abs(dy)>Math.abs(dx)){videoIndex=(videoIndex+(dy<0?1:-1)+4)%4;panel.dataset.turns=String((+panel.dataset.turns||0)+1);val(1,panel.dataset.turns);videoPaused=false;renderVideo()}
      else if(Math.abs(dx)<8&&Math.abs(dy)<8){videoPaused=!videoPaused;renderVideo()}
    }
  }

  function gameHTML(aim=false){return `<div class="game ${aim?'shooter-game':'moba-game'}"><div class="game-top"><div class="mini-map"><i></i><i></i><i></i></div><div class="match-info">${aim?'<b>NW · 330 · N · 30 · NE</b><span>剩余 48 · 淘汰 3</span>':'<b><em>12</em>　VS　<em>9</em>　08:36</b><span>FPS 60　　训练场</span>'}</div><div class="game-status" id="ammoStatus">${aim?'40 / 180':'Lv. 15'}</div></div><div class="player-state"><span></span><i></i></div><div class="joystick" id="joyBase"><div class="joy-knob" id="joyKnob"></div></div>${aim?'<div class="aim-zone"></div><div class="crosshair" id="crosshair"></div><div class="weapon-bar" id="weaponBar">M416　40 / 180　　单发 / 连发</div><div class="shooter-stance"><div class="stance-control" data-stance="蹲下">蹲</div><div class="stance-control" data-stance="趴下">趴</div><div class="stance-control" data-stance="跳跃">跳</div></div><div class="fire" id="fire">开火</div>':'<div class="moba-commands"><div class="moba-action shop" data-moba-action="商店">商店</div><div class="moba-action score" data-moba-action="战绩">战绩</div><div class="moba-action signal" data-moba-action="信号">信号</div><div class="moba-action chat" data-moba-action="聊天">聊天</div><div class="moba-action upgrade" data-moba-action="升级">＋</div><div class="moba-action last-hit" data-moba-action="补刀">补刀</div><div class="moba-action tower" data-moba-action="推塔">推塔</div><div class="moba-action lock" data-moba-action="头像锁定">锁定</div></div><div class="moba-popover" id="mobaPopover" hidden></div><div class="skill-vector" id="castIndicator"></div><div class="skills"><div class="skill utility">闪现</div><div class="skill skill-one"><b>✦</b><small>斩击</small></div><div class="skill skill-two"><b>ϟ</b><small>突进</small></div><div class="skill skill-three"><b>✺</b><small>爆发</small></div><div class="skill big"><b>⚔</b><small>攻击</small></div></div><div class="moba-utilities"><div class="skill auxiliary">回城</div><div class="skill auxiliary">恢复</div></div>'}</div>`}
  function buildGame(aim=false){showPanel(gameHTML(aim));joystickId=aimId=null;skillPointers.clear();shots=0;joystickHomeStyle=null;setStats(['触点','左轴','事件/秒',aim?'开火':'技能'],['0','0,0','0','0']);if(aim){const r=stage.getBoundingClientRect(),c=$('#crosshair');c.style.left=r.width*.5+'px';c.style.top=r.height*.48+'px'}panel.querySelectorAll('.joystick,.mini-map,.match-info,.game-status,.player-state,.skill,.fire,.weapon-bar,.stance-control,.moba-action').forEach((el,i)=>el.dataset.layoutKey='control-'+i);restoreHudLayout();if(window.touchTestNative)window.webkit?.messageHandlers?.touchTestNative.postMessage({action:'orientation',value:'landscape'});else if(document.fullscreenElement)screen.orientation?.lock?.('landscape').catch(()=>{})}
  function activateMobaAction(action,control){const pop=$('#mobaPopover');if(!pop)return;panel.querySelectorAll('.moba-action.selected').forEach(x=>x.classList.remove('selected'));control?.classList.add('selected');pop.hidden=false;if(action==='商店')pop.innerHTML='<b>装备商店</b><button data-buy="攻速剑">攻速剑 250</button><button data-buy="防御甲">防御甲 300</button><button data-buy="移动靴">移动靴 200</button><small id="buyResult">点选装备测试连续点击</small>';else if(action==='战绩')pop.innerHTML='<b>对局战绩</b><p>12 击杀　9 死亡　18 助攻</p><button data-close-moba>返回战场</button>';else if(action==='信号')pop.innerHTML='<b>快捷信号</b><button data-signal="集合">集合</button><button data-signal="撤退">撤退</button><button data-signal="进攻">进攻</button><small id="buyResult">选择一个战术信号</small>';else if(action==='聊天')pop.innerHTML='<b>快捷聊天</b><button data-chat="收到">收到</button><button data-chat="保护我方防御塔">保护防御塔</button><button data-chat="干得漂亮">干得漂亮</button><small id="buyResult">选择一条快捷消息</small>';else{pop.innerHTML=`<b>${action}</b><p>${action==='升级'?'技能点已分配':action==='头像锁定'?'英雄头像锁定已切换':action+'指令已执行'}</p><button data-close-moba>继续测试</button>`}pop.querySelectorAll('[data-buy],[data-signal],[data-chat]').forEach(button=>button.onclick=()=>{$('#buyResult').textContent=(button.dataset.buy?'已购买：'+button.dataset.buy:button.dataset.signal?'已发送：'+button.dataset.signal:'已发送：'+button.dataset.chat)});pop.querySelector('[data-close-moba]')?.addEventListener('click',()=>{pop.hidden=true;control?.classList.remove('selected')})}
  function gameDown(e,p,aim){const r=stage.getBoundingClientRect(),control=e.target.closest(aim?'.fire,.stance-control':'.skill,.moba-action');if(control){control.classList.add('active');skillPointers.set(e.pointerId,control);if(aim&&control.matches('.fire')){shots++;val(3,shots);$('#ammoStatus').textContent=(40-shots%40)+' / 180'}else if(aim){val(3,control.dataset.stance)}else if(control.matches('.moba-action')){activateMobaAction(control.dataset.mobaAction,control);val(3,control.dataset.mobaAction)}else val(3,skillPointers.size)}else if(p.x<r.width*.45&&p.y>r.height*.3&&joystickId===null){joystickId=e.pointerId;const base=$('#joyBase');joystickHomeStyle=base.style.cssText;base.style.translate='none';base.style.left=(p.x-base.offsetWidth/2)+'px';base.style.top=(p.y-base.offsetHeight/2)+'px';base.style.bottom='auto';base.style.right='auto';updateJoystick(p)}else if(aim&&p.x>r.width*.45&&aimId===null){aimId=e.pointerId}val(0,active.size)}
  function gameMove(id,p,aim,old){if(id===joystickId)updateJoystick(p);if(!aim&&skillPointers.has(id)){const button=skillPointers.get(id);if(button.classList.contains('skill-one')||button.classList.contains('skill-two')||button.classList.contains('skill-three')){const r=stage.getBoundingClientRect(),b=button.getBoundingClientRect(),dx=p.x-(b.left-r.left+b.width/2),dy=p.y-(b.top-r.top+b.height/2),indicator=$('#castIndicator');indicator.style.display='block';indicator.style.transform='rotate('+Math.atan2(dy,dx)+'rad)';val(3,Math.round(Math.atan2(dy,dx)*180/Math.PI)+'°')}}if(aim&&id===aimId&&old){const c=$('#crosshair'),r=stage.getBoundingClientRect(),x=Math.max(0,Math.min(r.width,parseFloat(c.style.left||r.width*.72)+(p.x-old.x))),y=Math.max(0,Math.min(r.height,parseFloat(c.style.top||r.height*.45)+(p.y-old.y)));c.style.left=x+'px';c.style.top=y+'px';val(3,`${Math.round(x)},${Math.round(y)}`)}}
  function updateJoystick(p){const base=$('#joyBase'),knob=$('#joyKnob'),sr=stage.getBoundingClientRect(),br=base.getBoundingClientRect(),cx=br.left-sr.left+br.width/2,cy=br.top-sr.top+br.height/2,max=br.width*.34,dx=p.x-cx,dy=p.y-cy,d=Math.hypot(dx,dy)||1,k=Math.min(1,max/d),x=dx*k,y=dy*k;knob.style.transform=`translate(${x}px,${y}px)`;val(1,`${(x/max).toFixed(2)},${(y/max).toFixed(2)}`)}
  function gameUp(id){if(id===joystickId){joystickId=null;const k=$('#joyKnob'),base=$('#joyBase');if(k)k.style.transform='';if(base&&joystickHomeStyle!==null)base.style.cssText=joystickHomeStyle;joystickHomeStyle=null;val(1,'0,0')}if(id===aimId)aimId=null;const el=skillPointers.get(id);skillPointers.delete(id);if(el&&![...skillPointers.values()].includes(el))el.classList.remove('active');val(0,Math.max(0,active.size-1));if(mode==='moba'){val(3,skillPointers.size);if(!skillPointers.size&&$('#castIndicator'))$('#castIndicator').style.display='none'}}

  function buildUI(){const rows=Array.from({length:12},(_,i)=>`<div class="setting-row"><span>测试项目 ${i+1}</span><label class="switch"><input type="checkbox"><i></i></label></div>`).join('');showPanel(`<div class="settings-test"><div class="setting-card"><h3>常用设置操作</h3><div class="setting-row"><span>触控反馈</span><label class="switch"><input type="checkbox" checked><i></i></label></div><div class="setting-row"><span>模式切换</span><div class="segment"><button class="on">标准</button><button>游戏</button><button>护眼</button></div></div><div class="setting-row"><span>灵敏度</span><b id="rangeValue">50</b></div><input id="range" type="range" min="0" max="100" value="50"><div class="setting-row"><span>刷新率</span><select><option>60 Hz</option><option>90 Hz</option><option>120 Hz</option></select></div></div><div class="setting-card"><h3>列表滚动与点击</h3>${rows}</div></div>`);setStats(['切换次数','滑块值','事件/秒','滚动'],['0','50','0','正常']);let n=0;panel.querySelectorAll('.segment button').forEach(b=>b.onclick=()=>{b.parentElement.querySelectorAll('button').forEach(x=>x.classList.remove('on'));b.classList.add('on');val(0,++n)});panel.querySelectorAll('input[type=checkbox],select').forEach(x=>x.onchange=()=>val(0,++n));$('#range').oninput=e=>{val(1,e.target.value);$('#rangeValue').textContent=e.target.value}}
  function buildMenu(){
    const pages={root:['设置',['网络与连接','显示与亮度','声音与触感','辅助功能','隐私与安全','应用与存储']], '网络与连接':['网络与连接',['Wi‑Fi','蓝牙','蜂窝网络','个人热点']], '显示与亮度':['显示与亮度',['外观','文字大小','自动锁定','抬起唤醒']]};
    const state=new Map();let stack=['root'],clicks=0;
    showPanel('<div class="menu-test"><div class="menu-head"><button id="menuBack">‹ 返回</button><b id="menuTitle">设置</b><span></span></div><div id="menuList"></div></div>');
    setStats(['菜单层级','操作次数','事件/秒','当前页面'],['1','0','0','设置']);
    const render=()=>{
      const key=stack.at(-1),data=pages[key]||[key,null],list=$('#menuList');
      $('#menuTitle').textContent=data[0];$('#menuBack').style.visibility=stack.length>1?'visible':'hidden';
      list.innerHTML=data[1]?data[1].map((x,i)=>`<button class="menu-row" data-menu-key="${x}"><span><i>${['⌁','◐','♪','◎','◉','▦'][i%6]}</i>${x}</span><b>›</b></button>`).join(''):
        Array.from({length:14},(_,i)=>{const id=key+':'+i;return `<div class="menu-row"><span>选项 ${i+1}</span><label class="switch"><input type="checkbox" aria-label="选项 ${i+1}" data-option="${id}" ${state.get(id)?'checked':''}><i></i></label></div>`}).join('')+'<div class="menu-row"><label for="menuRange">灵敏度</label><input id="menuRange" type="range" min="0" max="100" value="'+(state.get(key+':range')??50)+'"></div>';
      val(0,stack.length);val(3,data[0]);$('.menu-test').scrollTop=0;
    };
    $('#menuBack').onclick=()=>{if(stack.length>1){stack.pop();val(1,++clicks);render()}};
    $('#menuList').onclick=e=>{const row=e.target.closest('button[data-menu-key]');if(row){stack.push(row.dataset.menuKey);val(1,++clicks);render()}};
    $('#menuList').onchange=e=>{if(e.target.matches('input[type=checkbox]')){state.set(e.target.dataset.option,e.target.checked);val(1,++clicks)}};
    $('#menuList').oninput=e=>{if(e.target.id==='menuRange'){state.set(stack.at(-1)+':range',e.target.value);val(1,++clicks)}};
    render();
  }
  function buildTyping(){showPanel('<div class="typing-test"><div class="setting-card"><h3>键盘与输入测试</h3><p>测试中英文切换、连续输入、删除、空格、回车和长按选词。</p><textarea id="typingBox" autocomplete="off" autocorrect="on" spellcheck="false" placeholder="点击这里开始打字…"></textarea><p class="key-info" id="keyInfo">等待输入</p></div></div>');setStats(['字符数','输入事件','事件/秒','最后输入'],['0','0','0','—']);let events=0;$('#typingBox').addEventListener('input',e=>{events++;val(0,[...e.target.value].length);val(1,events);const last=[...e.target.value].slice(-1)[0]||'删除';val(3,last);$('#keyInfo').textContent=`内容：${e.target.value||'（空）'}`})}

  function buildCross(){showPanel('<div class="cross-test"><div class="big-cross" id="bigCross"><div class="axis-dot" id="axisDot"></div></div><div class="cursor-area"><div class="cursor-dot" id="cursorDot"></div></div></div>');crossIds={axis:null,cursor:null};setStats(['触点','左轴 X/Y','事件/秒','右光标'],['0','0,0','0','50%,50%'])}
  function crossDown(id,p){const r=stage.getBoundingClientRect();if(p.x<r.width/2&&crossIds.axis===null)crossIds.axis=id;else if(p.x>=r.width/2&&crossIds.cursor===null)crossIds.cursor=id;crossMove(id,p);val(0,active.size)}
  function crossMove(id,p){const r=stage.getBoundingClientRect();if(id===crossIds.axis){const base=$('#bigCross'),dot=$('#axisDot'),sr=stage.getBoundingClientRect(),br=base.getBoundingClientRect(),cx=br.left-sr.left+br.width/2,cy=br.top-sr.top+br.height/2,max=90,dx=p.x-cx,dy=p.y-cy,d=Math.hypot(dx,dy)||1,k=Math.min(1,max/d),x=dx*k,y=dy*k;dot.style.transform=`translate(${x}px,${y}px)`;val(1,`${(x/max).toFixed(2)},${(y/max).toFixed(2)}`)}if(id===crossIds.cursor){const c=$('#cursorDot'),x=Math.max(r.width/2,Math.min(r.width,p.x)),y=Math.max(0,Math.min(r.height,p.y));c.style.left=(x-r.width/2)/(r.width/2)*100+'%';c.style.top=y/r.height*100+'%';val(3,`${Math.round((x-r.width/2)/(r.width/2)*100)}%,${Math.round(y/r.height*100)}%`)}}
  function crossUp(id){if(id===crossIds.axis){crossIds.axis=null;const d=$('#axisDot');if(d)d.style.transform='';val(1,'0,0')}if(id===crossIds.cursor)crossIds.cursor=null;val(0,Math.max(0,active.size-1))}

  function newTarget(){const r=stage.getBoundingClientRect(),m=55,t=$('#target');t.style.left=m+Math.random()*Math.max(1,r.width-m*2)+'px';t.style.top=m+Math.random()*Math.max(1,r.height-m*2)+'px';t.style.display='block'}
  function scoreTap(p){const t=$('#target'),x=parseFloat(t.style.left),y=parseFloat(t.style.top),d=Math.hypot(p.x-x,p.y-y);tapTotal++;if(d<=32)tapHits++;val(0,tapTotal);val(1,tapHits);val(3,d.toFixed(1)+'px');$('#message').textContent=`本次偏差 ${d.toFixed(1)} px · 命中 ${tapHits}/${tapTotal}`;newTarget()}
  function placeHold(){const r=stage.getBoundingClientRect(),m=$('#holdMark');m.style.left=r.width/2+'px';m.style.top=r.height/2+'px'}
  function startHold(id,p){const m=$('#holdMark'),x=parseFloat(m.style.left),y=parseFloat(m.style.top);if(hold||Math.hypot(p.x-x,p.y-y)>48)return;hold={id,x:p.x,y:p.y,start:performance.now(),max:0};$('#message').textContent='保持手指不动…';modeTimer=setInterval(()=>{if(hold)updateHold(hold.id,active.get(hold.id)||hold)},100)}
  function updateHold(id,p){if(!hold||hold.id!==id)return;hold.max=Math.max(hold.max,Math.hypot(p.x-hold.x,p.y-hold.y));const sec=(performance.now()-hold.start)/1000;val(0,sec.toFixed(1)+'s');val(1,hold.max.toFixed(1)+'px');val(3,active.size);$('#message').textContent=`持续 ${sec.toFixed(1)} 秒 · 最大漂移 ${hold.max.toFixed(1)} px`}
  function endHold(id){if(hold?.id===id){clearInterval(modeTimer);modeTimer=null;hold=null}}

  const solidColors=['#000','#fff','#f00','#0f0','#00f','#808080'];let colorIndex=0;
  function showColor(kind){showPanel(kind==='bars'?'<div class="color-bars">'+['#fff','#ff0','#0ff','#0f0','#f0f','#f00','#00f'].map(c=>`<i style="background:${c}"></i>`).join('')+'</div>':'<div id="colorPanel"></div>');setStats(['模式','亮度','事件/秒','操作'],[kind==='bars'?'色条':'纯色','—','0','轻点切换']);if(kind!=='bars'){colorIndex=0;paintColor();panel.onclick=e=>{if(e.target.closest('button'))return;colorIndex=(colorIndex+1)%solidColors.length;paintColor()}}}
  function paintColor(){const c=$('#colorPanel');c.style.background=solidColors[colorIndex];c.style.color=colorIndex===1?'#000':'#fff';c.textContent=['黑','白','红','绿','蓝','灰'][colorIndex];val(0,c.textContent)}

  function setMode(next){
    snapshotMode();
    if(modeTimer){clearInterval(modeTimer);modeTimer=null}animationToken++;mode=next;active.clear();trails.clear();maxTouches=0;nextTouchOrder=1;eventBucket=0;gesture=null;hold=null;sceneSwipe=null;joystickId=aimId=null;skillPointers.clear();clearCanvases();hidePanel();$('#target').style.display='none';$('#holdMark').style.display='none';
    stage.classList.toggle('allow-scroll',['ui','menu','type','read'].includes(mode));stage.classList.toggle('game-mode',['moba','aim','cross','video'].includes(mode));document.querySelectorAll('nav button').forEach(b=>b.classList.toggle('active',b.dataset.mode===mode));$('#modeName').textContent=copy[mode][0];$('#message').textContent=copy[mode][1];
    document.body.classList.toggle('scene-game',['moba','aim'].includes(mode));
    document.body.classList.toggle('scene-shooter',mode==='aim');
    document.body.classList.remove('layout-edit');layoutDrag=null;document.body.classList.toggle('immersive',immersivePreferred);$('#fullBtn').textContent=immersivePreferred?'工具栏':'全屏';
    if(mode==='multi')setStats(['当前触点','最大触点','采样/秒','坐标/压力'],['0','0','0','—']);
    else if(mode==='draw')setStats(['当前触点','最大触点','事件/秒','画笔'],['0','0','0','多指']);
    else if(mode==='line'){lineHit.clear();setStats(['当前触点','最大触点','事件/秒','覆盖率'],['0','0','0','0%']);drawGuides()}
    else if(mode==='ghost')buildGhost();else if(mode==='auto')buildAuto();else if(mode==='grid')buildGrid();else if(mode==='edge')buildEdge();else if(mode==='pinch'||mode==='map')buildGesture(mode);else if(mode==='read')buildRead();else if(mode==='video')buildVideo();else if(mode==='moba')buildGame(false);else if(mode==='aim')buildGame(true);else if(mode==='ui')buildUI();else if(mode==='menu')buildMenu();else if(mode==='type')buildTyping();else if(mode==='cross')buildCross();
    else if(mode==='tap'){tapHits=tapTotal=0;setStats(['点击次数','命中','事件/秒','本次偏差'],['0','0','0','—']);newTarget()}
    else if(mode==='hold'){setStats(['持续时间','最大漂移','事件/秒','触点'],['0s','0px','0','0']);$('#holdMark').style.display='block';placeHold()}
    else if(mode==='colors'||mode==='bars')showColor(mode);
    resize();
  }
  function reset(){if(mode==='pinch'&&gesture){gesture.x=gesture.y=0;gesture.scale=1;gesture.last=null;gesture.baseScale=1;if($('#photoSize'))$('#photoSize').value='100';renderGesture();return}if(mode==='read'){readPage=0;panel.dataset.turns='0';renderRead();$('#readerPage')?.scrollTo(0,0);return}setMode(mode)}
  function toggleImmersive(){const on=document.body.classList.toggle('immersive');immersivePreferred=on;$('#fullBtn').textContent=on?'工具栏':'全屏';if(on&&!isStandalone&&isIOS)$('#message').textContent='Safari 会保留工具栏：请添加到主屏幕后从桌面打开';else if(on&&document.fullscreenEnabled&&!document.fullscreenElement)document.documentElement.requestFullscreen?.().catch(()=>{});else if(!on&&document.fullscreenElement)document.exitFullscreen?.().catch(()=>{});setTimeout(syncViewport,80)}

  stage.addEventListener('pointerdown',pointerDown,{passive:false});stage.addEventListener('pointermove',pointerMove,{passive:false});stage.addEventListener('pointerup',pointerUp,{passive:false});stage.addEventListener('pointercancel',pointerUp,{passive:false});stage.addEventListener('lostpointercapture',pointerUp);
  function cancelActive(){if(layoutDrag)finishLayoutDrag({pointerId:layoutDrag.id});for(const id of [...active.keys()])pointerUp({pointerId:id,type:'pointercancel'})}
  addEventListener('blur',cancelActive);document.addEventListener('visibilitychange',()=>{if(document.hidden){cancelActive();if(mode==='ghost'&&ghostLeft>0){clearInterval(modeTimer);modeTimer=null;ghostLeft=0;$('#ghostTime').textContent='中断';val(3,'中断');$('#ghostText').textContent='离开前台，结果无效；请重置后重新测试'}}});
  stage.addEventListener('pointerdown',e=>{const p=active.get(e.pointerId);if(!p)return;if(mode==='grid')hitGrid(p);if(mode==='edge')hitEdge(p)},{passive:false});
  $('#nav').addEventListener('click',e=>{const b=e.target.closest('button[data-mode]');if(b)setMode(b.dataset.mode)});$('#clearBtn').onclick=reset;$('#fullBtn').onclick=toggleImmersive;
  $('#modeChoices').innerHTML=[...document.querySelectorAll('#nav button')].map(b=>`<button data-choice="${b.dataset.mode}">${b.textContent}</button>`).join('');
  $('#menuBtn').onclick=()=>{cancelActive();$('#modeChoices').querySelectorAll('button').forEach(b=>b.classList.toggle('active',b.dataset.choice===mode));$('#editGameLayout').hidden=$('#resetGameLayout').hidden=!['moba','aim'].includes(mode);$('#editGameLayout').textContent=document.body.classList.contains('layout-edit')?'完成控件移动':'移动游戏控件';$('#modeDialog').showModal()};
  $('#modeChoices').onclick=e=>{const b=e.target.closest('[data-choice]');if(b){$('#modeDialog').close();setMode(b.dataset.choice)}};$('#closeModes').onclick=()=>$('#modeDialog').close();
  $('#menuReset').onclick=()=>{$('#modeDialog').close();reset()};$('#menuReport').onclick=()=>{$('#modeDialog').close();openReport()};$('#menuChrome').onclick=()=>{$('#modeDialog').close();toggleImmersive()};
  $('#editGameLayout').onclick=()=>{cancelActive();document.body.classList.toggle('layout-edit');$('#modeDialog').close()};$('#resetGameLayout').onclick=()=>{delete hudLayouts[layoutKey()];try{localStorage.setItem('touch-hud-layouts',JSON.stringify(hudLayouts))}catch(_){}restoreHudLayout();$('#modeDialog').close();document.body.classList.remove('layout-edit')};
  $('#reportBtn').onclick=openReport;$('#closeReport').onclick=()=>{const dialog=$('#reportDialog');if(typeof dialog.close==='function')dialog.close();else dialog.removeAttribute('open')};$('#reportDevice').oninput=refreshReport;$('#exportJson').onclick=()=>downloadReport('json');$('#exportCsv').onclick=()=>downloadReport('csv');
  $('#safeBtn').onclick=()=>{cancelActive();$('#safeDialog').showModal()};$('#closeSafe').onclick=()=>$('#safeDialog').close();$('#topInset').oninput=applySafeInsets;$('#bottomInset').oninput=applySafeInsets;$('#resetSafe').onclick=()=>{$('#topInset').value=0;$('#bottomInset').value=0;applySafeInsets()};
  try{const saved=JSON.parse(localStorage.getItem('touch-safe-insets')||'{}');for(const side of ['top','bottom'])$(`#${side}Inset`).value=Math.max(0,Math.min(100,+saved[side]||0))}catch(_){}applySafeInsets();
  setInterval(()=>{val(2,eventBucket);eventBucket=0;if(mode==='multi'&&active.size){const p=active.values().next().value;val(3,`${Math.round(p.x)},${Math.round(p.y)} / ${(p.pressure||0).toFixed(2)}`)}},1000);
  const resyncViewport=()=>{syncViewport();setTimeout(syncViewport,80);setTimeout(syncViewport,320)};
  addEventListener('resize',syncViewport);addEventListener('pageshow',resyncViewport);addEventListener('orientationchange',resyncViewport);document.addEventListener('focusin',resyncViewport);document.addEventListener('focusout',resyncViewport);visualViewport?.addEventListener('resize',syncViewport);visualViewport?.addEventListener('scroll',syncViewport);
  // Activate touch buttons at pointer-up even when the host suppresses compatibility clicks.
  // Suppress the subsequent native click so switches and navigation never run twice.
  const controlTouches=new Map(),activatedControls=new WeakMap();
  document.addEventListener('pointerdown',e=>{const button=e.target.closest('button');if(e.pointerType==='touch'&&button&&!button.disabled)controlTouches.set(e.pointerId,{button,x:e.clientX,y:e.clientY,moved:false})},true);
  document.addEventListener('pointermove',e=>{const touch=controlTouches.get(e.pointerId);if(touch&&Math.hypot(e.clientX-touch.x,e.clientY-touch.y)>10)touch.moved=true},true);
  document.addEventListener('pointercancel',e=>{const touch=controlTouches.get(e.pointerId);if(touch)activatedControls.set(touch.button,performance.now());controlTouches.delete(e.pointerId)},true);
  document.addEventListener('pointerup',e=>{const touch=controlTouches.get(e.pointerId);controlTouches.delete(e.pointerId);if(!touch)return;activatedControls.set(touch.button,performance.now());if(touch.moved||!touch.button.isConnected||e.target.closest('button')!==touch.button)return;if(e.cancelable)e.preventDefault();touch.button.click()},true);
  document.addEventListener('click',e=>{const button=e.target.closest('button');if(e.isTrusted&&button&&performance.now()-(activatedControls.get(button)??-1000)<500){e.preventDefault();e.stopImmediatePropagation()}},true);
  const initialMode=copy[location.hash.slice(1)]?location.hash.slice(1):'multi';syncViewport();setMode(initialMode);if(isIOS&&!isStandalone)$('#message').textContent='全屏使用：共享 → 添加到主屏幕 → 从桌面图标打开';
  if('serviceWorker' in navigator&&!window.touchTestNative)navigator.serviceWorker.register('./sw.js',{updateViaCache:'none'}).then(r=>r.update()).catch(()=>{});
})();
