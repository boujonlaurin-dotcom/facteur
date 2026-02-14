#!/bin/bash
# Pre-Code-Change Hook
# Vérifie qu'une Story ou Bug Doc existe AVANT toute modification de code

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🔍 Pre-Code-Change Hook: Vérification Story/Bug Doc...${NC}"

# Récupère le nom de la branche actuelle
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)

# Si branche main, bloquer
if [ "$BRANCH_NAME" = "main" ]; then
  echo -e "${RED}❌ ERREUR: Modification de code sur branche 'main' interdite${NC}"
  echo -e "${RED}   Crée une branche feature/bug dédiée avec worktree isolation${NC}"
  exit 1
fi

# Parse le nom de branche pour extraire le type (feature/fix/maintenance)
if [[ $BRANCH_NAME =~ ^(feature|fix|maintenance)/(.+)$ ]]; then
  TYPE="${BASH_REMATCH[1]}"
  TASK_NAME="${BASH_REMATCH[2]}"
else
  echo -e "${YELLOW}⚠️  WARNING: Format de branche non-standard: $BRANCH_NAME${NC}"
  echo -e "${YELLOW}   Format attendu: feature/*, fix/*, maintenance/*${NC}"
  echo -e "${YELLOW}   Vérification Story/Bug Doc skip.${NC}"
  exit 0
fi

# Vérifie existence de Story/Bug Doc selon type
if [ "$TYPE" = "feature" ]; then
  # Cherche story correspondante dans docs/stories/
  STORY_COUNT=$(find "$PROJECT_ROOT/docs/stories" -name "*.md" -type f | wc -l | tr -d ' ')

  if [ "$STORY_COUNT" -eq 0 ]; then
    echo -e "${RED}❌ ERREUR: Aucune User Story trouvée dans docs/stories/${NC}"
    echo -e "${RED}   Type: Feature → Une story DOIT exister${NC}"
    echo -e "${RED}   Crée docs/stories/core/{epic}.{story}.{nom}.md AVANT modification code${NC}"
    exit 1
  fi

  echo -e "${GREEN}✅ User Story détectée ($STORY_COUNT fichier(s))${NC}"

elif [ "$TYPE" = "fix" ]; then
  # Cherche bug doc correspondant dans docs/bugs/
  BUG_COUNT=$(find "$PROJECT_ROOT/docs/bugs" -maxdepth 1 -name "*.md" -type f | wc -l | tr -d ' ')

  if [ "$BUG_COUNT" -eq 0 ]; then
    echo -e "${RED}❌ ERREUR: Aucune Bug Doc trouvée dans docs/bugs/${NC}"
    echo -e "${RED}   Type: Fix → Une bug doc DOIT exister${NC}"
    echo -e "${RED}   Crée docs/bugs/bug-{nom}.md AVANT modification code${NC}"
    exit 1
  fi

  echo -e "${GREEN}✅ Bug Doc détectée ($BUG_COUNT fichier(s))${NC}"

elif [ "$TYPE" = "maintenance" ]; then
  # Cherche maintenance doc dans docs/maintenance/
  MAINT_COUNT=$(find "$PROJECT_ROOT/docs/maintenance" -name "*.md" -type f | wc -l | tr -d ' ')

  if [ "$MAINT_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠️  WARNING: Aucune Maintenance Doc trouvée${NC}"
    echo -e "${YELLOW}   Considère créer docs/maintenance/maintenance-{nom}.md${NC}"
    # Warning seulement, pas blocant pour maintenance
  else
    echo -e "${GREEN}✅ Maintenance Doc détectée ($MAINT_COUNT fichier(s))${NC}"
  fi
fi

echo -e "${GREEN}✅ Pre-Code-Change Hook: PASSED${NC}"
exit 0
