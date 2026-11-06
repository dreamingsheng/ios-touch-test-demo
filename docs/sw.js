const CACHE='touch-test-v14';
const ASSETS=['./','./index.html','./style.css?v=14','./app.js?v=14','./manifest.webmanifest','./icon.svg','./assets/moba-battlefield-v1.png','./assets/shooter-training-v1.png','./assets/lake-photo-v1.png','./assets/city-map.svg','./assets/flower-cc0.mp4'];
self.addEventListener('install',e=>e.waitUntil(caches.open(CACHE).then(c=>c.addAll(ASSETS)).then(()=>self.skipWaiting())));
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('touch-test-')&&k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',e=>{
  if(e.request.method!=='GET'||new URL(e.request.url).origin!==self.location.origin)return;
  e.respondWith((async()=>{
    const cache=await caches.open(CACHE);
    const range=e.request.headers.get('Range');
    if(range){
      const cached=await cache.match(e.request.url);
      if(cached){
        const bytes=await cached.arrayBuffer(),total=bytes.byteLength,match=/^bytes=(\d*)-(\d*)$/.exec(range);
        if(match){const start=match[1]?Number(match[1]):Math.max(0,total-Number(match[2])),end=match[1]?(match[2]?Math.min(Number(match[2]),total-1):total-1):total-1;
          if(start>=total||end<start)return new Response(null,{status:416,headers:{'Content-Range':'bytes */'+total}});
          return new Response(bytes.slice(start,end+1),{status:206,headers:{'Content-Type':cached.headers.get('Content-Type')||'video/mp4','Accept-Ranges':'bytes','Content-Range':`bytes ${start}-${end}/${total}`,'Content-Length':String(end-start+1)}});
        }
      }
      return fetch(e.request);
    }
    try{
      const response=await fetch(e.request,{cache:'no-cache'});
      if(response.ok){const copy=response.clone();e.waitUntil(cache.put(e.request,copy));return response}
      return await cache.match(e.request)||response;
    }catch(_){
      const cached=await cache.match(e.request);
      if(cached)return cached;
      if(e.request.mode==='navigate')return await cache.match('./index.html')||Response.error();
      return Response.error();
    }
  })());
});

