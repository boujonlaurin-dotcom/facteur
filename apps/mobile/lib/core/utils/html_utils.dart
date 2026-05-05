/// Utilitaires de nettoyage HTML pour l'affichage de texte RSS.
///
/// Extrait de [ArticlePreviewOverlay._stripHtml] pour réutilisation
/// dans les cards feed/digest et le reader in-app.
library;

/// Décode les entités HTML (named + numériques decimal/hex), en bouclant
/// pour gérer le multi-encodage (ex: `&amp;lt;` → `&lt;` → `<`).
///
/// Robuste face aux flux RSS où les entités peuvent être encodées 1, 2 ou
/// 3 fois selon les pipelines. Limite la boucle à 3 passes.
String decodeHtmlEntities(String input) {
  var text = input;
  for (var pass = 0; pass < 3; pass++) {
    final before = text;
    // Numeric entities (decimal & hex) — handles any code point.
    text = text.replaceAllMapped(
      RegExp(r'&#(x[0-9a-fA-F]+|[0-9]+);'),
      (m) {
        final raw = m.group(1)!;
        final code = raw.startsWith('x') || raw.startsWith('X')
            ? int.tryParse(raw.substring(1), radix: 16)
            : int.tryParse(raw);
        if (code == null || code < 0 || code > 0x10FFFF) return m.group(0)!;
        return String.fromCharCode(code);
      },
    );
    // Named entities. `&amp;` must come last so pre-existing `&amp;lt;`
    // becomes `&lt;` and gets fully decoded on the next pass.
    text = text
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&laquo;', '«')
        .replaceAll('&raquo;', '»')
        .replaceAll('&hellip;', '…')
        .replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–')
        .replaceAll('&lsquo;', '‘')
        .replaceAll('&rsquo;', '’')
        .replaceAll('&ldquo;', '“')
        .replaceAll('&rdquo;', '”')
        .replaceAll('&amp;', '&');
    if (text == before) break;
  }
  return text;
}

/// Supprime les balises HTML et décode les entités HTML courantes.
///
/// Utilisé pour nettoyer les descriptions RSS qui peuvent contenir
/// du HTML brut avant affichage dans les cards et previews.
String stripHtml(String html) {
  // Decode entities first so encoded `&lt;p&gt;` becomes `<p>` and is then
  // stripped by the tag regex below.
  var text = decodeHtmlEntities(html);
  // Remove HTML tags
  text = text.replaceAll(RegExp(r'<[^>]+>'), '');
  // Collapse multiple whitespace/newlines into single space
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text;
}

/// Nettoie le HTML d'un article pour le reader in-app.
///
/// - Décode les entités HTML (gère le double/triple encodage RSS, named +
///   numérique)
/// - Supprime les images et figures (affichées séparément en hero)
/// - Supprime les paragraphes et divs vides
/// - Préserve les balises sémantiques (p, h1-h6, blockquote, ul, etc.)
String sanitizeArticleHtml(String html) {
  // Decode HTML entities (handles single, double or triple-encoded RSS
  // content, including named and numeric entities).
  var content = decodeHtmlEntities(html);
  // Strip figure elements (includes figcaption) — order matters
  content = content.replaceAll(
      RegExp(r'<figure[^>]*>.*?</figure>', dotAll: true), '');
  // Strip standalone img tags
  content = content.replaceAll(RegExp(r'<img[^>]*/?>', dotAll: true), '');
  // Strip orphaned figcaptions
  content = content.replaceAll(
      RegExp(r'<figcaption[^>]*>.*?</figcaption>', dotAll: true), '');
  // Strip non-content elements that cause large whitespace gaps
  content = content.replaceAll(
      RegExp(r'<iframe[^>]*>.*?</iframe>', dotAll: true), '');
  content = content.replaceAll(RegExp(r'<iframe[^>]*/?>', dotAll: true), '');
  content = content.replaceAll(
      RegExp(r'<aside[^>]*>.*?</aside>', dotAll: true), '');
  content = content.replaceAll(
      RegExp(r'<svg[^>]*>.*?</svg>', dotAll: true), '');
  content = content.replaceAll(
      RegExp(r'<noscript[^>]*>.*?</noscript>', dotAll: true), '');
  content = content.replaceAll(
      RegExp(r'<button[^>]*>.*?</button>', dotAll: true), '');
  // Strip empty spans
  content = content.replaceAll(RegExp(r'<span[^>]*>\s*</span>'), '');
  // Collapse 3+ consecutive <br> tags into 2
  content = content.replaceAll(
      RegExp(r'(<br\s*/?\s*>[\s]*){3,}'), '<br><br>');
  // Strip interstitial "À lire aussi / Read also" blocks (hr + link paragraph + hr)
  // Common in The Conversation and similar academic sources
  content = content.replaceAll(
      RegExp(
          r'<hr[^>]*/?\s*>\s*<p[^>]*>\s*(<em>)?\s*(<strong>)?\s*'
          r'(À lire aussi|A lire aussi|Read also|Lire aussi)\s*'
          r'[:\s]*<a[^>]*>.*?</a>\s*(</strong>)?\s*(</em>)?\s*</p>\s*<hr[^>]*/?\s*>',
          dotAll: true,
          caseSensitive: false),
      '');
  // Strip <hr> tags (horizontal rules create unwanted visual gaps in reader)
  content = content.replaceAll(RegExp(r'<hr[^>]*/?\s*>'), '');
  // Strip empty paragraphs and divs (run twice to catch newly-emptied containers)
  content = content.replaceAll(RegExp(r'<(p|div)[^>]*>\s*</(p|div)>'), '');
  content = content.replaceAll(RegExp(r'<(p|div)[^>]*>\s*</(p|div)>'), '');
  // Strip trailing <br> tags to prevent extra line-height whitespace at article end
  content = content.replaceAll(RegExp(r'(\s*<br\s*/?\s*>)+\s*$'), '');
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

/// Common RSS truncation patterns indicating partial/teaser content.
final _truncationPatterns = [
  RegExp(r'\(\.\.\.\)\s*$'),               // ends with (...)
  RegExp(r'\.\.\.\s*$'),                    // ends with ...
  RegExp(r'\[\.\.\.]\s*$'),                 // ends with [...]
  RegExp(r'Lire la suite', caseSensitive: false),
  RegExp(r'Read more', caseSensitive: false),
  RegExp(r'Continue reading', caseSensitive: false),
  RegExp(r"L['’]article .+ est apparu en premier sur", caseSensitive: false),
  RegExp(r'Cet article .+ est publié sur', caseSensitive: false),
  RegExp(r'The post .+ appeared first on', caseSensitive: false),
];

/// Detects whether HTML content is likely a partial/truncated RSS excerpt.
///
/// Combines length check (< 500 chars) with common RSS truncation patterns.
bool isPartialContent(String? html) {
  if (html == null || html.isEmpty) return true;
  final text = stripHtml(html);
  if (text.length < 500) return true;
  return _truncationPatterns.any((p) => p.hasMatch(text));
}

/// Finds the position in [html] (a raw HTML string) after [wordLimit] plain-text words.
///
/// Walks char-by-char, skipping HTML tags. Returns the position in the HTML
/// string immediately after the [wordLimit]th word boundary, or null if the
/// text contains fewer words than [wordLimit].
int? _findPositionAfterNWords(String html, int wordLimit) {
  int wordCount = 0;
  int i = 0;
  bool inTag = false;
  bool inWord = false;

  while (i < html.length) {
    final c = html[i];
    if (c == '<') {
      if (inWord) {
        wordCount++;
        inWord = false;
        if (wordCount >= wordLimit) return i;
      }
      inTag = true;
    } else if (c == '>') {
      inTag = false;
    } else if (!inTag) {
      final isSpace = c == ' ' || c == '\n' || c == '\r' || c == '\t';
      if (isSpace) {
        if (inWord) {
          wordCount++;
          inWord = false;
          if (wordCount >= wordLimit) return i;
        }
      } else {
        inWord = true;
      }
    }
    i++;
  }
  if (inWord) {
    wordCount++;
    if (wordCount >= wordLimit) return html.length;
  }
  return null;
}

/// Cuts sanitized HTML at the first natural break after [wordLimit] plain-text
/// words, or just before the first subtitle (`<h1>`–`<h6>`), whichever is earlier.
///
/// Break-point search order after [wordLimit] words: `</p>`, then `<br`, then
/// the raw word position (fallback for HTML without paragraph tags).
///
/// Returns the cut HTML string, or null if the content is too short to cut
/// (fewer than [wordLimit] words and no heading found).
String? cutHtmlAtPreview(String html, {int wordLimit = 150}) {
  final sanitized = sanitizeArticleHtml(html);
  if (sanitized.isEmpty) return null;

  // Option B: position of first heading tag
  final headingMatch =
      RegExp(r'<h[1-6][\s>]', caseSensitive: false).firstMatch(sanitized);
  final firstHeadingPos = headingMatch?.start;

  // Option A: first natural break after the wordLimit-th word.
  // Try </p>, then <br (as fallback), then cut at word position directly.
  final wordPos = _findPositionAfterNWords(sanitized, wordLimit);
  int? optionA;
  if (wordPos != null) {
    final pClose = sanitized.indexOf('</p>', wordPos);
    final brTag = sanitized.indexOf('<br', wordPos);

    if (pClose != -1 && (brTag == -1 || pClose <= brTag)) {
      optionA = pClose + 4; // include </p>
    } else if (brTag != -1) {
      optionA = brTag; // cut just before <br
    } else {
      optionA = wordPos; // no block break found — cut at word boundary
    }
  }

  if (optionA == null && firstHeadingPos == null) return null;
  if (optionA == null) return sanitized.substring(0, firstHeadingPos!).trim();
  if (firstHeadingPos == null) return sanitized.substring(0, optionA).trim();

  final cutPos = optionA < firstHeadingPos ? optionA : firstHeadingPos;
  if (cutPos <= 0) return null;
  return sanitized.substring(0, cutPos).trim();
}
