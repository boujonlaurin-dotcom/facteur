#!/bin/bash
# Script d'importation et vérification des sources Facteur

echo "🔍 Vérification de la configuration..."
cd "$(dirname "$0")"
source venv/bin/activate

echo "🚀 Lancement de l'importation des (~114) sources..."
./venv/bin/python scripts/import_sources.py --file ../sources/sources_candidates.csv

echo "📊 Vérification du compte total en base de données..."
./venv/bin/python count_sources.py > count_final.log 2>&1
cat count_final.log

echo "✅ Opération terminée."
