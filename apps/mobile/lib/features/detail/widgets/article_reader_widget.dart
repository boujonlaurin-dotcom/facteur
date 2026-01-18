import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../config/theme.dart';

/// Widget for rendering HTML article content in-app (Story 5.2)
class ArticleReaderWidget extends StatelessWidget {
  final String? htmlContent;
  final String? description;
  final String title;
  final VoidCallback? onLinkTap;
  final Widget? footer;

  const ArticleReaderWidget({
    super.key,
    this.htmlContent,
    this.description,
    required this.title,
    this.onLinkTap,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    // Use htmlContent if available, otherwise fall back to description
    final content = htmlContent ?? description ?? '';

    if (content.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(FacteurSpacing.space6),
          child: Text(
            'Contenu non disponible',
            style: textTheme.bodyLarge?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Html(
            data: content,
            style: {
              'body': Style(
                fontSize: FontSize(17),
                lineHeight: LineHeight(1.7),
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
                color: colors.primary,
                textDecoration: TextDecoration.underline,
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
      ),
    );
  }
}
