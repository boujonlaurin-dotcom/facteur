"""
Script de maintenance : Nettoyage et Optimisation des Sources RSS
Date: 2026-01-22
Référence: docs/maintenance/maintenance-sources-cleanup-jan26.md

Actions:
1. Désactiver DirtyBiology (is_active=false)
2. Fusionner les doublons Heu?reka (garder le flux XML)
3. Passer L'Opinion de is_curated=true à is_curated=false
4. Passer Contrepoints et L'Incorrect de is_curated=false à is_curated=true
"""

import asyncio
import os
import sys

# Add the project root to sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.database import async_session_maker
from sqlalchemy import text


async def cleanup_sources():
    async with async_session_maker() as session:
        print("=" * 60)
        print("🧹 Début du nettoyage des sources")
        print("=" * 60)

        # 1. Désactiver DirtyBiology
        print("\n📌 1. Désactivation de DirtyBiology...")
        result = await session.execute(
            text("UPDATE sources SET is_active = false WHERE name ILIKE '%DirtyBiology%'")
        )
        print(f"   → {result.rowcount} ligne(s) mise(s) à jour")

        # 2. Fusionner les doublons Heu?reka
        print("\n📌 2. Fusion des doublons Heu?reka...")
        # Garder uniquement l'entrée avec le flux XML valide
        # D'abord, identifier les deux entrées
        res = await session.execute(
            text("SELECT id, name, feed_url, is_active FROM sources WHERE name ILIKE '%Heu%reka%'")
        )
        heureka_entries = res.fetchall()
        print(f"   Entrées trouvées: {len(heureka_entries)}")
        
        xml_feed_id = None
        non_xml_feed_id = None
        for entry in heureka_entries:
            print(f"   - ID: {entry[0]}, Feed: {entry[2]}")
            if "feeds/videos.xml" in entry[2]:
                xml_feed_id = entry[0]
            else:
                non_xml_feed_id = entry[0]
        
        if xml_feed_id and non_xml_feed_id:
            # Désactiver l'entrée non-XML (on garde l'historique des contenus liés)
            result = await session.execute(
                text("UPDATE sources SET is_active = false WHERE id = :id"),
                {"id": non_xml_feed_id}
            )
            print(f"   → Entrée non-XML désactivée (ID: {non_xml_feed_id})")
        else:
            print("   ⚠️ Impossible de trouver les deux entrées distinctes")

        # 3. Passer L'Opinion en is_curated=false
        print("\n📌 3. Retrait de L'Opinion du flux curé...")
        result = await session.execute(
            text("UPDATE sources SET is_curated = false WHERE name = 'L''Opinion'")
        )
        print(f"   → {result.rowcount} ligne(s) mise(s) à jour")

        # 4. Passer Contrepoints en is_curated=true et définir le feed_url
        print("\n📌 4. Promotion de Contrepoints au flux curé...")
        # Vérifier si Contrepoints existe déjà
        res = await session.execute(
            text("SELECT id, name, feed_url FROM sources WHERE name ILIKE '%Contrepoints%'")
        )
        contrepoints = res.fetchone()
        if contrepoints:
            result = await session.execute(
                text("""
                    UPDATE sources 
                    SET is_curated = true, 
                        feed_url = 'https://www.contrepoints.org/feed',
                        is_active = true
                    WHERE name ILIKE '%Contrepoints%'
                """)
            )
            print(f"   → {result.rowcount} ligne(s) mise(s) à jour")
        else:
            print("   ⚠️ Contrepoints non trouvé en base - à importer via sync_sources")

        # 5. Passer L'Incorrect en is_curated=true et définir le feed_url
        print("\n📌 5. Promotion de L'Incorrect au flux curé...")
        res = await session.execute(
            text("SELECT id, name, feed_url FROM sources WHERE name ILIKE '%Incorrect%'")
        )
        lincorrect = res.fetchone()
        if lincorrect:
            result = await session.execute(
                text("""
                    UPDATE sources 
                    SET is_curated = true, 
                        feed_url = 'https://lincorrect.org/feed/',
                        is_active = true
                    WHERE name ILIKE '%Incorrect%'
                """)
            )
            print(f"   → {result.rowcount} ligne(s) mise(s) à jour")
        else:
            print("   ⚠️ L'Incorrect non trouvé en base - à importer via sync_sources")

        # Commit les changements
        await session.commit()
        print("\n" + "=" * 60)
        print("✅ Nettoyage terminé avec succès!")
        print("=" * 60)

        # Vérification finale
        print("\n📊 Vérification finale:")
        res = await session.execute(
            text("""
                SELECT name, is_active, is_curated, feed_url 
                FROM sources 
                WHERE name IN ('DirtyBiology', 'L''Opinion', 'Contrepoints', 'L''Incorrect')
                   OR name ILIKE '%Heu%reka%'
                ORDER BY name
            """)
        )
        for row in res:
            status = "✅" if row[1] else "❌"
            curated = "🔹CURATED" if row[2] else "⬜INDEXED"
            print(f"   {status} {row[0]}: {curated} | Feed: {row[3][:50] if row[3] else 'N/A'}...")


if __name__ == "__main__":
    asyncio.run(cleanup_sources())
