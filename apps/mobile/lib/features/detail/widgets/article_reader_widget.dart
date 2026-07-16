import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../config/theme.dart';
import '../../../../core/utils/html_utils.dart';

/// Widget for rendering HTML article content in-app (Story 5.2)
class ArticleReaderWidget extends StatefulWidget {
  final String? htmlContent;
  final String? description;
  final String title;
  final void Function(String url)? onLinkTap;
  final Widget? header;
  final Widget? footer;
  final double footerSpacing;
  final bool shrinkWrap;

  /// When non-null, replaces the HTML body with this widget (e.g. skeleton).
  final Widget? bodyPlaceholder;

  const ArticleReaderWidget({
    super.key,
    this.htmlContent,
    this.description,
    required this.title,
    this.onLinkTap,
    this.header,
    this.footer,
    this.footerSpacing = FacteurSpacing.space8,
    this.shrinkWrap = false,
    this.bodyPlaceholder,
  });

  @override
  State<ArticleReaderWidget> createState() => _ArticleReaderWidgetState();
}

class _ArticleReaderWidgetState extends State<ArticleReaderWidget> {
  /// HTML sanitisé, mémoïsé : `sanitizeArticleHtml` (regex lourdes) ne se relance
  /// qu'au changement de `htmlContent`/`description`, pas à chaque `setState` de
  /// l'écran parent (nombreux à l'ouverture).
  late String _sanitized;

  @override
  void initState() {
    super.initState();
    _sanitized = _computeSanitized();
  }

  @override
  void didUpdateWidget(ArticleReaderWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.htmlContent != widget.htmlContent ||
        oldWidget.description != widget.description) {
      _sanitized = _computeSanitized();
    }
  }

  String _computeSanitized() {
    // Sanitize htmlContent, fallback to description if result is empty
    String content = '';
    if (widget.htmlContent != null && widget.htmlContent!.isNotEmpty) {
      content = sanitizeArticleHtml(widget.htmlContent!);
    }
    if (content.isEmpty &&
        widget.description != null &&
        widget.description!.isNotEmpty) {
      content = sanitizeArticleHtml(widget.description!);
    }
    return content;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final content = _sanitized;

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.header != null) widget.header!,
        if (widget.bodyPlaceholder != null)
          widget.bodyPlaceholder!
        else
          RepaintBoundary(
            child: Html(
              data: content,
              style: {
                'body': Style(
                  fontSize: FontSize(17),
                  lineHeight: const LineHeight(1.7),
                  color: colors.textPrimary,
                  fontFamily: 'DMSans',
                  margin: Margins.zero,
                  padding: HtmlPaddings.zero,
                ),
                'p': Style(margin: Margins.only(bottom: 16)),
                'h1': Style(
                  fontSize: FontSize(24),
                  fontWeight: FontWeight.w600,
                  margin: Margins.only(bottom: 16, top: 24),
                  color: colors.textPrimary,
                ),
                'h2': Style(
                  fontSize: FontSize(20),
                  fontWeight: FontWeight.w600,
                  margin: Margins.only(bottom: 16, top: 24),
                  color: colors.textPrimary,
                ),
                'h3': Style(
                  fontSize: FontSize(18),
                  fontWeight: FontWeight.w500,
                  margin: Margins.only(bottom: 16, top: 16),
                  color: colors.textPrimary,
                ),
                'a': Style(
                  color: colors.textSecondary,
                  textDecoration: TextDecoration.none,
                ),
                'img': Style(margin: Margins.symmetric(vertical: 16)),
                'blockquote': Style(
                  border: Border(
                    left: BorderSide(
                      color: colors.primary.withValues(alpha: 0.5),
                      width: 3,
                    ),
                  ),
                  padding: HtmlPaddings.only(left: 16),
                  margin: Margins.symmetric(vertical: 16),
                  fontStyle: FontStyle.italic,
                  color: colors.textSecondary,
                ),
                'ul': Style(margin: Margins.only(bottom: 16)),
                'ol': Style(margin: Margins.only(bottom: 16)),
                'li': Style(margin: Margins.only(bottom: 8)),
                'figure': Style(margin: Margins.symmetric(vertical: 16)),
                'figcaption': Style(
                  fontSize: FontSize(14),
                  color: colors.textTertiary,
                  textAlign: TextAlign.center,
                  margin: Margins.only(top: 8),
                ),
                // Defensive: prevent leftover divs/iframes/asides from creating gaps
                'div': Style(margin: Margins.zero, padding: HtmlPaddings.zero),
                'iframe': Style(display: Display.none),
                'aside': Style(display: Display.none),
              },
              onLinkTap: (url, _, __) async {
                if (url != null) {
                  if (widget.onLinkTap != null) {
                    widget.onLinkTap!(url);
                  } else {
                    final uri = Uri.tryParse(url);
                    if (uri != null && await canLaunchUrl(uri)) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  }
                }
              },
            ),
          ),
        if (widget.footer != null) ...[
          if (widget.footerSpacing > 0) SizedBox(height: widget.footerSpacing),
          widget.footer!,
        ],
      ],
    );

    if (widget.shrinkWrap) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space4),
        child: column,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space4),
      child: column,
    );
  }
}
