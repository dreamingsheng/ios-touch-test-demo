const CACHE='touch-test-v11';
const ASSETS=['./','./index.html','./style.css?v=11','./app.js?v=11','./manifest.webmanifest','./icon.svg'];
self.addEventListener('install',e=>e.waitUntil(caches.open(CACHE).then(c=>c.addAll(ASSETS)).then(()=>self.skipWaiting())));
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('touch-test-')&&k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',e=>{
  if(e.request.method!=='GET'||new URL(e.request.url).origin!==self.location.origin)return;
  e.respondWith((async()=>{
    const cache=await caches.open(CACHE);
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

