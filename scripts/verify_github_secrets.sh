#!/bin/bash
# Script de vérification des secrets GitHub pour Facteur
# Usage: ./scripts/verify_github_secrets.sh

echo "=========================================="
echo "Vérification des secrets GitHub - Facteur"
echo "=========================================="
echo ""

# Vérifier si gh CLI est installé
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) n'est pas installé."
    echo "   Installez-le avec: brew install gh"
    echo "   Puis connectez-vous avec: gh auth login"
    exit 1
fi

# Vérifier si l'utilisateur est connecté
if ! gh auth status &> /dev/null; then
    echo "❌ Vous n'êtes pas connecté à GitHub CLI."
    echo "   Connectez-vous avec: gh auth login"
    exit 1
fi

REPO="boujonlaurin-dotcom/facteur"

echo "🔍 Vérification des secrets dans le repository: $REPO"
echo ""

# Liste des secrets requis
SECRETS=(
    "SUPABASE_URL"
    "SUPABASE_ANON_KEY"
    "REVENUECAT_IOS_KEY"
    "GITHUB_TOKEN"
)

echo "📋 Secrets requis:"
for secret in "${SECRETS[@]}"; do
    echo "   - $secret"
done
echo ""

# Récupérer la liste des secrets
SECRET_LIST=$(gh secret list -R "$REPO" 2>&1)

if [ $? -ne 0 ]; then
    echo "❌ Impossible de récupérer la liste des secrets."
    echo "   Erreur: $SECRET_LIST"
    echo ""
    echo "💡 Assurez-vous d'avoir les permissions suffisantes sur le repository."
    exit 1
fi

echo "✅ Liste des secrets récupérée avec succès"
echo ""

# Vérifier chaque secret
MISSING=0
for secret in "${SECRETS[@]}"; do
    if echo "$SECRET_LIST" | grep -q "^$secret"; then
        echo "✅ $secret est configuré"
    else
        echo "❌ $secret est MANQUANT"
        MISSING=$((MISSING + 1))
    fi
done

echo ""
echo "=========================================="

if [ $MISSING -eq 0 ]; then
    echo "✅ Tous les secrets sont configurés!"
    echo ""
    echo "📝 Prochaines étapes:"
    echo "   1. Redéployer l'application via GitHub Actions"
    echo "   2. Tester la connexion sur le navigateur"
    echo "   3. Tester sur l'application Android"
else
    echo "❌ $MISSING secret(s) manquant(s)"
    echo ""
    echo "📝 Pour ajouter les secrets manquants:"
    echo "   1. Allez sur: https://github.com/$REPO/settings/secrets/actions"
    echo "   2. Cliquez sur 'New repository secret'"
    echo "   3. Ajoutez chaque secret manquant:"
    echo ""
    echo "   SUPABASE_URL:"
    echo "      Valeur: https://ykuadtelnzavrqzbfdve.supabase.co"
    echo ""
    echo "   SUPABASE_ANON_KEY:"
    echo "      Valeur: (clé publique depuis Supabase Dashboard)"
    echo ""
    echo "   REVENUECAT_IOS_KEY:"
    echo "      Valeur: (clé API depuis RevenueCat)"
fi

echo "=========================================="
