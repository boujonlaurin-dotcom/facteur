#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="$ROOT_DIR/apps/mobile"
ASSET_DIR="$APP_DIR/assets/icons"
ICON_XML="$APP_DIR/android/app/src/main/res/mipmap-anydpi-v26/launcher_icon.xml"

cd "$ROOT_DIR"

test -f "$ASSET_DIR/facteur_logo.png"
test -f "$ASSET_DIR/logo facteur fond_clair.png"
test -f "$ASSET_DIR/logo facteur fond_sombre.png"
test -f "$ASSET_DIR/logo_facteur_app_icon.png"

if ! grep -q "@mipmap/launcher_icon" "$ICON_XML"; then
  echo "launcher_icon.xml n'utilise pas @mipmap/launcher_icon"
  exit 1
fi

echo "Assets OK. Lancer l'app Android et verifier :"
echo "- Logo visible sur l'ecran de splash"
echo "- Icone nette et centree dans le menu Android"
