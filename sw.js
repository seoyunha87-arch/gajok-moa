const CACHE = "gajok-moa-v5";
const APP = ["./", "./index.html", "./app.css?v=5", "./app.js?v=5", "./manifest.json", "./icon-192.png", "./icon-512.png", "./icon-180.png"];
self.addEventListener("install", event => event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(APP)).then(() => self.skipWaiting())));
self.addEventListener("activate", event => event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key !== CACHE).map(key => caches.delete(key)))).then(() => self.clients.claim())));
self.addEventListener("fetch", event => {
  if (event.request.method !== "GET" || !event.request.url.startsWith(self.location.origin)) return;
  const url = new URL(event.request.url);
  const fresh = event.request.mode === "navigate" || /\.(html|js|css|json)$/.test(url.pathname);
  event.respondWith(fetch(event.request, fresh ? { cache: "no-store" } : undefined).then(response => { const copy=response.clone(); caches.open(CACHE).then(cache=>cache.put(event.request,copy)); return response; }).catch(() => caches.match(event.request).then(hit => hit || caches.match("./index.html"))));
});
self.addEventListener("push", event => { let data={title:"가족모아",body:"가족 일정 시간이 되었어요",url:"./"}; try{data={...data,...event.data.json()}}catch{} event.waitUntil(self.registration.showNotification(data.title,{body:data.body,icon:"./icon-192.png",badge:"./icon-192.png",data:{url:data.url||"./"},tag:"gajok-moa-event",renotify:true})) });
self.addEventListener("notificationclick", event => { event.notification.close(); event.waitUntil(clients.matchAll({type:"window",includeUncontrolled:true}).then(list=>{for(const client of list){if("focus" in client){client.navigate(event.notification.data?.url||"./");return client.focus()}}return clients.openWindow(event.notification.data?.url||"./")})) });
