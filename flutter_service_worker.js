'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"icons/Icon-192.png": "59fd8ea25636b975179f03f82cc7b19e",
"icons/Icon-512.png": "92dc660f505d120ed1d92db8ec74943d",
"index.html": "10be8bb4ee9bf29fc6b384b53a5f75dc",
"/": "10be8bb4ee9bf29fc6b384b53a5f75dc",
"flutter.js": "6fef97aeca90b426343ba6c5c9dc5d4a",
"version.json": "249d9b586f1a2ac5579938a187ff8662",
"ardrive-http.js": "2af5ccae03c682160e028a0071fa669b",
"assets/shaders/ink_sparkle.frag": "f8b80e740d33eb157090be4e995febdf",
"assets/fonts/MaterialIcons-Regular.otf": "effd371e95b5a5505f35237869c0ebe5",
"assets/NOTICES": "399383a25d2428f3e9e3c85eefc5705d",
"assets/assets/fonts/Montserrat-Regular.ttf": "ee6539921d713482b8ccd4d0d23961bb",
"assets/assets/fonts/OpenSans-Regular.ttf": "3ed9575dcc488c3e3a5bd66620bdf5a4",
"assets/assets/fonts/OpenSans-Bold.ttf": "1025a6e0fb0fa86f17f57cc82a6b9756",
"assets/assets/fonts/Montserrat-Light.ttf": "409c7f79a42e56c785f50ed37535f0be",
"assets/assets/config/dev.json": "9c30c0b6d0dfa171216e914df4e239bf",
"assets/assets/config/prod.json": "e183bdcfc137d2739015a539bd8e2c26",
"assets/assets/images/brand/black_logo_0.5x.png": "db8757ce3fc25f039ad798ada3e0d44a",
"assets/assets/images/brand/ArDrive-Logo-Wordmark-Dark.png": "1a5609738e95b5ebe84e8165f1ad46c8",
"assets/assets/images/brand/4x.png": "e7f5ee5d6fc6f663fe11d61526b7eb9e",
"assets/assets/images/brand/black_logo_0.25x.png": "50e5d433822af0d58d37797f1d54c18a",
"assets/assets/images/brand/ArDrive-Logo-Wordmark-Light.png": "e3d0d3081ed93e73d60f0054b61fbf6c",
"assets/assets/images/brand/launch_icon.png": "8d40188cdbfdbe3e48686a7eaa8a78de",
"assets/assets/images/brand/white_logo_2x.png": "cc36f2423d33e0e3e1095fbd4678f9b1",
"assets/assets/images/brand/black_logo_2x.png": "ec7bc20fef5ce2210e4942c7b5079934",
"assets/assets/images/brand/ArDrive-Logo.svg": "57a6848924c3150cf33a5a49388cc039",
"assets/assets/images/brand/ArDrive.png": "5159b61030c0666289c32c24d62e32f0",
"assets/assets/images/brand/white_logo_0.25x.png": "587846e83c2c6480533b92b963d2f3d2",
"assets/assets/images/brand/0.5x.png": "b4e11ac4c7cc8ba7cfb0350bb08e073e",
"assets/assets/images/brand/3x.png": "c23722ebc4903a0599550c39d94a4ff8",
"assets/assets/images/brand/1x.png": "2a27a320c06e6ae4191e93428953c052",
"assets/assets/images/brand/2x.png": "3d1836ef9ca5635d771e04782d4fcdd1",
"assets/assets/images/brand/white_logo_4x.png": "fdeaea3326301d60d798b04f5e309c06",
"assets/assets/images/brand/ardrive_logo.png": "fbc7c81829920de13de8f36ac942e543",
"assets/assets/images/brand/white_logo_3x.png": "ac6034ca966ea63dc8b3da71d47d0c33",
"assets/assets/images/brand/black_logo_1x.png": "33c699c44eb77a33c75db9af0b0dc452",
"assets/assets/images/brand/turbo.svg": "e1ec06f62c907411e7697ed3a6c7f80d",
"assets/assets/images/brand/white_logo_0.5x.png": "fdeaea3326301d60d798b04f5e309c06",
"assets/assets/images/brand/white_logo_1x.png": "707dc7586b1e23f164cadcd54845d61f",
"assets/assets/images/profile/profile_new_user_private.png": "bb761b58972221c0bb8a330c1be86f3a",
"assets/assets/images/profile/profile_welcome.png": "8ce2b109cbe2aa3155d501be5bc47dba",
"assets/assets/images/profile/profile_add.png": "bb761b58972221c0bb8a330c1be86f3a",
"assets/assets/images/profile/profile_unlock.png": "bb761b58972221c0bb8a330c1be86f3a",
"assets/assets/images/profile/profile_new_user_payment.png": "968d2e6cb2304669cd61d8f614b960a4",
"assets/assets/images/profile/profile_new_user_upload.png": "6eb625030efb33a901a7be4531e015da",
"assets/assets/images/profile/profile_new_user_permanent.png": "19cef59765533319b5ab58d665200762",
"assets/assets/images/profile/profile_permahills_bg.svg": "b03d4d69db506598a66e3ae1b19b5252",
"assets/assets/images/profile/profile_permahills_bg.png": "b4d8f83b6bd7750a64cb305bcf1dd1a0",
"assets/assets/images/profile/profile_new_user_delete.png": "6eb625030efb33a901a7be4531e015da",
"assets/assets/images/login/grid_images.png": "48e8ea034143fa4fc9b55816db3b4c49",
"assets/assets/images/login/ardrive_plates_3.png": "1a6c389fca65e7a533eafc397af0980e",
"assets/assets/images/login/arconnect_logo.png": "e9b89da2b6cc4d6f01f477e801cb81d3",
"assets/assets/animations/lottie.json": "191a5283adba0ee925152e6bb1c36cce",
"assets/FontManifest.json": "00bd4e7e3588f3c3bcba910ef327db92",
"assets/AssetManifest.bin": "4949610a78f506bd9243bee514da4200",
"assets/AssetManifest.json": "d8de437e5e3b92c0222e68f075f032b2",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "60114762957c6a50d2e0cd7d2c5b7b98",
"assets/packages/flutter_dropzone_web/assets/flutter_dropzone.js": "ba1ea8616ef82d6917b823ecb236a4ea",
"assets/packages/ardrive_ui/assets/icons/file_zip.svg": "1ac3f156581b7c09345755fef007dbeb",
"assets/packages/ardrive_ui/assets/icons/move.svg": "02d673e27d8353e5da62e7917404d36b",
"assets/packages/ardrive_ui/assets/icons/close_icon_circle.svg": "ac859c0affafa93948d54c1abfc0638a",
"assets/packages/ardrive_ui/assets/icons/download.svg": "c60a8b9695789103d9b1c4e594d53bca",
"assets/packages/ardrive_ui/assets/icons/logout.svg": "81b69071c1510e2e3e390da57559edde",
"assets/packages/ardrive_ui/assets/icons/manifest.svg": "5dfb5bd7897da452bfee54ff47c73e24",
"assets/packages/ardrive_ui/assets/icons/file_doc.svg": "25819bd8af550f928498c801bcf44f46",
"assets/packages/ardrive_ui/assets/icons/edit.png": "b7c265032ce11b3346da424da97b9606",
"assets/packages/ardrive_ui/assets/icons/camera.svg": "09100f55bb738acaf17af0a0d1a43356",
"assets/packages/ardrive_ui/assets/icons/eye_off.svg": "71ecc79b17b1736001ab3cda9368a2ef",
"assets/packages/ardrive_ui/assets/icons/arrow_forward_filled.svg": "333c0f95238e6832b5d89d3f96d042ed",
"assets/packages/ardrive_ui/assets/icons/file_code.svg": "6e827d9474d92fcb76513bad8d036db9",
"assets/packages/ardrive_ui/assets/icons/chevron_up.svg": "6346dcb97a799d5e480d970d6346c5dc",
"assets/packages/ardrive_ui/assets/icons/external_link.svg": "945e7b855568fe9fbb3de0cc35602281",
"assets/packages/ardrive_ui/assets/icons/copy.svg": "95d9ef99aff83b80cf350b358919456b",
"assets/packages/ardrive_ui/assets/icons/arrow_right_circle.svg": "19b68a1b1b156fd80acc4ca40c71f990",
"assets/packages/ardrive_ui/assets/icons/folder_fill.svg": "4d88eea5e2992196ad253d57d8b60fbf",
"assets/packages/ardrive_ui/assets/icons/file_outlined.svg": "7c0bcc2f539dc761fb233bb06de4e0d3",
"assets/packages/ardrive_ui/assets/icons/chevron_right.svg": "18616b915c2ba937f57ada490d47b577",
"assets/packages/ardrive_ui/assets/icons/plus.svg": "ee958dfdb172245303b1f2fb058606c3",
"assets/packages/ardrive_ui/assets/icons/file_filled.svg": "4c2a8bea4019055f2a410b93264e9f60",
"assets/packages/ardrive_ui/assets/icons/checked.svg": "3b285209846614f912d04facd924994d",
"assets/packages/ardrive_ui/assets/icons/folder_add.svg": "48db97763f7e6aede7dfa77cb86bc4b7",
"assets/packages/ardrive_ui/assets/icons/indeterminate_indicator.svg": "b92e437ac01fc448baae5c88c36b1704",
"assets/packages/ardrive_ui/assets/icons/share.svg": "5b5a9782f8b5f637aa72961afbb0c835",
"assets/packages/ardrive_ui/assets/icons/close_icon.svg": "e9d2c5c1025afef8cde0e3d30c4b5a50",
"assets/packages/ardrive_ui/assets/icons/info.svg": "625eafba76134321777795fb36770e8d",
"assets/packages/ardrive_ui/assets/icons/arrow_back.svg": "22e391b657d9170572c9ef96482455ea",
"assets/packages/ardrive_ui/assets/icons/options.svg": "61f54c36273115fd109289039e439617",
"assets/packages/ardrive_ui/assets/icons/image.svg": "4e0aae9c373b41858dd6605381c10c45",
"assets/packages/ardrive_ui/assets/icons/arrow_back_filled.svg": "3edfe964738ecff6056de63b1b4c58fb",
"assets/packages/ardrive_ui/assets/icons/chevron_down.svg": "a02551465a6507c2843a4ff6a31e85a0",
"assets/packages/ardrive_ui/assets/icons/file_music.svg": "206c4cad1000436bd33fc0c6e2d5abaa",
"assets/packages/ardrive_ui/assets/icons/dots.svg": "224f529c1dfee27682e7ca90d0339c85",
"assets/packages/ardrive_ui/assets/icons/sync.svg": "a036fb7a904acff7d08d058752bc5d20",
"assets/packages/ardrive_ui/assets/icons/cloud_upload.svg": "82af098c976594cb8337c6825bb858eb",
"assets/packages/ardrive_ui/assets/icons/folder_outlined.svg": "005aa0b6311e99ee425b54a6d5911db0",
"assets/packages/ardrive_ui/assets/icons/check_success.svg": "7c011c470ec1d88b47cc3262af487a13",
"assets/packages/ardrive_ui/assets/icons/close_button.svg": "d4a385a02c2aad28c40f2a1f0cb4fe83",
"assets/packages/ardrive_ui/assets/icons/file_video.svg": "60910cad43bc26b3f83d031141e741d7",
"assets/packages/ardrive_ui/assets/icons/person.svg": "1639603244e25ed1ca693d58e9eb8d91",
"assets/packages/ardrive_ui/assets/icons/chevron_left.svg": "e8e614f3c655c87f877cf669bf89486b",
"assets/packages/ardrive_ui/assets/icons/menu_arrow.svg": "fc0c9b62b03a098016d3eb5570e26a44",
"assets/packages/ardrive_ui/assets/icons/arrow_left_circle.svg": "c784b0350fb0212c80e5479112c8680c",
"assets/packages/ardrive_ui/assets/icons/eye.svg": "a67a3121028f05dabed5cb79596ebc17",
"assets/packages/ardrive_ui/assets/icons/drive.svg": "80f8bc3a7341e26015c5bd8abecc21cd",
"assets/packages/ardrive_ui/assets/icons/edit.svg": "c6e0eb3c3f64135ab89c6d37dec476e1",
"assets/packages/ardrive_ui/assets/icons/help.svg": "6cea80c85bf14f55e9475464685df0cd",
"assets/packages/ardrive_ui/assets/icons/warning.svg": "f2c7a3388e902fd3ee27abd5f40cf40e",
"assets/packages/ardrive_ui/assets/icons/info.png": "3a8c9c268ab57c027eb777d8b22ff6d5",
"assets/packages/ardrive_ui/assets/fonts/ArDriveIcons.ttf": "e9046a684bf0ad20c10de478c886766f",
"assets/packages/ardrive_ui/assets/fonts/Wavehaus-128Bold.otf": "b3ac94013856d386c4276fbf67ab0c44",
"assets/packages/ardrive_ui/assets/fonts/Wavehaus-158ExtraBold.otf": "624a498b2fb413898232b492106940c7",
"assets/packages/ardrive_ui/assets/fonts/Wavehaus-42Light.otf": "be1b4d01a02cc61fd7c8061470971587",
"assets/packages/ardrive_ui/assets/fonts/Wavehaus-28Thin.otf": "d989c8954006a62696e255dc0e86b571",
"assets/packages/ardrive_ui/assets/fonts/Wavehaus-66Book.otf": "88e0a9b0b3ab9f869448656b27f62777",
"assets/packages/ardrive_ui/assets/fonts/Wavehaus-95SemiBold.otf": "997cded16edecc6941c0aea7ae0d1e27",
"assets/packages/wakelock_web/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/packages/alchemist/assets/fonts/Roboto/Roboto-Medium.ttf": "d08840599e05db7345652d3d417574a9",
"assets/packages/alchemist/assets/fonts/Roboto/Roboto-Black.ttf": "ec4c9962ba54eb91787aa93d361c10a8",
"assets/packages/alchemist/assets/fonts/Roboto/Roboto-Thin.ttf": "89e2666c24d37055bcb60e9d2d9f7e35",
"assets/packages/alchemist/assets/fonts/Roboto/Roboto-Light.ttf": "fc84e998bc29b297ea20321e4c90b6ed",
"assets/packages/alchemist/assets/fonts/Roboto/Roboto-Regular.ttf": "3e1af3ef546b9e6ecef9f3ba197bf7d2",
"assets/packages/alchemist/assets/fonts/Roboto/Roboto-Bold.ttf": "ee7b96fa85d8fdb8c126409326ac2d2b",
"main.dart.js": "79bfe3909c0cd932724332ef299abdf7",
"sqlite3.wasm": "fbf9815a14460df0b4ee8b746ae9b95b",
"canvaskit/skwasm.worker.js": "19659053a277272607529ef87acf9d8a",
"canvaskit/canvaskit.js": "76f7d822f42397160c5dfc69cbc9b2de",
"canvaskit/canvaskit.wasm": "f48eaf57cada79163ec6dec7929486ea",
"canvaskit/skwasm.js": "1df4d741f441fa1a4d10530ced463ef8",
"canvaskit/chromium/canvaskit.js": "8c8392ce4a4364cbb240aa09b5652e05",
"canvaskit/chromium/canvaskit.wasm": "fc18c3010856029414b70cae1afc5cd9",
"canvaskit/skwasm.wasm": "6711032e17bf49924b2b001cef0d3ea3",
"favicon.png": "167c77d2168cfdb31c240d2d3d5e9601",
"js/pst.min.js": "353b22b2121953178e78dfe6bce00b6d",
"js/sql-wasm.js": "88a2d15fe24a12bed48ade5c89689065",
"js/arconnect.js": "319aaf4ece35e24861e488a1e292c5d7",
"js/is_document_focused.js": "50c9b2315780823c9234b1115a50d564",
"manifest.json": "a610c0950a2012e01119d0e8a57e3585",
"worker.js": "f916974921b8b3d98f9fdfc4b68e5432",
"sql-wasm.wasm": "8b3b3fe7c9c611db53b9e43661bf38dd"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
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
        // Claim client to enable caching on first launch
        self.clients.claim();
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
      // Claim client to enable caching on first launch
      self.clients.claim();
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
