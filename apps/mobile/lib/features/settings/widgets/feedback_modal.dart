import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../config/constants.dart';
import '../../../config/theme.dart';

class FeedbackModal extends StatelessWidget {
  const FeedbackModal({super.key});

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Container(
      decoration: BoxDecoration(
        color: colors.backgroundPrimary,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textTertiary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Donner mon avis',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Votre retour nous aide à améliorer Facteur',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
              ),
              const SizedBox(height: 20),
              _FeedbackOption(
                icon: PhosphorIcons.users(PhosphorIconsStyle.regular),
                title: 'Rejoindre le groupe',
                subtitle: 'Facteur — Retours & idées',
                onTap: () => _launch(ExternalLinks.whatsappGroupUrl),
              ),
              if (LaurinContact.hasWhatsapp) ...[
                const SizedBox(height: 12),
                _FeedbackOption(
                  icon: PhosphorIcons.chatText(PhosphorIconsStyle.regular),
                  title: 'Envoyer un message à Laurin',
                  subtitle: 'Réponse garantie',
                  onTap: () => _launch(
                    'https://wa.me/${LaurinContact.whatsappE164}?text=Retours%20Facteur%20',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedbackOption extends StatelessWidget {
  const _FeedbackOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Material(
      color: colors.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(FacteurRadius.large),
      child: InkWell(
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(FacteurSpacing.space4),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(FacteurRadius.medium),
                ),
                child: Icon(icon, color: colors.primary, size: 20),
              ),
              const SizedBox(width: FacteurSpacing.space4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                PhosphorIcons.arrowRight(PhosphorIconsStyle.regular),
                color: colors.textTertiary,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
