import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../core/ui/notification_service.dart';
import '../../../shared/widgets/buttons/primary_button.dart';
import '../providers/checkout_link_provider.dart';
import '../soutien_copy.dart';

/// Confirmation « lien envoyé » : enveloppe + cachet daté, retour lecture,
/// renvoi du lien (429 Supabase → toast « patiente une minute »).
class LinkSentScreen extends ConsumerStatefulWidget {
  const LinkSentScreen({super.key});

  @override
  ConsumerState<LinkSentScreen> createState() => _LinkSentScreenState();
}

class _LinkSentScreenState extends ConsumerState<LinkSentScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _stampController;
  late final Animation<double> _stampScale;

  bool _frLocaleReady = false;

  @override
  void initState() {
    super.initState();
    // La locale fr d'intl n'est pas initialisée ailleurs dans l'app : on la
    // charge ici, avec fallback locale par défaut tant qu'elle n'est pas prête.
    initializeDateFormatting('fr').then((_) {
      if (mounted) setState(() => _frLocaleReady = true);
    });
    _stampController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _stampScale = CurvedAnimation(
      parent: _stampController,
      curve: Curves.easeOutBack,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Accessibilité : pas d'animation de cachet si le système la désactive.
      if (MediaQuery.of(context).disableAnimations) {
        _stampController.value = 1.0;
      } else {
        _stampController.forward();
      }
    });
  }

  @override
  void dispose() {
    _stampController.dispose();
    super.dispose();
  }

  Future<void> _resend() async {
    try {
      await ref.read(checkoutLinkProvider.notifier).sendLink(resend: true);
      NotificationService.showSuccess(SoutienCopy.linkSentResendSuccess);
    } catch (e) {
      NotificationService.showError(checkoutErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final isResending = ref.watch(checkoutLinkProvider).isLoading;
    final dateLabel = _frLocaleReady
        ? DateFormat('d MMM yyyy', 'fr').format(DateTime.now())
        : DateFormat('d MMM yyyy').format(DateTime.now());

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FacteurSpacing.space6),
          child: Column(
            children: [
              const Spacer(),
              Stack(
                alignment: Alignment.topRight,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(FacteurSpacing.space4),
                    child: Icon(
                      PhosphorIcons.envelopeSimple(PhosphorIconsStyle.duotone),
                      size: 96,
                      color: colors.primary,
                    ),
                  ),
                  ScaleTransition(
                    scale: _stampScale,
                    child: Transform.rotate(
                      angle: 0.12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: FacteurSpacing.space2,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: colors.primary, width: 2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Column(
                          children: [
                            Text(
                              SoutienCopy.linkSentStamp,
                              style: GoogleFonts.courierPrime(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                                color: colors.primary,
                              ),
                            ),
                            Text(
                              dateLabel.toUpperCase(),
                              style: GoogleFonts.courierPrime(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                                color: colors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FacteurSpacing.space6),
              Text(
                SoutienCopy.linkSentHeadline,
                textAlign: TextAlign.center,
                style: GoogleFonts.fraunces(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: FacteurSpacing.space3),
              Text(
                SoutienCopy.linkSentBody,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: FacteurSpacing.space3),
              Text(
                SoutienCopy.linkSentSpamHint,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: colors.textTertiary,
                ),
              ),
              const Spacer(),
              PrimaryButton(
                label: SoutienCopy.linkSentBack,
                onPressed: () => context.pop(),
              ),
              const SizedBox(height: FacteurSpacing.space2),
              TextButton(
                onPressed: isResending ? null : _resend,
                child: Text(
                  SoutienCopy.linkSentResend,
                  style: textTheme.labelLarge?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
