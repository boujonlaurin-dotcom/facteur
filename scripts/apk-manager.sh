#!/bin/bash

# =============================================================================
# 📦 APK Manager - Script de gestion des builds Android pour Facteur
# =============================================================================
# Usage:
#   ./scripts/apk-manager.sh push      - Commit et push, puis ouvre le workflow
#   ./scripts/apk-manager.sh build     - Lance un build GitHub Actions manuellement
#   ./scripts/apk-manager.sh download  - Télécharge la dernière APK
#   ./scripts/apk-manager.sh status    - Vérifie le statut du dernier build
#   ./scripts/apk-manager.sh open      - Ouvre la page des workflows GitHub
# =============================================================================

set -e

# Configuration
REPO="boujonlaurin-dotcom/facteur"
WORKFLOW_FILE="build-apk.yml"
ARTIFACT_NAME="facteur-app-release"
DOWNLOAD_DIR="$HOME/Desktop"

# Trouver gh
if command -v gh &> /dev/null; then
    GH_CMD="gh"
elif [[ -f "/usr/local/bin/gh" ]]; then
    GH_CMD="/usr/local/bin/gh"
elif [[ -f "$HOME/Downloads/gh_2.85.0_macOS_amd64/bin/gh" ]]; then
    GH_CMD="$HOME/Downloads/gh_2.85.0_macOS_amd64/bin/gh"
else
    GH_CMD=""
fi

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

CHECK="✅"
ROCKET="🚀"
DOWNLOAD="📥"
INFO="ℹ️"
ERROR="❌"

print_header() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}   ${ROCKET} APK Manager - Facteur                          ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

check_gh_cli() {
    if [[ -z "$GH_CMD" ]]; then
        echo -e "${RED}${ERROR} GitHub CLI (gh) n'est pas installé.${NC}"
        echo "   Télécharge-le sur: https://cli.github.com/"
        exit 1
    fi
    
    if ! $GH_CMD auth status &> /dev/null; then
        echo -e "${YELLOW}${INFO} Tu n'es pas authentifié. Lancement de l'authentification...${NC}"
        $GH_CMD auth login
    fi
}

# Push
cmd_push() {
    print_header
    echo -e "${YELLOW}${ROCKET} Préparation du push vers GitHub...${NC}"
    
    cd "$(dirname "$0")/.."
    
    if [[ -z $(git status --porcelain) ]]; then
        echo -e "${INFO} Aucun changement à commit."
        echo -e "${YELLOW}Lancer un build manuel? (y/n)${NC}"
        read -r answer
        [[ "$answer" == "y" ]] && cmd_build
        return
    fi
    
    echo ""
    echo -e "${INFO} Changements détectés:"
    git status --short
    echo ""
    
    echo -e "${YELLOW}Message de commit (ou 'q' pour annuler):${NC}"
    read -r commit_msg
    [[ "$commit_msg" == "q" ]] && return
    
    git add -A
    git commit -m "$commit_msg"
    git push origin main
    
    echo -e "${GREEN}${CHECK} Push réussi!${NC}"
    open "https://github.com/$REPO/actions/workflows/$WORKFLOW_FILE"
}

# Build manuel
cmd_build() {
    print_header
    check_gh_cli
    echo -e "${ROCKET} Lancement du build...${NC}"
    $GH_CMD workflow run "$WORKFLOW_FILE" --repo "$REPO"
    echo -e "${GREEN}${CHECK} Build lancé!${NC}"
    open "https://github.com/$REPO/actions/workflows/$WORKFLOW_FILE"
}

# Télécharger
cmd_download() {
    print_header
    check_gh_cli
    
    echo -e "${DOWNLOAD} Recherche de la dernière APK...${NC}"
    
    LAST_RUN=$($GH_CMD run list --workflow="$WORKFLOW_FILE" --repo "$REPO" --status success --limit 1 --json databaseId,displayTitle,createdAt --jq '.[0]')
    
    if [[ -z "$LAST_RUN" || "$LAST_RUN" == "null" ]]; then
        echo -e "${RED}${ERROR} Aucun build réussi trouvé.${NC}"
        exit 1
    fi
    
    RUN_ID=$(echo "$LAST_RUN" | jq -r '.databaseId')
    echo -e "${INFO} Build trouvé: ID $RUN_ID"
    
    DOWNLOAD_PATH="$DOWNLOAD_DIR/facteur-apk-tmp"
    mkdir -p "$DOWNLOAD_PATH"
    
    echo -e "${BLUE}→ Téléchargement...${NC}"
    $GH_CMD run download "$RUN_ID" --repo "$REPO" --name "$ARTIFACT_NAME" --dir "$DOWNLOAD_PATH"
    
    APK_FILE=$(find "$DOWNLOAD_PATH" -name "*.apk" | head -1)
    if [[ -f "$APK_FILE" ]]; then
        FINAL_APK="$DOWNLOAD_DIR/Facteur-$(date +%Y%m%d-%H%M%S).apk"
        mv "$APK_FILE" "$FINAL_APK"
        rm -rf "$DOWNLOAD_PATH"
        
        echo -e "${GREEN}${CHECK} APK téléchargée: $FINAL_APK${NC}"
        open -R "$FINAL_APK"
    else
        echo -e "${RED}${ERROR} APK non trouvée.${NC}"
        exit 1
    fi
}

# Status
cmd_status() {
    print_header
    check_gh_cli
    echo -e "${INFO} Derniers builds:${NC}"
    $GH_CMD run list --workflow="$WORKFLOW_FILE" --repo "$REPO" --limit 5
}

# Open
cmd_open() {
    open "https://github.com/$REPO/actions/workflows/$WORKFLOW_FILE"
}

# Auth
cmd_auth() {
    print_header
    if [[ -z "$GH_CMD" ]]; then
        echo -e "${RED}${ERROR} gh non trouvé${NC}"
        exit 1
    fi
    echo -e "${INFO} Lancement de l'authentification GitHub...${NC}"
    $GH_CMD auth login
}

# Help
cmd_help() {
    print_header
    echo "Usage: ./scripts/apk-manager.sh <commande>"
    echo ""
    echo "  push      Commit + push + ouvre le workflow"
    echo "  build     Lance un build manuellement"
    echo "  download  Télécharge la dernière APK"
    echo "  status    Affiche les derniers builds"
    echo "  open      Ouvre GitHub Actions"
    echo "  auth      Configure l'authentification GitHub"
    echo ""
}

case "${1:-help}" in
    push)     cmd_push ;;
    build)    cmd_build ;;
    download) cmd_download ;;
    status)   cmd_status ;;
    open)     cmd_open ;;
    auth)     cmd_auth ;;
    *)        cmd_help ;;
esac
