# PR — Widget Android : fix `Class not allowed to be inflated android.view.View`

## Why

Le widget Android Facteur était cassé sur Samsung One UI depuis 4 itérations
(PR #478, #501, #505, #525). Symptôme : "Impossible d'ajouter le widget" +
écran noir. Aucune itération n'avait jamais lu le logcat.

Logcat capté sur Samsung S24 le 2026-05-01 :

```
W AppWidgetHostView: android.widget.RemoteViews$ActionException:
  android.view.InflateException: Binary XML file line #123 in
  com.example.facteur:layout/widget_article_row:
  Class not allowed to be inflated android.view.View
```

`RemoteViews` impose une whitelist stricte des classes inflatables (API ≥ 31,
l'app cible API 36). `android.view.View` brut n'est PAS autorisé. Allowlist :
`AdapterViewFlipper, FrameLayout, GridLayout, GridView, LinearLayout, ListView,
RelativeLayout, StackView, ViewFlipper, AnalogClock, Button, Chronometer,
ImageButton, ImageView, ProgressBar, RadioGroup, RadioButton, TextClock,
TextView, ViewStub, Space`.

`widget_article_row.xml` contenait deux `<View>` :
- L. 120 : spacer flex (`layout_weight="1"`) — entre `row_source_name` et `row_time`.
- L. 133 : séparateur 1dp avec background.

→ L'inflate échouait dès la première row, l'host launcher avortait le bind.

## What

2 lignes XML modifiées dans `widget_article_row.xml` :

- `<View layout_weight="1"/>` (spacer) → `<Space layout_weight="1"/>`
- `<View ... background="@color/facteur_border"/>` (séparateur) → `<TextView ...>`
  (TextView est whitelisté et accepte un `android:background`).

Aucun changement Kotlin. Aucun changement architectural.

## Investigation report

Détails complets : `.context/widget-android-investigation.md`
(setup, logcat filtré, dumpsys, conclusion).

## Test plan

- [ ] Build APK release sur la branche, install sur Samsung One UI réel
- [ ] Long-press écran d'accueil → Widgets → Facteur → drag
- [ ] Le widget s'affiche avec les 5 articles (header, rows, footer CTA)
- [ ] Aucune erreur "Impossible d'ajouter le widget"
- [ ] Tap sur une row ouvre le deep link `io.supabase.facteur://digest/<id>`
- [ ] Tap sur le footer CTA ouvre l'app
- [ ] (Optionnel) tester aussi sur émulateur Pixel pour valider la généralité

## Out of scope

- Pas de changement de stratégie de rendu (rester sur `addView` inline,
  validé par les logs : `onUpdate id=25 json.len=2581` + bind système OK).
- Pas de retour à `RemoteViewsService`/`Factory` (cassé sur Samsung).
- Pas de changement de taille du widget (`minHeight=340dp` OK, le launcher
  l'accepte — c'était bien le rendu qui cassait, pas le sizing).
