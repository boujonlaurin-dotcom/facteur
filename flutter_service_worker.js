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
"assets/assets/notifications/facteur_goodnews.png": "2dc14b172691f4a932b7be5e4e176d4f",
"assets/assets/notifications/facteur_avatar.png": "ba8bfd5fb863fca5905758b87137e1ae",
"assets/assets/notifications/facteur_bike.png": "aeee823f094172a5afe1c367e0a94687",
"assets/assets/notifications/facteur_veille.png": "8f3c79d4f1d34dadb493bad1b8912700",
"assets/assets/images/weather/rainy.svg": "b82549b49bc38aeb783fdda8be31b12a",
"assets/assets/images/weather/sunny.svg": "436d967e535106d515e7b870c68e4cc4",
"assets/assets/images/weather/cloudy.svg": "918ccffb5c007934df179d0135ef8bc2",
"assets/assets/images/weather/snowy.svg": "6cb4c005fff5d55f78fd263bc2dfe28a",
"assets/assets/images/weather/partly_cloudy.svg": "e4de7a6971b723244e57e5ae5debee6f",
"assets/assets/images/facteur_reparation_cropped.svg": "c78f5e8ed6a7fd9bb833886a4e2fff6d",
"assets/assets/images/recos_facteur.png": "5c05138a6fb60a2feb972c875acb4a1f",
"assets/assets/images/media_concentration_map.png": "c4555d787c4e1e867f7635844526e530",
"assets/assets/icons/logo_facteur_app_icon_ios.png": "dfee43c1d2e86cad2f31e8bc08e215e1",
"assets/assets/icons/logo_officiel.svg": "66bcd0e0152fc2f117dcfab005740adb",
"assets/assets/icons/streak_flame.svg": "bfb0798f3101fc68392ab367b596c33f",
"assets/assets/icons/logo_facteur_app_icon.png": "e41a61fdbbe16d218d61addcd3d85ba5",
"assets/assets/icons/logo_android_icon.png": "7d75adcda1adfab18d04a2b61226c2d6",
"assets/assets/icons/facteur_logo.png": "924a3fbce0a09d3f7959c96f7ec2d316",
"assets/assets/icons/google_g_logo.png": "e90397b32e43ddad3315be34004befc1",
"assets/assets/icons/logo_facteur_ui.png": "5d0b0e4f27bc8505b2da69ae6e0d10db",
"assets/assets/loaders/loading_facteur.json": "2ad70ee4008c820c0462e0f56ea83c7e",
"assets/assets/changelog.json": "25a0b0581e7932f23952feea7cbc8752",
"assets/AssetManifest.bin.json": "fc7313a17123d9a5faa6924610fc631e",
"assets/fonts/MaterialIcons-Regular.otf": "e28f8f3d149866db21e56b42b41acfac",
"assets/AssetManifest.bin": "6c0b935c0a7b1150dce512cafe0930d8",
"assets/NOTICES": "08b9ab6e8aaa90924e4dca45c5a5cf1d",
"icons/Icon-512.png": "d94321ef49ccb865e1c8efd333a31049",
"icons/Icon-maskable-512.png": "d94321ef49ccb865e1c8efd333a31049",
"icons/Icon-maskable-192.png": "4707a087c6c2650cebb4297382e64d97",
"icons/Icon-192.png": "4707a087c6c2650cebb4297382e64d97",
"flutter_bootstrap.js": "aaddb63f230eb0e4daf1d042a1cebe6e",
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
"main.dart.js": "044a839ddbf988bae233f49647bd00c0",
"favicon.png": "159fa956f52abe713fdffa560cf340be",
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
