import datetime
from app.services.recommendation.scoring_engine import BaseScoringLayer, ScoringContext
from app.models.content import Content
from app.models.enums import ContentType

class StaticPreferenceLayer(BaseScoringLayer):
    """
    Couche gérant les préférences statiques déclarées lors de l'onboarding.
    - contentRecency: Ajuste le poids de la récence.
    - formatPreference: Boost certains types ou durées.
    """
    
    @property
    def name(self) -> str:
        return "static_prefs"

    def score(self, content: Content, context: ScoringContext) -> float:
        score = 0.0
        prefs = context.user_prefs
        
        # 1. Content Recency Preference
        # recent -> on veut que la récence pèse PLUS (donc on ajoute un bonus aux items récents)
        # timeless -> on veut que la récence pèse MOINS (donc on compense le decay ou on boost les items vieux, ici on va booster légèrement les items "timeless" pour compenser le decay standard du CoreLayer)
        recency_pref = prefs.get('content_recency') # recent, timeless, balanced
        
        if recency_pref == 'recent':
             # Boost supplémentaire pour les items très récents (< 24h)
             if content.published_at:
                published = content.published_at
                now = context.now
                # Ensure both are tz-aware for safe subtraction
                if published.tzinfo is None:
                    published = published.replace(tzinfo=datetime.timezone.utc)
                if now.tzinfo is None:
                    now = now.replace(tzinfo=datetime.timezone.utc)
                hours_old = (now - published).total_seconds() / 3600.0
                if hours_old < 24:
                    score += 15.0 # Bonus fraîcheur
                    context.add_reason(content.id, self.name, 15.0, "Pref: Recent content")

        elif recency_pref == 'timeless':
            # On s'en fiche un peu de la récence, donc on peut redonner des points aux vieux articles
            # pour qu'ils remontent malgré le decay du CoreLayer.
             if content.published_at:
                published = content.published_at
                now = context.now
                # Ensure both are tz-aware for safe subtraction
                if published.tzinfo is None:
                    published = published.replace(tzinfo=datetime.timezone.utc)
                if now.tzinfo is None:
                    now = now.replace(tzinfo=datetime.timezone.utc)
                hours_old = (now - published).total_seconds() / 3600.0
                if hours_old > 48:
                    score += 10.0 # Bonus "Archive"
                    context.add_reason(content.id, self.name, 10.0, "Pref: Timeless content")

        # 2. Format Preference
        # short, long, audio, video
        format_pref = prefs.get('format_preference')
        
        if format_pref:
            bonus = 0.0
            triggered = False
            
            if format_pref == 'audio' and content.content_type == ContentType.PODCAST:
                bonus = 20.0
                triggered = True
            elif format_pref == 'video' and content.content_type == ContentType.VIDEO:
                bonus = 20.0
                triggered = True
            elif format_pref == 'short' and content.duration_seconds and content.duration_seconds <= 300:
                # <= 5 min
                bonus = 15.0
                triggered = True
            elif format_pref == 'long' and content.duration_seconds and content.duration_seconds >= 900:
                # >= 15 min
                bonus = 15.0
                triggered = True
                
            if triggered:
                score += bonus
                context.add_reason(content.id, self.name, bonus, f"Pref: {format_pref} match")
                
        return score
