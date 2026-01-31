#!/bin/bash
# Script d'installation du modèle spaCy French
# US-4: NER Service

set -e

echo "================================"
echo "Installation du modèle spaCy FR"
echo "================================"

# Check if we're in the right directory
if [ ! -f "requirements-ml.txt" ]; then
    echo "❌ Erreur: Vous devez exécuter ce script depuis packages/api/"
    exit 1
fi

# Install spaCy if not already installed
echo "📦 Vérification de spaCy..."
pip show spacy > /dev/null 2>&1 || {
    echo "📥 Installation de spaCy..."
    pip install spacy==3.8.11
}

# Download French model
echo "🌍 Téléchargement du modèle fr_core_news_md..."
python -m spacy download fr_core_news_md

# Verify installation
echo "✅ Vérification de l'installation..."
python -c "
import spacy
nlp = spacy.load('fr_core_news_md')
print('✅ Modèle fr_core_news_md chargé avec succès!')
print(f'   Version spaCy: {spacy.__version__}')

# Test quick extraction
doc = nlp('Emmanuel Macron visite Paris.')
entities = [(ent.text, ent.label_) for ent in doc.ents]
print(f'   Test extraction: {entities}')
"

echo ""
echo "================================"
echo "✅ Installation terminée!"
echo "================================"
