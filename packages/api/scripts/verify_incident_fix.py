import asyncio
import os
import sys
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

# Ajout du path pour les imports app
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.services.sync_service import SyncService
from app.models.source import Source

SAMPLE_RSS = """<?xml version="1.0" encoding="UTF-8" ?>
<rss version="2.0">
<channel>
 <title>Test Source</title>
 <description>Test Description</description>
 <link>http://example.com</link>
 <item>
  <title>Article Test Async</title>
  <description>Ceci est un test pour valider le fix run_in_executor</description>
  <link>http://example.com/test-async</link>
  <guid>test-async-123</guid>
  <pubDate>Mon, 22 Jan 2026 20:00:00 GMT</pubDate>
 </item>
</channel>
</rss>
"""

async def verify_fix():
    print("🔍 Démarrage de la vérification du fix Sync-Async...")
    
    # 1. Setup Mock Session
    session = AsyncMock()
    # Mock pour _save_content qui est appelé dans process_source
    # On simule que l'article est nouveau
    session.execute.return_value = MagicMock()
    
    service = SyncService(session)
    
    # 2. Mock httpx to return SAMPLE_RSS
    mock_response = MagicMock()
    mock_response.text = SAMPLE_RSS
    mock_response.raise_for_status = MagicMock()
    service.client.get = AsyncMock(return_value=mock_response)
    
    # 3. Patch _save_content to avoid DB calls
    service._save_content = AsyncMock(return_value=True)
    
    # 4. Create Mock Source
    source = Source(
        id=uuid4(),
        name="Test Source",
        feed_url="http://example.com/feed",
        type="article"
    )
    
    print(f"📡 Test de process_source pour {source.name}...")
    
    try:
        # Appel de la fonction modifiée
        new_count = await service.process_source(source)
        
        print(f"✅ Résultat : {new_count} nouveaux articles détectés.")
        
        if new_count == 1:
            print("\n✨ VERIFICATION REUSSIE ! ✨")
            print("Le code a correctement fetché, parsé (via executor) et traité l'article.")
            return True
        else:
            print(f"❌ ECHEC : Attendu 1 article, reçu {new_count}")
            return False
            
    except Exception as e:
        print(f"💥 ERREUR lors de l'exécution : {str(e)}")
        import traceback
        traceback.print_exc()
        return False
    finally:
        await service.close()

if __name__ == "__main__":
    success = asyncio.run(verify_fix())
    sys.exit(0 if success else 1)
