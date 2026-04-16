# Failed sources — synthetic probe dataset

Top French mainstream news/media domains tested against `RSSParser.detect()` on current `main`. Since the real `failed_source_attempts` table is empty (logging bug, see `docs/bugs/bug-failed-source-attempts-logging.md`), this synthetic dataset plays the same role.

**Résultat : 30/30 détectés** (100%).

## Tableau

| # | Source | Succès | Feed URL / Erreur | Stages |
|---|---|---|---|---|
| 1 | **L'Équipe** | ✅ | https://dwh.lequipe.fr/api/edito/rss?path=/ | — |
| 2 | **Le Monde** | ✅ | https://www.lemonde.fr/rss/une.xml | — |
| 3 | **Le Figaro** | ✅ | https://www.lefigaro.fr/rss/figaro_actualites.xml | — |
| 4 | **Le Parisien** | ✅ | https://feeds.leparisien.fr/leparisien/rss | — |
| 5 | **Libération** | ✅ | https://www.liberation.fr/arc/outboundfeeds/rss/?outputType=xml | — |
| 6 | **Les Echos** | ✅ | https://services.lesechos.fr/rss/les-echos-economie.xml | — |
| 7 | **La Croix** | ✅ | https://www.la-croix.com/feed | — |
| 8 | **L'Humanité** | ✅ | https://www.humanite.fr/feed | — |
| 9 | **Mediapart** | ✅ | https://www.mediapart.fr/articles/feed | — |
| 10 | **L'Obs** | ✅ | https://www.nouvelobs.com/rss.xml | — |
| 11 | **Le Point** | ✅ | https://www.lepoint.fr/rss | — |
| 12 | **L'Express** | ✅ | https://www.lexpress.fr/arc/outboundfeeds/rss/alaune.xml | — |
| 13 | **Marianne** | ✅ | https://www.marianne.net/rss.xml | — |
| 14 | **Charlie Hebdo** | ✅ | https://charliehebdo.fr/feed/ | — |
| 15 | **Courrier International** | ✅ | https://www.courrierinternational.com/feed/all/rss.xml | — |
| 16 | **France Info** | ✅ | https://www.francetvinfo.fr/titres.rss | — |
| 17 | **France Inter** | ✅ | https://www.radiofrance.fr/franceinter/rss | — |
| 18 | **France Culture** | ✅ | https://www.radiofrance.fr/franceculture/rss | — |
| 19 | **BFMTV** | ✅ | https://www.bfmtv.com/rss/news-24-7/ | — |
| 20 | **TF1 Info** | ✅ | https://www.tf1info.fr/feeds/rss-une.xml | — |
| 21 | **Ouest France** | ✅ | https://www.ouest-france.fr/rss/une | — |
| 22 | **Sud Ouest** | ✅ | https://www.sudouest.fr/rss.xml | — |
| 23 | **La Dépêche** | ✅ | https://www.ladepeche.fr/rss.xml | — |
| 24 | **20 Minutes** | ✅ | https://www.20minutes.fr/feeds/rss-une.xml | — |
| 25 | **Télérama** | ✅ | https://www.telerama.fr/rss/une.xml | — |
| 26 | **Slate** | ✅ | https://www.slate.fr/rss.xml | — |
| 27 | **Konbini** | ✅ | https://www.konbini.com/feed/ | — |
| 28 | **Numerama** | ✅ | https://www.numerama.com/feed | — |
| 29 | **Next INpact** | ✅ | https://next.ink/feed/mp3/ | — |
| 30 | **Korii** | ✅ | https://korii.slate.fr/rss.xml | — |

## Patterns d'échec

_Aucun échec._
