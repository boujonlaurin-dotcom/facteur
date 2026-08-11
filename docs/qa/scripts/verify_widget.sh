#!/usr/bin/env bash
#
# verify_widget.sh — checklist device du widget d'accueil Facteur (Android).
#
# Le widget est la seule surface du produit dont le rendu ne dépend d'aucune
# ligne de Dart exécutée : il vit dans le process du launcher, alimenté par des
# SharedPreferences. Aucun test unitaire ne peut prouver qu'il s'affiche. Ce
# script automatise tout ce qui est automatisable via `adb` et laisse à
# l'opérateur les seuls gestes qui ne le sont pas (le glisser-déposer du widget
# depuis le sélecteur du launcher).
#
# Prérequis : un device/émulateur branché (`adb devices`), l'APK beta installé.
#
#   cd apps/mobile && flutter build apk --debug --flavor beta
#   adb install -r build/app/outputs/flutter-apk/app-beta-debug.apk
#   bash docs/qa/scripts/verify_widget.sh
#
# Cf. docs/bugs/bug-widget-flaner-android.md pour ce que chaque étape prouve.

set -uo pipefail

APP_ID="${APP_ID:-com.example.facteur.staging}"
NAMESPACE="com.example.facteur"
PASS=0
FAIL=0

c_ok()   { printf '\033[32m  ✔\033[0m %s\n' "$1"; PASS=$((PASS + 1)); }
c_ko()   { printf '\033[31m  ✘\033[0m %s\n' "$1"; FAIL=$((FAIL + 1)); }
c_info() { printf '\033[90m  · %s\033[0m\n' "$1"; }
c_head() { printf '\n\033[1m%s\033[0m\n' "$1"; }
c_todo() { printf '\033[33m  ☐\033[0m %s\n' "$1"; }

require_device() {
  if ! command -v adb >/dev/null 2>&1; then
    echo "adb introuvable — installe les platform-tools Android." >&2
    exit 2
  fi
  if [ -z "$(adb devices | sed -n '2p')" ]; then
    echo "Aucun device connecté (adb devices)." >&2
    exit 2
  fi
}

# ─────────────────────────────────────────────────────────────
c_head "0. Environnement"
require_device
c_info "device : $(adb devices | sed -n '2p' | cut -f1)"
c_info "applicationId testé : $APP_ID"
if adb shell pm list packages | grep -q "^package:$APP_ID$"; then
  c_ok "APK installé"
else
  c_ko "APK $APP_ID absent — installe-le d'abord"
  exit 2
fi

# ─────────────────────────────────────────────────────────────
c_head "1. Les providers sont enregistrés auprès de l'AppWidgetService"
# C1 historique : les receivers vivent dans le NAMESPACE, pas dans
# l'applicationId. S'ils n'apparaissent pas ici, le pont Flutter → widget est
# cassé et rien ne se rafraîchira jamais.
WIDGET_DUMP="$(adb shell dumpsys appwidget 2>/dev/null)"
for provider in FacteurWidgetLight FacteurWidgetDark; do
  if printf '%s' "$WIDGET_DUMP" | grep -q "$NAMESPACE.$provider"; then
    c_ok "$provider enregistré"
  else
    c_ko "$provider ABSENT de dumpsys appwidget"
  fi
done

PINNED="$(printf '%s' "$WIDGET_DUMP" | grep -c "$NAMESPACE.FacteurWidget" || true)"
if [ "$PINNED" -gt 0 ]; then
  c_info "instances trouvées : $PINNED"
else
  c_todo "Aucun widget épinglé — pose-en un depuis le sélecteur du launcher"
fi

# ─────────────────────────────────────────────────────────────
c_head "2. Le manifest mergé est sain"
MANIFEST_DUMP="$(adb shell pm dump "$APP_ID" 2>/dev/null)"
if printf '%s' "$MANIFEST_DUMP" | grep -qi "TrampolineActivity"; then
  c_ko "Trampoline Glance présente — régression du crash FLUTTER-1D"
else
  c_ok "Aucune trampoline Glance (FLUTTER-1D reste impossible)"
fi
if printf '%s' "$MANIFEST_DUMP" | grep -q "FacteurWidgetService"; then
  c_ok "FacteurWidgetService déclaré"
else
  c_ko "FacteurWidgetService absent — la liste restera vide"
fi

# ─────────────────────────────────────────────────────────────
c_head "3. Contenu du payload (profondeur + fraîcheur)"
# `widget_last_push_count` et `articles_updated_at` sont écrits par Flutter à
# chaque push. Les lire prouve que la donnée arrive, indépendamment du rendu.
PREFS_PATH="/data/data/$APP_ID/shared_prefs/HomeWidgetPreferences.xml"
PREFS="$(adb shell "run-as $APP_ID cat $PREFS_PATH" 2>/dev/null)"
if [ -z "$PREFS" ]; then
  c_todo "SharedPreferences illisibles (build release ?) — ouvre l'app une fois"
else
  COUNT="$(printf '%s' "$PREFS" | sed -n 's/.*widget_last_push_count[^>]*>\([0-9]*\)<.*/\1/p' | head -1)"
  UPDATED="$(printf '%s' "$PREFS" | sed -n 's/.*articles_updated_at[^>]*>\([0-9]*\)<.*/\1/p' | head -1)"
  if [ -n "$COUNT" ] && [ "$COUNT" -gt 9 ]; then
    c_ok "profondeur du payload : $COUNT lignes"
  else
    c_ko "profondeur du payload : ${COUNT:-inconnue} (attendu ≫ 9)"
  fi
  if [ -n "$UPDATED" ] && [ "$UPDATED" -gt 0 ]; then
    AGE_MIN=$(( ( $(date +%s) - UPDATED / 1000 ) / 60 ))
    if [ "$AGE_MIN" -lt 120 ]; then
      c_ok "dernier push : il y a ${AGE_MIN} min"
    else
      c_ko "dernier push : il y a ${AGE_MIN} min — le widget affiche du périmé"
    fi
  else
    c_ko "articles_updated_at absent — le masthead n'affichera aucune heure"
  fi
  # Le bloc Essentiel fossile est la cause racine du « 14 jours de retard ».
  if printf '%s' "$PREFS" | grep -q '"source_kind":"essentiel"'; then
    c_ko "payload contenant encore des lignes Essentiel — purge non appliquée"
  else
    c_ok "aucune ligne Essentiel dans le payload"
  fi
fi

# ─────────────────────────────────────────────────────────────
c_head "4. Refresh en place (le bouton 🔄 ne doit PAS ouvrir l'app)"
BEFORE_ACT="$(adb shell dumpsys activity activities | grep -m1 'topResumedActivity' || true)"
adb shell am broadcast \
  -a com.example.facteur.action.WIDGET_REFRESH \
  -n "$APP_ID/$NAMESPACE.FacteurWidgetLight" >/dev/null 2>&1
sleep 8
AFTER_ACT="$(adb shell dumpsys activity activities | grep -m1 'topResumedActivity' || true)"
if [ "$BEFORE_ACT" = "$AFTER_ACT" ]; then
  c_ok "le refresh n'a pas mis MainActivity au premier plan"
else
  c_ko "le refresh a changé l'activité au premier plan (régression D4)"
  c_info "avant : $BEFORE_ACT"
  c_info "après : $AFTER_ACT"
fi

# ─────────────────────────────────────────────────────────────
c_head "5. Tap sur une ligne → article dans Flâner"
# On simule le fillInIntent que la row émet. Remplace <ID> par un id réel lu
# dans le payload si tu veux vérifier l'ouverture effective du lecteur.
ROW_ID="$(printf '%s' "$PREFS" | sed -n 's/.*\[{&quot;id&quot;:&quot;\([^&]*\)&quot;.*/\1/p' | head -1)"
if [ -n "$ROW_ID" ]; then
  adb shell am start -a android.intent.action.VIEW \
    -d "io.supabase.facteur://feed/content/$ROW_ID" "$APP_ID" >/dev/null 2>&1
  sleep 4
  c_ok "deep link ligne délivré (io.supabase.facteur://feed/content/$ROW_ID)"
  c_todo "Vérifie à l'écran : l'article est ouvert, DANS Flâner"
  c_todo "Appuie sur Retour → tu dois atterrir sur Flâner, pas sur un écran vide"
else
  c_todo "Aucun id lisible dans le payload — teste le tap à la main"
fi

# ─────────────────────────────────────────────────────────────
c_head "6. Rafraîchissement de fond (WorkManager, ~1 h)"
c_info "Job list :"
adb shell dumpsys jobscheduler | grep -A 2 "$APP_ID" | head -20 || true
c_todo "Forcer : adb shell cmd jobscheduler run -f $APP_ID <jobId>"

# ─────────────────────────────────────────────────────────────
c_head "7. Contrôles visuels (non automatisables)"
c_todo "Masthead : logo Facteur + « Facteur » en Fraunces Bold + « Maj HHhMM »"
c_todo "Les 10 premières lignes = les 10 premières de l'onglet Flâner, même ordre"
c_todo "Aucun « à l'instant » sur un article de la veille"
c_todo "Aucune ligne sans titre ni ligne vide entre les articles"

# ─────────────────────────────────────────────────────────────
c_head "Résultat"
printf '  %s réussis · %s échecs\n' "$PASS" "$FAIL"
c_info "Les ☐ demandent un œil humain : coche-les avant d'approuver la PR."
[ "$FAIL" -eq 0 ] || exit 1
