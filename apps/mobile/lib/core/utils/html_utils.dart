/// Utilitaires de nettoyage HTML pour l'affichage de texte RSS.
///
/// Extrait de [ArticlePreviewOverlay._stripHtml] pour réutilisation
/// dans les cards feed/digest et le reader in-app.

/// Supprime les balises HTML et décode les entités HTML courantes.
///
/// Utilisé pour nettoyer les descriptions RSS qui peuvent contenir
/// du HTML brut avant affichage dans les cards et previews.
String stripHtml(String html) {
  // Remove HTML tags
  var text = html.replaceAll(RegExp(r'<[^>]+>'), '');
  // Decode common HTML entities
  text = text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&#8217;', '\u2019')
      .replaceAll('&#8216;', '\u2018')
      .replaceAll('&#8220;', '\u201C')
      .replaceAll('&#8221;', '\u201D');
  // Collapse multiple whitespace/newlines into single space
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text;
}

/// Nettoie le HTML d'un article pour le reader in-app.
///
/// - Décode les entités HTML (gère le double encodage RSS)
/// - Supprime les images et figures (affichées séparément en hero)
/// - Supprime les paragraphes et divs vides
/// - Préserve les balises sémantiques (p, h1-h6, blockquote, ul, etc.)
String sanitizeArticleHtml(String html) {
  var content = html;
  // Decode HTML entities (handles double-encoded RSS content)
  content = content
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'");
  // Strip figure elements (includes figcaption) — order matters
  content = content.replaceAll(
      RegExp(r'<figure[^>]*>.*?</figure>', dotAll: true), '');
  // Strip standalone img tags
  content = content.replaceAll(RegExp(r'<img[^>]*/?>', dotAll: true), '');
  // Strip orphaned figcaptions
  content = content.replaceAll(
      RegExp(r'<figcaption[^>]*>.*?</figcaption>', dotAll: true), '');
  // Strip empty paragraphs and divs
  content = content.replaceAll(RegExp(r'<(p|div)[^>]*>\s*</(p|div)>'), '');
  // Strip trailing "Lire aussi" link blocks (lists where all items are just links)
  content = content.replaceAll(
      RegExp(
          r'<(ul|ol)[^>]*>(\s*<li[^>]*>\s*<a[^>]*>.*?</a>\s*</li>\s*)+</(ul|ol)>\s*$',
          dotAll: true),
      '');
  // Strip trailing consecutive link-only paragraphs (2+ in a row at end)
  content = content.replaceAll(
      RegExp(r'(\s*<p[^>]*>\s*<a[^>]*>.*?</a>\s*</p>\s*){2,}$', dotAll: true),
      '');
  return content.trim();
}

/// Calcule la longueur en texte brut après nettoyage HTML.
///
/// Utile pour déterminer la qualité du contenu :
/// - >= 500 chars : contenu complet
/// - 100-500 chars : aperçu partiel
/// - < 100 chars : contenu insuffisant
int plainTextLength(String? html) {
  if (html == null || html.isEmpty) return 0;
  return stripHtml(html).length;
}
