"""Page HTML hébergeant le YouTube IFrame Player API.

Le WebView mobile charge cette page depuis une **vraie origine https**
(api.facteur.app / Railway) au lieu d'un document `loadDataWithBaseURL`.

Pourquoi : Android WebView ne propage PAS l'Origin/Referer du `baseUrl`
aux sous-requêtes de l'iframe YouTube → YouTube refuse l'embed (Error 153).
En servant le wrapper depuis notre propre origine, l'iframe YouTube reçoit
un Referer valide et l'embed est autorisé — exactement la condition qui
marchait avec le proxy corsproxy.io, mais self-hosted (pas de rate-limit,
pas de dépendance tierce, cf. le pattern du proxy `routers/images.py`).

Le bridge JS (`window.flutter_inappwebview.callHandler`) fonctionne quelle
que soit l'origine de la page ; les gardes `if (window.flutter_inappwebview)`
permettent aussi d'ouvrir la page dans un navigateur normal sans erreur.
"""

import re

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import HTMLResponse

router = APIRouter()

# YouTube video IDs sont exactement 11 caractères [A-Za-z0-9_-]. Valider
# strictement ferme tout vecteur d'injection HTML/JS dans le template.
_VIDEO_ID_RE = re.compile(r"^[A-Za-z0-9_-]{11}$")
_CACHE_HEADERS = {"Cache-Control": "public, max-age=3600"}

_PLAYER_HTML_TEMPLATE = """<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
<style>
  html, body { margin: 0; padding: 0; background: #000; height: 100%; overflow: hidden; }
  #player { width: 100%; height: 100%; }
</style>
</head>
<body>
<div id="player"></div>
<script src="https://www.youtube.com/iframe_api"></script>
<script>
  var player;
  function onYouTubeIframeAPIReady() {
    player = new YT.Player('player', {
      videoId: '__VIDEO_ID__',
      width: '100%',
      height: '100%',
      playerVars: {
        playsinline: 1, rel: 0, modestbranding: 1,
        autoplay: 0, controls: 1, fs: 1
      },
      events: {
        onReady: function() {
          setInterval(function() {
            try {
              var d = player.getDuration();
              if (d > 0 && window.flutter_inappwebview) {
                window.flutter_inappwebview.callHandler(
                  'FlutterProgress', player.getCurrentTime() / d
                );
              }
            } catch (e) {}
          }, 1000);
        },
        onStateChange: function(e) {
          // YT.PlayerState.PLAYING === 1
          if (window.flutter_inappwebview) {
            window.flutter_inappwebview.callHandler('FlutterPlayState', e.data === 1 ? 1 : 0);
          }
        },
        onError: function(e) {
          if (window.flutter_inappwebview) {
            window.flutter_inappwebview.callHandler('FlutterError', e.data);
          }
        }
      }
    });
  }
  window.setPlaybackRate = function(rate) {
    if (player && player.setPlaybackRate) player.setPlaybackRate(rate);
  };
</script>
</body>
</html>
"""


@router.get("/player", response_class=HTMLResponse)
async def youtube_player(
    v: str = Query(..., min_length=11, max_length=11),
) -> HTMLResponse:
    """Sert la page player IFrame pour un video_id YouTube donné.

    Le WebView mobile charge cette URL (vraie origine https) pour contourner
    l'Error 153 (embed refusé) dû à l'absence de Referer sous WebView Android.
    """
    if not _VIDEO_ID_RE.match(v):
        raise HTTPException(status_code=400, detail="invalid_video_id")

    html = _PLAYER_HTML_TEMPLATE.replace("__VIDEO_ID__", v)
    return HTMLResponse(content=html, headers=_CACHE_HEADERS)
