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

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Icônes
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
    if ! command -v gh &> /dev/null; then
        echo -e "${RED}${ERROR} GitHub CLI (gh) n'est pas installé.${NC}"
        echo "   Installez-le avec: brew install gh"
        echo "   Puis authentifiez-vous: gh auth login"
        exit 1
    fi
    
    if ! gh auth status &> /dev/null; then
        echo -e "${RED}${ERROR} Vous n'êtes pas authentifié sur GitHub CLI.${NC}"
        echo "   Exécutez: gh auth login"
        exit 1
    fi
}

# =============================================================================
# COMMANDE: push - Commit, push et ouvre le workflow
# =============================================================================
cmd_push() {
    print_header
    echo -e "${YELLOW}${ROCKET} Préparation du push vers GitHub...${NC}"
    
    cd "$(dirname "$0")/.."
    
    # Vérifier s'il y a des changements
    if [[ -z $(git status --porcelain) ]]; then
        echo -e "${INFO} Aucun changement à commit."
        echo -e "${YELLOW}Voulez-vous quand même lancer un build manuel? (y/n)${NC}"
        read -r answer
        if [[ "$answer" == "y" ]]; then
            cmd_build
        fi
        return
    fi
    
    # Afficher les changements
    echo ""
    echo -e "${INFO} Changements détectés:"
    git status --short
    echo ""
    
    # Demander le message de commit
    echo -e "${YELLOW}Message de commit (ou 'q' pour annuler):${NC}"
    read -r commit_msg
    
    if [[ "$commit_msg" == "q" ]]; then
        echo -e "${INFO} Push annulé."
        return
    fi
    
    # Commit et push
    echo ""
    echo -e "${BLUE}→ git add -A${NC}"
    git add -A
    
    echo -e "${BLUE}→ git commit -m \"$commit_msg\"${NC}"
    git commit -m "$commit_msg"
    
    echo -e "${BLUE}→ git push origin main${NC}"
    git push origin main
    
    echo ""
    echo -e "${GREEN}${CHECK} Push réussi! Le build GitHub Actions démarre automatiquement.${NC}"
    echo ""
    
    # Ouvrir la page des workflows
    echo -e "${INFO} Ouverture de la page des workflows..."
    open "https://github.com/$REPO/actions/workflows/$WORKFLOW_FILE"
}

# =============================================================================
# COMMANDE: build - Lancer un build manuel
# =============================================================================
cmd_build() {
    print_header
    check_gh_cli
    
    echo -e "${ROCKET} Lancement d'un build GitHub Actions...${NC}"
    echo ""
    
    # Lancer le workflow
    gh workflow run "$WORKFLOW_FILE" --repo "$REPO"
    
    echo -e "${GREEN}${CHECK} Build lancé avec succès!${NC}"
    echo ""
    echo -e "${INFO} Suivez le build sur: https://github.com/$REPO/actions/workflows/$WORKFLOW_FILE"
    
    # Ouvrir la page
    open "https://github.com/$REPO/actions/workflows/$WORKFLOW_FILE"
}

# =============================================================================
# COMMANDE: download - Télécharger la dernière APK
# =============================================================================
cmd_download() {
    print_header
    check_gh_cli
    
    echo -e "${DOWNLOAD} Recherche de la dernière APK...${NC}"
    echo ""
    
    # Obtenir le dernier run réussi
    LAST_RUN=$(gh run list --workflow="$WORKFLOW_FILE" --repo "$REPO" --status success --limit 1 --json databaseId,displayTitle,createdAt --jq '.[0]')
    
    if [[ -z "$LAST_RUN" || "$LAST_RUN" == "null" ]]; then
        echo -e "${RED}${ERROR} Aucun build réussi trouvé.${NC}"
        exit 1
    fi
    
    RUN_ID=$(echo "$LAST_RUN" | jq -r '.databaseId')
    RUN_TITLE=$(echo "$LAST_RUN" | jq -r '.displayTitle')
    RUN_DATE=$(echo "$LAST_RUN" | jq -r '.createdAt')
    
    echo -e "${INFO} Dernier build trouvé:"
    echo "   Titre: $RUN_TITLE"
    echo "   Date:  $RUN_DATE"
    echo "   ID:    $RUN_ID"
    echo ""
    
    # Télécharger l'artifact
    DOWNLOAD_PATH="$DOWNLOAD_DIR/facteur-apk-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$DOWNLOAD_PATH"
    
    echo -e "${BLUE}→ Téléchargement vers $DOWNLOAD_PATH...${NC}"
    gh run download "$RUN_ID" --repo "$REPO" --name "$ARTIFACT_NAME" --dir "$DOWNLOAD_PATH"
    
    # Renommer l'APK avec la date
    APK_FILE=$(find "$DOWNLOAD_PATH" -name "*.apk" | head -1)
    if [[ -f "$APK_FILE" ]]; then
        FINAL_APK="$DOWNLOAD_DIR/Facteur-$(date +%Y%m%d-%H%M%S).apk"
        mv "$APK_FILE" "$FINAL_APK"
        rm -rf "$DOWNLOAD_PATH"
        
        echo ""
        echo -e "${GREEN}${CHECK} APK téléchargée avec succès!${NC}"
        echo ""
        echo -e "   📍 Emplacement: ${YELLOW}$FINAL_APK${NC}"
        echo ""
        
        # Ouvrir le dossier
        open -R "$FINAL_APK"
    else
        echo -e "${RED}${ERROR} APK non trouvée dans l'artifact.${NC}"
        exit 1
    fi
}

# =============================================================================
# COMMANDE: status - Vérifier le statut du dernier build
# =============================================================================
cmd_status() {
    print_header
    check_gh_cli
    
    echo -e "${INFO} Statut des derniers builds:${NC}"
    echo ""
    
    gh run list --workflow="$WORKFLOW_FILE" --repo "$REPO" --limit 5
    
    echo ""
    echo -e "${INFO} Pour plus de détails: ${YELLOW}./scripts/apk-manager.sh open${NC}"
}

# =============================================================================
# COMMANDE: open - Ouvrir la page GitHub Actions
# =============================================================================
cmd_open() {
    echo -e "${INFO} Ouverture de la page GitHub Actions..."
    open "https://github.com/$REPO/actions/workflows/$WORKFLOW_FILE"
}

# =============================================================================
# COMMANDE: help - Afficher l'aide
# =============================================================================
cmd_help() {
    print_header
    echo "Usage: ./scripts/apk-manager.sh <commande>"
    echo ""
    echo "Commandes disponibles:"
    echo ""
    echo -e "  ${GREEN}push${NC}      Commit et push les changements, puis ouvre le workflow"
    echo -e "  ${GREEN}build${NC}     Lance un build GitHub Actions manuellement"
    echo -e "  ${GREEN}download${NC}  Télécharge la dernière APK sur le Bureau"
    echo -e "  ${GREEN}status${NC}    Affiche le statut des derniers builds"
    echo -e "  ${GREEN}open${NC}      Ouvre la page des workflows GitHub"
    echo -e "  ${GREEN}help${NC}      Affiche cette aide"
    echo ""
    echo "Exemples:"
    echo "  ./scripts/apk-manager.sh push"
    echo "  ./scripts/apk-manager.sh download"
    echo ""
}

# =============================================================================
# Main
# =============================================================================
case "${1:-help}" in
    push)     cmd_push ;;
    build)    cmd_build ;;
    download) cmd_download ;;
    status)   cmd_status ;;
    open)     cmd_open ;;
    help|*)   cmd_help ;;
esac
