'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';
const RESOURCES = {
  "flutter.js": "f85e6fb278b0fd20c349186fb46ae36d",
"canvaskit/canvaskit.js": "2bc454a691c631b07a9307ac4ca47797",
"canvaskit/canvaskit.wasm": "bf50631470eb967688cca13ee181af62",
"canvaskit/profiling/canvaskit.js": "38164e5a72bdad0faa4ce740c9b8e564",
"canvaskit/profiling/canvaskit.wasm": "95a45378b69e77af5ed2bc72b2209b94",
"assets/assets/fonts/OpenSans-Regular.ttf": "3ed9575dcc488c3e3a5bd66620bdf5a4",
"assets/assets/fonts/OpenSans-Bold.ttf": "1025a6e0fb0fa86f17f57cc82a6b9756",
"assets/assets/fonts/Montserrat-Light.ttf": "409c7f79a42e56c785f50ed37535f0be",
"assets/assets/fonts/Montserrat-Regular.ttf": "ee6539921d713482b8ccd4d0d23961bb",
"assets/assets/config/prod.json": "67ed5b9ccdd3ec9d130c302bdaa75ab1",
"assets/assets/config/dev.json": "541474355936f073fa412f1a512c3fb9",
"assets/assets/images/profile/profile_new_user_upload.png": "6eb625030efb33a901a7be4531e015da",
"assets/assets/images/profile/profile_welcome.png": "8ce2b109cbe2aa3155d501be5bc47dba",
"assets/assets/images/profile/profile_new_user_delete.png": "6eb625030efb33a901a7be4531e015da",
"assets/assets/images/profile/profile_new_user_payment.png": "968d2e6cb2304669cd61d8f614b960a4",
"assets/assets/images/profile/profile_permahills_bg.svg": "b03d4d69db506598a66e3ae1b19b5252",
"assets/assets/images/profile/profile_add.png": "bb761b58972221c0bb8a330c1be86f3a",
"assets/assets/images/profile/profile_permahills_bg.png": "b4d8f83b6bd7750a64cb305bcf1dd1a0",
"assets/assets/images/profile/profile_new_user_private.png": "bb761b58972221c0bb8a330c1be86f3a",
"assets/assets/images/profile/profile_unlock.png": "bb761b58972221c0bb8a330c1be86f3a",
"assets/assets/images/profile/profile_new_user_permanent.png": "19cef59765533319b5ab58d665200762",
"assets/assets/images/brand/launch_icon.png": "8d40188cdbfdbe3e48686a7eaa8a78de",
"assets/assets/images/brand/ArDrive-Logo-Wordmark-Dark.png": "1a5609738e95b5ebe84e8165f1ad46c8",
"assets/assets/images/brand/ArDrive-Logo-Wordmark-Light.png": "b11193d644585ac01361cfdce7b6b9cb",
"assets/shaders/ink_sparkle.frag": "83c076d55fdbf5e6f73f29c79926992c",
"assets/fonts/MaterialIcons-Regular.otf": "95db9098c58fd6db106f1116bae85a0b",
"assets/NOTICES": "c9faa4ec545310c4eecd73be5bf4f356",
"assets/packages/flutter_dropzone_web/assets/flutter_dropzone.js": "ba1ea8616ef82d6917b823ecb236a4ea",
"assets/FontManifest.json": "7b2a36307916a9721811788013e65289",
"assets/AssetManifest.json": "1e023e690127db290a10a5cd35b0e47e",
"index.html": "c38e410d05cba85f4c894718fc98e7e2",
"/": "c38e410d05cba85f4c894718fc98e7e2",
"worker.js": "f916974921b8b3d98f9fdfc4b68e5432",
"sqlite3.wasm": "fbf9815a14460df0b4ee8b746ae9b95b",
"ardrive-http.js": "6a3b75804a6e1b4a76e09cc3df70c32c",
"favicon.png": "167c77d2168cfdb31c240d2d3d5e9601",
"version.json": "879b65d33c235a4b7df8499ccae1a728",
"icons/Icon-192.png": "59fd8ea25636b975179f03f82cc7b19e",
"icons/Icon-512.png": "92dc660f505d120ed1d92db8ec74943d",
"sql-wasm.wasm": "8b3b3fe7c9c611db53b9e43661bf38dd",
"js/is_document_focused.js": "50c9b2315780823c9234b1115a50d564",
"js/pst.min.js": "353b22b2121953178e78dfe6bce00b6d",
"js/arconnect.js": "fcf3565603d187e5050b091f013c4d45",
"js/sql-wasm.js": "88a2d15fe24a12bed48ade5c89689065",
"main.dart.js": "fd48ede4936ca974ccf25b0b94f7ab4e",
"manifest.json": "a610c0950a2012e01119d0e8a57e3585"
};

// The application shell files that are downloaded before a service worker can
// start.
const CORE = [
  "main.dart.js",
"index.html",
"assets/AssetManifest.json",
"assets/FontManifest.json"];
// During install, the TEMP cache is populated with the application shell files.
self.addEventListener("install", (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});

// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files.
self.addEventListener("activate", function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      // When there is no prior manifest, clear the entire cache.
      if (!manifest) {
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
        for (var request of await tempCache.keys()) {
          var response = await tempCache.match(request);
          await contentCache.put(request, response);
        }
        await caches.delete(TEMP);
        // Save the manifest to make future upgrades efficient.
        await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
        return;
      }
      var oldManifest = await manifest.json();
      var origin = self.location.origin;
      for (var request of await contentCache.keys()) {
        var key = request.url.substring(origin.length + 1);
        if (key == "") {
          key = "/";
        }
        // If a resource from the old manifest is not in the new cache, or if
        // the MD5 sum has changed, delete it. Otherwise the resource is left
        // in the cache and can be reused by the new service worker.
        if (!RESOURCES[key] || RESOURCES[key] != oldManifest[key]) {
          await contentCache.delete(request);
        }
      }
      // Populate the cache with the app shell TEMP files, potentially overwriting
      // cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
      return;
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
  }());
});

// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var origin = self.location.origin;
  var key = event.request.url.substring(origin.length + 1);
  // Redirect URLs to the index.html
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  if (event.request.url == origin || event.request.url.startsWith(origin + '/#') || key == '') {
    key = '/';
  }
  // If the URL is not the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  event.respondWith(caches.open(CACHE_NAME)
    .then((cache) =>  {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      })
    })
  );
});

self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});

// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = request.url.substring(origin.length + 1);
    if (key == "") {
      key = "/";
    }
    currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}

// Attempt to download the resource online before falling back to
// the offline cache.
function onlineFirst(event) {
  return event.respondWith(
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}
