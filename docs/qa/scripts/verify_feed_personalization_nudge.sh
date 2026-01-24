#!/bin/bash

# Configuration des chemins automatiques
ROOT_DIR="/Users/laurinboujon/Desktop/Projects/Work Projects/Facteur"
MOBILE_DIR="$ROOT_DIR/apps/mobile"

echo "--------------------------------------------------"
echo "🚀 VERIFICATION PERSONALIZATION NUDGE (FACTEUR)"
echo "--------------------------------------------------"

echo -e "\n[1/1] Analyse Flutter ciblee (Mobile)..."
cd "$MOBILE_DIR"
flutter pub get
flutter analyze lib/features/feed/screens/feed_screen.dart \
  lib/features/feed/widgets/personalization_nudge.dart \
  lib/features/feed/widgets/personalization_sheet.dart \
  lib/features/feed/providers/skip_provider.dart
if [ $? -eq 0 ]; then
    echo "✅ Mobile: OK"
else
    echo "❌ Mobile: ECHEC"
    exit 1
fi

echo -e "\n--------------------------------------------------"
echo "✨ VERIFICATION TERMINEE AVEC SUCCES !"
echo "--------------------------------------------------"
