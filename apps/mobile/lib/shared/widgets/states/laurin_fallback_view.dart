import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/constants.dart';
import '../../../config/theme.dart';
import '../../strings/loader_error_strings.dart';
import '../buttons/primary_button.dart';
import '../buttons/secondary_button.dart';

/// Fallback affiché après plusieurs échecs consécutifs : message rassurant et
/// option de prévenir Laurin (mail / WhatsApp + presse-papier).
class LaurinFallbackView extends StatelessWidget {
  final VoidCallback onRetry;

  const LaurinFallbackView({super.key, required this.onRetry});

  Future<void> _copyToClipboard(BuildContext context) async {
    await Clipboard.setData(
      const ClipboardData(text: LaurinFallbackStrings.prefilledMessage),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(LaurinFallbackStrings.clipboardConfirmation),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _openMail(BuildContext context) async {
    await _copyToClipboard(context);
    final uri = Uri(
      scheme: 'mailto',
      path: LaurinContact.email,
      queryParameters: {
        'subject': LaurinFallbackStrings.mailSubject,
        'body': LaurinFallbackStrings.prefilledMessage,
      },
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openWhatsapp(BuildContext context) async {
    await _copyToClipboard(context);
    final encoded =
        Uri.encodeComponent(LaurinFallbackStrings.prefilledMessage);
    final uri = Uri.parse(
      'https://wa.me/${LaurinContact.whatsappE164}?text=$encoded',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space6,
          vertical: FacteurSpacing.space6,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Icon(
                  PhosphorIcons.heartStraight(PhosphorIconsStyle.duotone),
                  size: 32,
                  color: colors.primary.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: FacteurSpacing.space4),
              Text(
                LaurinFallbackStrings.title,
                textAlign: TextAlign.center,
                style: FacteurTypography.displayMedium(colors.textPrimary),
              ),
              const SizedBox(height: FacteurSpacing.space2),
              Text(
                LaurinFallbackStrings.subtitle,
                textAlign: TextAlign.center,
                style: FacteurTypography.bodyMedium(colors.textSecondary),
              ),
              const SizedBox(height: FacteurSpacing.space6),
              Center(
                child: PrimaryButton(
                  label: LaurinFallbackStrings.retryLabel,
                  icon: PhosphorIcons.arrowClockwise(PhosphorIconsStyle.bold),
                  onPressed: onRetry,
                  fullWidth: false,
                ),
              ),
              const SizedBox(height: FacteurSpacing.space6),
              Container(
                padding: const EdgeInsets.all(FacteurSpacing.space4),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius:
                      BorderRadius.circular(FacteurRadius.medium),
                  border: Border.all(
                    color: colors.border.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      LaurinFallbackStrings.contactSectionTitle,
                      style: FacteurTypography.labelLarge(colors.textPrimary),
                    ),
                    const SizedBox(height: FacteurSpacing.space1),
                    Text(
                      LaurinFallbackStrings.contactSectionSubtitle,
                      style: FacteurTypography.bodySmall(colors.textSecondary),
                    ),
                    const SizedBox(height: FacteurSpacing.space3),
                    SecondaryButton(
                      label: LaurinFallbackStrings.mailLabel,
                      icon: PhosphorIcons.envelopeSimple(
                          PhosphorIconsStyle.regular),
                      onPressed: () => _openMail(context),
                    ),
                    if (LaurinContact.hasWhatsapp) ...[
                      const SizedBox(height: FacteurSpacing.space2),
                      SecondaryButton(
                        label: LaurinFallbackStrings.whatsappLabel,
                        icon: PhosphorIcons.whatsappLogo(
                            PhosphorIconsStyle.regular),
                        onPressed: () => _openWhatsapp(context),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
