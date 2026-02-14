#!/bin/bash
# Check Worktree Isolation
# Vérifie que l'agent travaille dans un worktree isolé (pas le repo principal)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🔍 Worktree Isolation Check...${NC}"

# Récupère le chemin absolu du repo actuel
CURRENT_REPO=$(git rev-parse --show-toplevel)

# Vérifie si on est dans un worktree (pas le repo principal)
IS_WORKTREE=$(git rev-parse --is-inside-work-tree 2>/dev/null || echo "false")
GIT_DIR=$(git rev-parse --git-dir)

if [[ "$GIT_DIR" == ".git" ]]; then
  # On est dans le repo principal
  echo -e "${RED}❌ ERREUR: Travail dans le repo principal détecté${NC}"
  echo -e "${RED}   Chemin actuel: $CURRENT_REPO${NC}"
  echo -e "${RED}   Git dir: $GIT_DIR${NC}"
  echo ""
  echo -e "${YELLOW}📋 Workflow Worktree Isolation (OBLIGATOIRE):${NC}"
  echo ""
  echo -e "  cd /Users/laurinboujon/Desktop/Projects/Work\\ Projects/Facteur"
  echo -e "  git checkout main && git pull origin main"
  echo -e "  git checkout -b <agent>-<tache>"
  echo -e "  git worktree add ../<agent>-<tache> <agent>-<tache>"
  echo -e "  cd ../<agent>-<tache>"
  echo ""
  echo -e "${YELLOW}Exemples de noms de branche:${NC}"
  echo -e "  - feature/digest-share-button"
  echo -e "  - fix/auth-token-refresh"
  echo -e "  - maintenance/migrate-sqlalchemy"
  echo ""
  exit 1
fi

# Si on arrive ici, on est dans un worktree
echo -e "${GREEN}✅ Worktree Isolation: OK${NC}"
echo -e "${GREEN}   Worktree: $CURRENT_REPO${NC}"
echo -e "${GREEN}   Git dir: $GIT_DIR${NC}"

# Liste tous les worktrees pour info
echo ""
echo -e "${YELLOW}📂 Worktrees actifs:${NC}"
git worktree list

exit 0
