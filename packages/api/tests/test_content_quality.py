from app.services.content_quality import compute_content_quality


def test_quality_uses_plain_text_length_for_rss_html():
    assert compute_content_quality(f"<p>{'a' * 500}</p>") == "full"
    assert compute_content_quality(f"<div>{'a' * 100}</div>") == "partial"
    assert compute_content_quality("<p>court</p>") == "none"


def test_quality_collapses_markup_and_whitespace():
    html = "<p>" + ("mot " * 26) + "</p>"
    assert compute_content_quality(html) == "partial"
