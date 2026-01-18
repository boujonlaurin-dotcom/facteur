#!/bin/bash
# Script de redémarrage manuel du backend Facteur sur le port 8080

echo "🛑 Arrêt des processus existants..."
pkill -9 -f "uvicorn" || true
pkill -9 -f "python" || true

echo "🚀 Démarrage du backend sur le port 8080..."
cd "$(dirname "$0")"
source venv/bin/activate
nohup uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload > backend_8080.log 2>&1 &

echo "✅ Commande lancée en arrière-plan."
echo "🔍 Vérifiez le statut avec : tail -f backend_8080.log"
echo "🌐 Health check : http://localhost:8080/api/health"
