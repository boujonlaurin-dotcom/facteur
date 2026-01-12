import pytest
from app.services.perspective_service import PerspectiveService

def test_perspective_filtering_logic():
    service = PerspectiveService()
    
    # Mock RSS content with 3 items
    mock_rss = b"""<?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0">
    <channel>
        <item>
            <title>Article Original - Le Monde</title>
            <link>http://lemonde.fr/article1</link>
            <source url="http://lemonde.fr">Le Monde</source>
        </item>
        <item>
            <title>Autre Article - Figaro</title>
            <link>http://lefigaro.fr/article2</link>
            <source url="http://lefigaro.fr">Le Figaro</source>
        </item>
        <item>
            <title>Doublon Titre - Libe</title>
            <link>http://liberation.fr/article3</link>
            <source url="http://liberation.fr">Liberation</source>
        </item>
    </channel>
    </rss>"""
    
    # 1. Test without exclusion
    results = service._parse_rss(mock_rss)
    assert len(results) == 3
    
    # 2. Test with URL exclusion
    results_url = service._parse_rss(mock_rss, exclude_url="http://lemonde.fr/article1")
    assert len(results_url) == 2
    assert results_url[0].title == "Autre Article - Figaro"
    
    # 3. Test with Title exclusion (similarity check)
    # The logic splits by " - " and compares
    results_title = service._parse_rss(mock_rss, exclude_title="Doublon Titre")
    assert len(results_title) == 2
    assert results_title[1].title == "Autre Article - Figaro" # Order might change due to set, but here list
    # Actually Liberation was the 3rd one.
    titles = [r.title for r in results_title]
    assert "Doublon Titre - Libe" not in titles
