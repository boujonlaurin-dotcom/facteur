"""Test the improved keyword extraction."""

import sys
sys.path.append('.')
from app.services.perspective_service import PerspectiveService

svc = PerspectiveService()

tests = [
    "Le public doit primer sur l'arbitraire du président : Jerome Powell contre Donald Trump",
    "Macron annonce un plan pour l'IA en France",
    "Venezuela : Maria Corina Machado remporte le Prix Nobel",
    "Comment la France a détrôné l'Irlande dans le classement",
    "En quoi pourraient consister des sanctions économiques contre les États-Unis ?",
]

for title in tests:
    keywords = svc.extract_keywords(title)
    print(f"📰 {title[:55]}...")
    print(f"   → Keywords: {keywords}")
    print()
