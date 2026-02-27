"""Service for clustering content into stories based on topic keywords - Hybrid approach."""

import datetime
import re
from collections import defaultdict
from uuid import UUID, uuid4

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.content import Content

# French stopwords and filler words - AGGRESSIVE filtering
STOPWORDS = {
    # Articles & pronouns
    "le",
    "la",
    "les",
    "un",
    "une",
    "des",
    "de",
    "du",
    "d",
    "l",
    "et",
    "en",
    "à",
    "au",
    "aux",
    "ce",
    "cette",
    "ces",
    "mon",
    "ma",
    "mes",
    "ton",
    "ta",
    "tes",
    "son",
    "sa",
    "ses",
    "notre",
    "nos",
    "votre",
    "vos",
    "leur",
    "leurs",
    "qui",
    "que",
    "quoi",
    "dont",
    "où",
    "se",
    "ne",
    "pas",
    "plus",
    "moins",
    "très",
    "bien",
    "mal",
    "tout",
    "tous",
    "toute",
    "toutes",
    "il",
    "elle",
    "on",
    "nous",
    "vous",
    "ils",
    "elles",
    "je",
    "tu",
    "me",
    "te",
    "lui",
    # Prepositions
    "y",
    "avec",
    "pour",
    "par",
    "sur",
    "sous",
    "dans",
    "entre",
    "vers",
    "chez",
    "sans",
    # Verbs
    "est",
    "sont",
    "être",
    "avoir",
    "fait",
    "faire",
    "a",
    "ont",
    "peut",
    "été",
    "sera",
    "peuvent",
    "pourraient",
    "devrait",
    "faut",
    "veut",
    "vont",
    "doit",
    "veux",
    "vouloir",
    # Conjunctions & adverbs
    "mais",
    "ou",
    "donc",
    "ni",
    "car",
    "si",
    "alors",
    "quand",
    "comme",
    "après",
    "avant",
    "encore",
    "aussi",
    "même",
    "autre",
    "autres",
    "peu",
    "beaucoup",
    "trop",
    "assez",
    "vraiment",
    "toujours",
    "jamais",
    "souvent",
    "parfois",
    # Question words
    "pourquoi",
    "comment",
    "combien",
    # Generic/common words that don't indicate topic
    "monde",
    "année",
    "années",
    "nouveau",
    "nouvelle",
    "nouveaux",
    "nouvelles",
    "grand",
    "grande",
    "grands",
    "grandes",
    "petit",
    "petite",
    "petits",
    "petites",
    "premier",
    "première",
    "dernier",
    "dernière",
    "deux",
    "trois",
    "quatre",
    "cinq",
    "face",
    "contre",
    "selon",
    "côté",
    "fois",
    "temps",
    "jour",
    "jours",
    "grâce",
    "travers",
    "lors",
    "depuis",
    "jusque",
    "durant",
    "pendant",
    "suite",
    "fallait",
    "faudrait",
    "doivent",
    "devraient",
    "pourrait",
    "sait",
    "savent",
    "veulent",
    # News filler
    "informations",
    "info",
    "infos",
    "article",
    "articles",
    "savoir",
    "retenir",
    "breaking",
    "urgent",
    "exclusif",
    "exclusive",
    "dernières",
    "heure",
    "heures",
    "minute",
    "minutes",
    "live",
    "direct",
    "video",
    "vidéo",
    "photo",
    "photos",
    "images",
    "podcast",
    "interview",
    "analyse",
    "décryptage",
    "explications",
    "enquête",
    "dossier",
    "révèle",
    "montre",
    "indique",
    "suggère",
    "affirme",
    "estime",
    "pense",
    "croit",
    # Very common non-topical words
    "président",
    "gouvernement",
    "ministre",
    "pays",
    "nation",
    "société",
    "économie",
    "politique",
    "histoire",
    "science",
    "culture",
    "international",
    "national",
    "local",
    "victimes",
    "personnes",
    "gens",
    "hommes",
    "femmes",
    "enfants",
    "jeunes",
    "vieux",
    "villes",
    "ville",
    "région",
    "zone",
    "secteur",
    "domaine",
    "partie",
    "ensemble",
    "système",
    "question",
    "problème",
    "solution",
    "idée",
    "projet",
    "plan",
    "mesure",
    "effet",
    "impact",
    "conséquence",
    "résultat",
    "cause",
    "raison",
    "objectif",
    "but",
    "manière",
    "façon",
    "forme",
    "type",
    "sorte",
    "genre",
    "niveau",
    "degré",
    "point",
    "occident",
    "occidental",
    "orientale",
    "europe",
    "européen",
    "européenne",
    "américain",
}


class StoryService:
    """Service for topic-based story clustering - Hybrid approach."""

    def __init__(self, session: AsyncSession):
        self.session = session

    def _extract_topic_keywords(self, title: str) -> set[str]:
        """Extract topic keywords from a title - focus on named entities."""
        # Normalize
        title_clean = title.lower()
        title_clean = re.sub(r"[^\w\s]", " ", title_clean)

        # Split into words
        words = title_clean.split()

        # Filter to keep significant words (likely topics/entities)
        keywords = {
            w for w in words if len(w) > 3 and w not in STOPWORDS and not w.isdigit()
        }

        return keywords

    async def cluster_hybrid(
        self,
        time_window_hours: int = 168,  # 7 days
    ) -> tuple[int, int, int]:
        """
        Hybrid clustering approach:
        1. Core clusters: 2+ shared specific keywords
        2. Extended clusters: 1 shared keyword + same theme + 48h window

        Returns:
            Tuple of (articles_clustered, total_articles, num_clusters)
        """
        # Reset all clusters
        await self.session.execute(update(Content).values(cluster_id=None))
        await self.session.commit()

        # Get all recent articles
        cutoff_time = datetime.datetime.utcnow() - datetime.timedelta(
            hours=time_window_hours
        )

        stmt = (
            select(Content)
            .options(selectinload(Content.source))
            .where(
                Content.published_at >= cutoff_time, Content.content_type == "article"
            )
            .order_by(Content.published_at.desc())
        )

        result = await self.session.execute(stmt)
        articles = list(result.scalars().all())

        if not articles:
            return 0, 0, 0

        # Pre-compute keywords
        article_keywords: dict[UUID, set[str]] = {}
        for article in articles:
            article_keywords[article.id] = self._extract_topic_keywords(article.title)

        # Union-Find for clustering
        parent = {a.id: a.id for a in articles}

        def find(x):
            if parent[x] != x:
                parent[x] = find(parent[x])
            return parent[x]

        def union(x, y):
            px, py = find(x), find(y)
            if px != py:
                parent[px] = py
                return True
            return False

        # PASS 1: Core clusters (2+ shared keywords, different sources)
        for i, art1 in enumerate(articles):
            kw1 = article_keywords[art1.id]
            for art2 in articles[i + 1 :]:
                if art1.source_id == art2.source_id:
                    continue

                kw2 = article_keywords[art2.id]
                shared = kw1 & kw2

                if len(shared) >= 2:
                    union(art1.id, art2.id)

        # PASS 2: Extended clusters (1 keyword + same theme + 48h window)
        for i, art1 in enumerate(articles):
            kw1 = article_keywords[art1.id]
            theme1 = art1.source.theme if art1.source else None

            for art2 in articles[i + 1 :]:
                if art1.source_id == art2.source_id:
                    continue

                # Check time proximity (48h)
                time_diff = abs((art1.published_at - art2.published_at).total_seconds())
                if time_diff > 48 * 60 * 60:
                    continue

                # Check same theme
                theme2 = art2.source.theme if art2.source else None
                if theme1 != theme2:
                    continue

                kw2 = article_keywords[art2.id]
                shared = kw1 & kw2

                # 1 shared keyword + same theme + 48h = cluster
                if len(shared) >= 1:
                    union(art1.id, art2.id)

        # Build clusters from Union-Find
        clusters: dict[UUID, list[Content]] = defaultdict(list)
        for article in articles:
            root = find(article.id)
            clusters[root].append(article)

        # Assign cluster IDs (only to clusters with 2+ articles and 2+ sources)
        articles_clustered = 0
        num_clusters = 0

        for root, cluster_articles in clusters.items():
            sources_in_cluster = {a.source_id for a in cluster_articles}

            if len(cluster_articles) >= 2 and len(sources_in_cluster) >= 2:
                cluster_id = uuid4()
                num_clusters += 1

                for article in cluster_articles:
                    article.cluster_id = cluster_id
                    articles_clustered += 1

        await self.session.commit()

        return articles_clustered, len(articles), num_clusters

    async def get_cluster_contents(
        self, content_id: UUID, exclude_current: bool = True
    ) -> list[Content]:
        """Get all contents in the same cluster as the given content."""
        stmt = select(Content.cluster_id).where(Content.id == content_id)
        result = await self.session.execute(stmt)
        cluster_id = result.scalar_one_or_none()

        if not cluster_id:
            return []

        stmt = (
            select(Content)
            .options(selectinload(Content.source))
            .where(Content.cluster_id == cluster_id)
        )

        if exclude_current:
            stmt = stmt.where(Content.id != content_id)

        stmt = stmt.order_by(Content.published_at.desc())

        result = await self.session.execute(stmt)
        return list(result.scalars().all())

    async def get_cluster_stats(self) -> dict:
        """Get clustering statistics."""
        from sqlalchemy import func

        total_result = await self.session.execute(
            select(func.count(Content.id)).where(Content.content_type == "article")
        )
        total = total_result.scalar()

        clustered_result = await self.session.execute(
            select(func.count(Content.id)).where(
                Content.cluster_id.isnot(None), Content.content_type == "article"
            )
        )
        clustered = clustered_result.scalar()

        clusters_result = await self.session.execute(
            select(func.count(func.distinct(Content.cluster_id))).where(
                Content.cluster_id.isnot(None)
            )
        )
        num_clusters = clusters_result.scalar()

        return {
            "total_articles": total,
            "clustered_articles": clustered,
            "clustering_rate": (clustered / total * 100) if total > 0 else 0,
            "num_clusters": num_clusters,
            "avg_cluster_size": (clustered / num_clusters) if num_clusters > 0 else 0,
        }
