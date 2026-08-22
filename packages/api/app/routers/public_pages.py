"""Pages HTML publiques servies par l'API (carte de partage d'un article).

`facteur.app/a/<id>` est proxifié par le nginx de la landing vers
`GET /api/pages/a/{content_id}` (cf. `apps/landing/nginx.conf.template`). La page
DOIT vivre sous `facteur.app` pour que l'universal link iOS / app link Android
puisse la capter : un domaine tiers ne serait pas couvert par le
`.well-known/apple-app-site-association`.

Pas d'iframe de l'éditeur (X-Frame-Options, paywalls, RGPD) : on rend une carte
riche — titre, extrait, vignette, source — avec un lien sortant vers l'article
original et un CTA vers l'app.

Pattern repris de `routers/youtube_player.py` : template Python en dur, aucune
dépendance de templating, réponse `HTMLResponse` sans authentification.
"""

import html
import re
from urllib.parse import quote, urlparse
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from fastapi.responses import HTMLResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import get_db
from app.models.content import Content
from app.models.source import Source
from app.services.content_quality import strip_html

router = APIRouter()

APP_STORE_ID = "6778094299"
PLAY_PACKAGE = "facteur.app"

# Feuille de style de la landing, réutilisée pour rester cohérent avec le reste
# de facteur.app (le header emprunte `container` / `section-nav__item`).
#
# ⚠️ Couplage inter-trains : cette page est déployée par le service API (branche
# `production`) alors que la CSS l'est par la landing (branche `main`). Le `?v=`
# est la clé de cache-bust partagée par toutes les pages de la landing — quand
# elle est bumpée là-bas, **cette constante doit suivre**, sinon la carte de
# partage reste épinglée sur une version périmée de la CSS. D'où la constante
# unique plutôt que deux littéraux dans les templates.
_LANDING_CSS_TAG = '<link rel="stylesheet" href="/css/style.css?v=6">'

# Convention UTM Notion : utm_source=app&utm_medium=partage_in_app&utm_content=<surface>
UTM_SURFACE_ARTICLE = "article"

# Un `ref` est un code d'attribution court émis par l'app (PR2). Tout ce qui
# sort de cet alphabet est ignoré silencieusement plutôt que rejeté : un lien
# partagé avec un `ref` tronqué doit rester une page qui s'affiche.
_REF_RE = re.compile(r"^[A-Za-z0-9_-]{1,32}$")

_TOKEN_RE = re.compile(r"__[A-Z_]+__")

_DESCRIPTION_MAX_CHARS = 200

_CACHE_OK = {"Cache-Control": "public, max-age=600"}
# 1 min sur le 404 : un contenu peut apparaître juste après (ingestion en cours),
# et ça borne l'amplification si un lien mort circule.
_CACHE_MISS = {"Cache-Control": "public, max-age=60"}


def _clean_ref(ref: str | None) -> str:
    """Normalise le code d'attribution ; chaîne vide si absent ou malformé."""
    if ref and _REF_RE.match(ref):
        return ref
    return ""


def _utm_query(surface: str, ref: str) -> str:
    """Suffixe UTM commun (convention Notion), avec le `ref` s'il existe."""
    parts = [
        "utm_source=app",
        "utm_medium=partage_in_app",
        f"utm_content={surface}",
    ]
    if ref:
        parts.append(f"ref={ref}")
    return "&".join(parts)


def _store_links(surface: str, ref: str) -> tuple[str, str]:
    """(App Store, Play Store) décorés pour l'attribution d'installation.

    Play : le paramètre `referrer` est remonté tel quel par l'Install Referrer
    API, donc on y met la query UTM complète (encodée une fois).
    App Store : Apple n'accepte que `pt`/`ct`/`mt` ; `ct` (campaign token) est
    la seule chaîne libre. Le `pt` (provider token) reste à collecter dans App
    Store Connect, le lien fonctionne sans.
    """
    campaign = f"partage_{surface}"
    if ref:
        campaign = f"{campaign}_{ref}"
    ios = f"https://apps.apple.com/us/app/facteur-ton-algo-ton-info/id{APP_STORE_ID}?ct={quote(campaign)}&mt=8"
    android = (
        f"https://play.google.com/store/apps/details?id={PLAY_PACKAGE}&hl=fr"
        f"&referrer={quote(_utm_query(surface, ref))}"
    )
    return ios, android


def _plain_excerpt(raw: str | None) -> str:
    """Texte brut tronqué depuis une description RSS potentiellement HTML.

    Ordre volontaire : `unescape` -> strip des balises -> collapse -> troncature
    -> (l'échappement de sortie est fait par l'appelant). Unescaper d'abord évite
    qu'un `&lt;script&gt;` survive au strip et ressorte en balise réelle.
    """
    if not raw:
        return ""
    text = strip_html(html.unescape(raw))
    if len(text) <= _DESCRIPTION_MAX_CHARS:
        return text
    # Coupe au dernier espace pour ne pas trancher un mot. `text` est déjà
    # strippé et non vide ici, donc le `rsplit` rend au pire la tranche entière.
    return f"{text[:_DESCRIPTION_MAX_CHARS].rsplit(' ', 1)[0]}…"


def _safe_link_url(raw: str | None, fallback: str) -> str:
    """URL sortante sûre pour un `href`, repli sur `fallback` (la home) sinon.

    `html.escape()` ne protège **pas** d'un `href="javascript:…"` : l'échappement
    ne touche pas au schéma. Les URLs viennent de flux RSS tiers, donc on impose
    http(s) avant de les rendre cliquables.
    """
    if raw:
        candidate = raw.strip()
        try:
            parsed = urlparse(candidate)
        except ValueError:
            return fallback
        if parsed.scheme in ("http", "https") and parsed.netloc:
            return candidate
    return fallback


def _safe_image_url(raw: str | None) -> str:
    """Vignette utilisable comme `og:image`, chaîne vide si inexploitable.

    Les crawlers sociaux exigent une URL **absolue en https** ; ils ne suivent ni
    les URLs relatives ni le http (carte muette, voire mixed-content). Filtrer
    sur le schéma ferme du même geste `javascript:` et `data:`.

    Pas de repli via `/api/images/proxy` : ce proxy rejette lui-même le http
    (`images.py` exige `scheme == "https"`), le repli rendrait donc un 404. Sans
    image on bascule `twitter:card` en `summary`, qui s'affiche proprement.
    """
    if not raw:
        return ""
    candidate = raw.strip()
    try:
        parsed = urlparse(candidate)
    except ValueError:
        return ""
    if parsed.scheme != "https" or not parsed.netloc:
        return ""
    return candidate


_PAGE_TEMPLATE = """<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>__TITLE__ · Facteur</title>
<meta name="description" content="__EXCERPT__">
<!-- Aucun contenu original ici (titre + extrait + lien sortant) : indexer cette
     page produirait du duplicate content. Les crawlers sociaux ignorent robots
     et lisent l'Open Graph normalement. -->
<meta name="robots" content="noindex, follow">
<link rel="canonical" href="__ORIGINAL_URL__">
<link rel="icon" type="image/png" href="/favicon.png">

<meta property="og:site_name" content="Facteur">
<meta property="og:type" content="article">
<meta property="og:title" content="__TITLE__">
<meta property="og:description" content="__EXCERPT__">
<meta property="og:url" content="__PAGE_URL__">
__OG_IMAGE__
<meta name="twitter:card" content="__TWITTER_CARD__">
<meta name="twitter:title" content="__TITLE__">
<meta name="twitter:description" content="__EXCERPT__">

__LANDING_CSS__
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet">
<style>
  .share-card { max-width: 560px; margin: 0 auto; padding: 1.5rem 1.25rem 3rem; }
  .share-card__source { font-size: 0.85rem; font-weight: 600; letter-spacing: 0.04em;
    text-transform: uppercase; color: #d4652a; margin: 0 0 0.75rem; }
  .share-card__title { font-size: 1.6rem; line-height: 1.25; font-weight: 800;
    margin: 0 0 0.9rem; color: #1a1a1a; }
  .share-card__excerpt { font-size: 1.02rem; line-height: 1.55; color: #6b6560; margin: 0 0 1.5rem; }
  .share-card__thumb { width: 100%; border-radius: 14px; margin: 0 0 1.5rem; display: block; }
  .share-card__cta { display: block; text-align: center; background: #1a1a1a; color: #fff;
    font-weight: 700; font-size: 1rem; padding: 0.95rem 1.5rem; border-radius: 12px;
    text-decoration: none; border: none; width: 100%; cursor: pointer; font-family: inherit; }
  .share-card__cta:hover { background: #333; }
  .share-card__original { display: block; text-align: center; margin-top: 1rem;
    font-size: 0.95rem; color: #6b6560; }
  .share-card__stores { display: none; flex-direction: column; gap: 0.6rem;
    margin-top: 1.75rem; padding-top: 1.5rem; border-top: 1px solid #e0dbd5; text-align: center; }
  .share-card__stores p { margin: 0 0 0.25rem; font-size: 0.92rem; color: #6b6560; }
  .share-card__stores a { font-size: 0.95rem; color: #0a58ca; }
</style>
</head>
<body>
<header class="section hero legal-page__hero" style="min-height:auto; padding:1.5rem 0 0;">
  <div class="container"><a href="/" class="section-nav__item" style="font-size:0.9rem;">Facteur</a></div>
</header>

<main>
  <article class="share-card">
    <p class="share-card__source">__SOURCE_NAME__</p>
    <h1 class="share-card__title">__TITLE__</h1>
    __THUMB__
    <p class="share-card__excerpt">__EXCERPT__</p>

    <button class="share-card__cta" id="open-btn" type="button">Lire dans Facteur</button>
    <a class="share-card__original" href="__ORIGINAL_URL__" target="_blank" rel="noopener noreferrer">
      Voir l'article original
    </a>

    <div class="share-card__stores" id="stores">
      <p>Facteur n'est pas installé ?</p>
      <a href="__IOS_STORE__" id="ios-link" data-store="ios">Télécharger sur l'App Store</a>
      <a href="__ANDROID_STORE__" id="android-link" data-store="android">Télécharger sur Google Play</a>
    </div>
  </article>
</main>

<script>
(function () {
  var DEEP_LINK = 'io.supabase.facteur://feed/content/__CONTENT_ID__';
  var REF = '__REF__';
  var SURFACE = '__SURFACE__';
  var IOS = /iPad|iPhone|iPod/.test(navigator.userAgent);
  var ANDROID = /android/i.test(navigator.userAgent);
  var stores = document.getElementById('stores');

  function revealStores() {
    stores.style.display = 'flex';
    if (IOS) { document.getElementById('android-link').style.display = 'none'; }
    else if (ANDROID) { document.getElementById('ios-link').style.display = 'none'; }
  }

  // Scheme custom volontaire (pas l'universal link) : une fois la page chargée,
  // iOS court-circuite l'universal link pour un tap intra-domaine. L'universal
  // link, lui, joue en amont et cette page n'est alors jamais affichée.
  document.getElementById('open-btn').addEventListener('click', function () {
    window.location.href = DEEP_LINK;
    setTimeout(revealStores, 1500);
  });

  Array.prototype.forEach.call(stores.querySelectorAll('a[data-store]'), function (a) {
    a.addEventListener('click', function () {
      if (window.gtag) {
        window.gtag('event', 'store_click', {
          store: a.getAttribute('data-store'), surface: SURFACE, ref: REF
        });
      }
    });
  });

  if (!IOS && !ANDROID) { revealStores(); }
})();
</script>
<script src="/js/consent.js?v=1"></script>
</body>
</html>
"""

_NOT_FOUND_TEMPLATE = """<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Contenu introuvable · Facteur</title>
<meta name="robots" content="noindex, nofollow">
<link rel="icon" type="image/png" href="/favicon.png">
__LANDING_CSS__
<style>
  .share-404 { max-width: 480px; margin: 0 auto; padding: 4rem 1.25rem; text-align: center; }
  .share-404 h1 { font-size: 1.5rem; font-weight: 800; margin: 0 0 0.75rem; color: #1a1a1a; }
  .share-404 p { color: #6b6560; margin: 0 0 2rem; }
  .share-404 a { color: #0a58ca; }
</style>
</head>
<body>
<main class="share-404">
  <h1>Ce contenu n'est plus disponible</h1>
  <p>Le lien a peut-être expiré, ou l'article a été retiré.</p>
  <a href="/">Découvrir Facteur</a>
</main>
<script src="/js/consent.js?v=1"></script>
</body>
</html>
"""

# Figé à l'import : la feuille de style ne dépend d'aucune donnée de requête.
# La substitution par requête (`_TOKEN_RE.sub`, passe unique) reste réservée
# aux valeurs utilisateur.
_PAGE_TEMPLATE = _PAGE_TEMPLATE.replace("__LANDING_CSS__", _LANDING_CSS_TAG)
_NOT_FOUND_TEMPLATE = _NOT_FOUND_TEMPLATE.replace("__LANDING_CSS__", _LANDING_CSS_TAG)


def _not_found() -> HTMLResponse:
    return HTMLResponse(
        content=_NOT_FOUND_TEMPLATE, status_code=404, headers=_CACHE_MISS
    )


@router.get("/a/{content_id}", response_class=HTMLResponse)
async def article_share_page(
    content_id: str,
    ref: str | None = Query(default=None, max_length=64),
    db: AsyncSession = Depends(get_db),
) -> HTMLResponse:
    """Carte de partage publique d'un article (aucune authentification).

    `content_id` est typé `str` et non `UUID` à dessein : un id malformé doit
    rendre la page 404 HTML (ce que voit un humain qui suit un lien tronqué),
    pas le 422 JSON que FastAPI produirait sur un path param typé.
    """
    try:
        parsed_id = UUID(content_id)
    except ValueError:
        return _not_found()

    # Colonnes explicites plutôt que l'entité `Content` : la table porte un
    # `html_content` (corps complet de l'article) dont la page n'a aucun besoin,
    # et qui transiterait sur chaque miss de cache.
    row = (
        await db.execute(
            select(
                Content.title,
                Content.description,
                Content.thumbnail_url,
                Content.url,
                Source.name,
            )
            .join(Source, Source.id == Content.source_id)
            .where(Content.id == parsed_id)
        )
    ).first()
    if row is None:
        return _not_found()

    raw_title, raw_description, raw_thumbnail, raw_url, source_name = row
    origin = get_settings().public_web_base_url
    clean_ref = _clean_ref(ref)
    ios_store, android_store = _store_links(UTM_SURFACE_ARTICLE, clean_ref)

    title = html.escape(raw_title or "Article")
    excerpt = html.escape(_plain_excerpt(raw_description))
    escaped_image = html.escape(_safe_image_url(raw_thumbnail))

    page_url = f"{origin}/a/{parsed_id}"
    if clean_ref:
        page_url = f"{page_url}?ref={clean_ref}"

    replacements = {
        "__TITLE__": title,
        "__EXCERPT__": excerpt,
        "__SOURCE_NAME__": html.escape(source_name or "Facteur"),
        "__ORIGINAL_URL__": html.escape(_safe_link_url(raw_url, origin)),
        "__PAGE_URL__": html.escape(page_url),
        "__OG_IMAGE__": (
            f'<meta property="og:image" content="{escaped_image}">'
            if escaped_image
            else ""
        ),
        "__TWITTER_CARD__": ("summary_large_image" if escaped_image else "summary"),
        "__THUMB__": (
            f'<img class="share-card__thumb" src="{escaped_image}" alt="" loading="lazy">'
            if escaped_image
            else ""
        ),
        "__IOS_STORE__": html.escape(ios_store),
        "__ANDROID_STORE__": html.escape(android_store),
        # `parsed_id` (et non `content_id`) : la re-sérialisation de l'UUID
        # garantit `[0-9a-f-]` seulement dans le littéral JS.
        "__CONTENT_ID__": str(parsed_id),
        "__REF__": clean_ref,
        "__SURFACE__": UTM_SURFACE_ARTICLE,
    }

    # Passe unique : un `.replace()` token par token re-scannerait le texte déjà
    # injecté, si bien qu'un titre contenant littéralement « __ORIGINAL_URL__ »
    # se ferait substituer à son tour.
    page = _TOKEN_RE.sub(
        lambda m: replacements.get(m.group(0), m.group(0)), _PAGE_TEMPLATE
    )

    return HTMLResponse(content=page, headers=_CACHE_OK)
