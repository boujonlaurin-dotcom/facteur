import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../config/theme.dart';
import '../../../../core/utils/html_utils.dart';

/// Widget for rendering HTML article content in-app (Story 5.2)
class ArticleReaderWidget extends StatelessWidget {
  final String? htmlContent;
  final String? description;
  final String title;
  final VoidCallback? onLinkTap;
  final Widget? header;
  final Widget? footer;

  const ArticleReaderWidget({
    super.key,
    this.htmlContent,
    this.description,
    required this.title,
    this.onLinkTap,
    this.header,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    // Sanitize htmlContent, fallback to description if result is empty
    String content = '';
    if (htmlContent != null && htmlContent!.isNotEmpty) {
      content = sanitizeArticleHtml(htmlContent!);
    }
    if (content.isEmpty && description != null && description!.isNotEmpty) {
      content = sanitizeArticleHtml(description!);
    }

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null) header!,
        Html(
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
              'p': Style(
                margin: Margins.only(bottom: 16),
              ),
              'h1': Style(
                fontSize: FontSize(24),
                fontWeight: FontWeight.w600,
                margin: Margins.only(bottom: 16, top: 24),
                color: colors.textPrimary,
              ),
              'h2': Style(
                fontSize: FontSize(20),
                fontWeight: FontWeight.w600,
                margin: Margins.only(bottom: 12, top: 20),
                color: colors.textPrimary,
              ),
              'h3': Style(
                fontSize: FontSize(18),
                fontWeight: FontWeight.w500,
                margin: Margins.only(bottom: 8, top: 16),
                color: colors.textPrimary,
              ),
              'a': Style(
                color: colors.textSecondary,
                textDecoration: TextDecoration.none,
              ),
              'img': Style(
                margin: Margins.symmetric(vertical: 16),
              ),
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
              'ul': Style(
                margin: Margins.only(bottom: 16),
              ),
              'ol': Style(
                margin: Margins.only(bottom: 16),
              ),
              'li': Style(
                margin: Margins.only(bottom: 8),
              ),
              'figure': Style(
                margin: Margins.symmetric(vertical: 16),
              ),
              'figcaption': Style(
                fontSize: FontSize(14),
                color: colors.textTertiary,
                textAlign: TextAlign.center,
                margin: Margins.only(top: 8),
              ),
            },
            onLinkTap: (url, _, __) async {
              if (url != null) {
                final uri = Uri.tryParse(url);
                if (uri != null && await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              }
            },
          ),
          if (footer != null) ...[
            const SizedBox(height: 32),
            footer!,
            const SizedBox(height: 32),
          ],
        ],
      );

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space4),
      child: column,
    );
  }
}
