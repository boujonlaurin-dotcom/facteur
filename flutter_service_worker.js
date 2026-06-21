'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"flutter.js": "24bc71911b75b5f8135c949e27a2984e",
"assets/FontManifest.json": "78edb7b94f3ec0f4faa82568e50d5066",
"assets/packages/flutter_inappwebview/assets/t_rex_runner/t-rex.css": "5a8d0222407e388155d7d1395a75d5b9",
"assets/packages/flutter_inappwebview/assets/t_rex_runner/t-rex.html": "16911fcc170c8af1c5457940bd0bf055",
"assets/packages/flutter_inappwebview_web/assets/web/web_support.js": "509ae636cfdd93e49b5a6eaf0f06d79f",
"assets/packages/phosphor_flutter/lib/fonts/Phosphor-Bold.ttf": "8fedcf7067a22a2a320214168689b05c",
"assets/packages/phosphor_flutter/lib/fonts/Phosphor-Fill.ttf": "5d304fa130484129be6bf4b79a675638",
"assets/packages/phosphor_flutter/lib/fonts/Phosphor.ttf": "003d691b53ee8fab57d5db497ddc54db",
"assets/packages/phosphor_flutter/lib/fonts/Phosphor-Light.ttf": "f2dc1cd993671b155e3235044280ba47",
"assets/packages/phosphor_flutter/lib/fonts/Phosphor-Thin.ttf": "f128e0009c7b98aba23cafe9c2a5eb06",
"assets/packages/phosphor_flutter/lib/fonts/Phosphor-Duotone.ttf": "c48df336708c750389fa8d06ec830dab",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/shaders/stretch_effect.frag": "40d68efbbf360632f614c731219e95f0",
"assets/assets/notifications/facteur_goodnews.png": "8c0cf04fd9e4faef3881c0a4deeab52c",
"assets/assets/notifications/facteur_avatar.png": "77a7e9c31040c80f0cd12a613f6f4891",
"assets/assets/notifications/facteur_bike.png": "a70adbde78a116c0aa34e95e295c907f",
"assets/assets/notifications/facteur_veille.png": "63b03cc84416ecf26c905f48cfd2bae3",
"assets/assets/images/weather/rainy.svg": "1b24411e5a716b6e5b5b17ea30f5d3fc",
"assets/assets/images/weather/sunny.svg": "5269b06981edee0a2a65211f604e61e0",
"assets/assets/images/weather/cloudy.svg": "71e65107da9bdde9dafb382025669620",
"assets/assets/images/weather/snowy.svg": "9a349967e27d95cbc81607d04173669c",
"assets/assets/images/weather/partly_cloudy.svg": "bf33f21badfb6aaea87f4df9dcbb3c06",
"assets/assets/images/facteur_reparation_cropped.svg": "c78f5e8ed6a7fd9bb833886a4e2fff6d",
"assets/assets/images/recos_facteur.png": "5c05138a6fb60a2feb972c875acb4a1f",
"assets/assets/images/media_concentration_map.png": "12e8d92d71f50fbcfa9ed8417106d19f",
"assets/assets/icons/logo_facteur_app_icon_ios.png": "e434732d88d27635f72f928bc7b477a1",
"assets/assets/icons/logo_officiel.svg": "66bcd0e0152fc2f117dcfab005740adb",
"assets/assets/icons/streak_flame.svg": "bfb0798f3101fc68392ab367b596c33f",
"assets/assets/icons/logo_facteur_app_icon.png": "e41a61fdbbe16d218d61addcd3d85ba5",
"assets/assets/icons/logo_android_icon.png": "c38a4bc976c8d1b5ca44cc23989b0862",
"assets/assets/icons/facteur_logo.png": "45760e0ca20ec59ef690ec50f3a40f96",
"assets/assets/icons/logo%2520facteur%2520fond_clair.png": "45760e0ca20ec59ef690ec50f3a40f96",
"assets/assets/icons/logo_facteur_light.svg": "5ddce3d527fc65cc3df011044fe7451a",
"assets/assets/icons/google_g_logo.png": "e90397b32e43ddad3315be34004befc1",
"assets/assets/icons/logo_facteur_ui.png": "5d0b0e4f27bc8505b2da69ae6e0d10db",
"assets/assets/icons/logo%2520facteur%2520fond_sombre.png": "2a2641766a2fb15f288e3ac213eb95c1",
"assets/assets/loaders/loading_facteur.json": "2ad70ee4008c820c0462e0f56ea83c7e",
"assets/assets/changelog.json": "9ac7cafe4567e46839037ca23da9d6a0",
"assets/AssetManifest.bin.json": "39e6073547f45a608547b4dbb2f5de0a",
"assets/fonts/MaterialIcons-Regular.otf": "e28f8f3d149866db21e56b42b41acfac",
"assets/AssetManifest.bin": "61fd49f6961ffdf04bee6c3247f79b39",
"assets/NOTICES": "08b9ab6e8aaa90924e4dca45c5a5cf1d",
"icons/Icon-512.png": "62247b09de703d8bb37b5cbfec216446",
"icons/Icon-maskable-512.png": "62247b09de703d8bb37b5cbfec216446",
"icons/Icon-maskable-192.png": "2f8369d1d8d99e513e4eb6539bd0f6ff",
"icons/Icon-192.png": "2f8369d1d8d99e513e4eb6539bd0f6ff",
"flutter_bootstrap.js": "2212c1d6dd7c02fd932a6038211a55df",
"canvaskit/skwasm.wasm": "7e5f3afdd3b0747a1fd4517cea239898",
"canvaskit/skwasm.js.symbols": "3a4aadf4e8141f284bd524976b1d6bdc",
"canvaskit/chromium/canvaskit.js": "a80c765aaa8af8645c9fb1aae53f9abf",
"canvaskit/chromium/canvaskit.js.symbols": "e2d09f0e434bc118bf67dae526737d07",
"canvaskit/chromium/canvaskit.wasm": "a726e3f75a84fcdf495a15817c63a35d",
"canvaskit/canvaskit.js": "8331fe38e66b3a898c4f37648aaf7ee2",
"canvaskit/skwasm_heavy.js": "740d43a6b8240ef9e23eed8c48840da4",
"canvaskit/canvaskit.js.symbols": "a3c9f77715b642d0437d9c275caba91e",
"canvaskit/skwasm_heavy.js.symbols": "0755b4fb399918388d71b59ad390b055",
"canvaskit/canvaskit.wasm": "9b6a7830bf26959b200594729d73538e",
"canvaskit/skwasm.js": "8060d46e9a4901ca9991edd3a26be4f0",
"canvaskit/skwasm_heavy.wasm": "b0be7910760d205ea4e011458df6ee01",
"index.html": "e78df9034ce13b495d15c6228dacedeb",
"/": "e78df9034ce13b495d15c6228dacedeb",
"main.dart.js": "fa25b13e5a08b2930ce5f7c2a4b5af80",
"favicon.png": "8886e36a1435e459ddb16d004aaabcb7",
"manifest.json": "d7eddc4cd63df39a919eddaf81649c6f",
"version.json": "d355f41f0f64e3f0cb5f2aa035e41222",
"email-confirmation.html": "ac115775cbd8a949a4c666e687510e43"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"flutter_bootstrap.js",
"assets/AssetManifest.bin.json",
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
