import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../errors/user_facing_error_notifier.dart';
import 'notification_service.dart';

/// UI (pure, sans Riverpod) de la bannière « un truc s'est mal passé » et de
/// sa feuille de report 1-champ. Les effets de bord (Sentry, PostHog,
/// `markReported`) sont injectés par le wiring root — cf. `app.dart`.
class UserFacingErrorBanner {
  UserFacingErrorBanner._();

  static Timer? _autoHideTimer;

  /// Affiche la [MaterialBanner] discrète en bas de la messagerie globale.
  ///
  /// - Variante standard : texte + CTA souligné « Nous dire » + ✕, auto-dismiss 8s.
  /// - Variante [UserFacingErrorEvent.shortAck] : ack court sans CTA, 1,5s.
  static void show(
    ScaffoldMessengerState messenger,
    UserFacingErrorEvent event, {
    required VoidCallback onReport,
  }) {
    _autoHideTimer?.cancel();
    messenger.hideCurrentMaterialBanner();

    final context = NotificationService.messengerKey.currentContext;
    final colors = context?.facteurColors;
    final surface = colors?.surface ?? const Color(0xFF1E1E1E);
    final border = colors?.border ?? const Color(0xFF3A3A3A);
    final textPrimary = colors?.textPrimary ?? Colors.white;
    final textSecondary = colors?.textSecondary ?? Colors.white70;
    final accent = colors?.primary ?? const Color(0xFFD35400);

    void dismiss() {
      _autoHideTimer?.cancel();
      messenger.hideCurrentMaterialBanner();
    }

    final message = event.shortAck
        ? 'On est au courant, merci.'
        : 'Un truc s\'est mal passé de notre côté.';

    messenger.showMaterialBanner(
      MaterialBanner(
        backgroundColor: surface,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        content: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: border)),
          ),
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            message,
            style: FacteurTypography.bodySmall(
              event.shortAck ? textSecondary : textPrimary,
            ),
          ),
        ),
        actions: event.shortAck
            ? const [SizedBox.shrink()]
            : [
                TextButton(
                  onPressed: () {
                    dismiss();
                    onReport();
                  },
                  child: Text(
                    'Nous dire',
                    style: FacteurTypography.labelMedium(accent).copyWith(
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, size: 18, color: textSecondary),
                  onPressed: dismiss,
                ),
              ],
      ),
    );

    _autoHideTimer = Timer(
      event.shortAck
          ? const Duration(milliseconds: 1500)
          : const Duration(seconds: 8),
      dismiss,
    );
  }

  /// Feuille basse 1-champ « Qu'est-ce qui s'est passé ? ». Le commentaire est
  /// optionnel. [onSubmit] reçoit le texte saisi (peut être vide).
  static Future<void> showReportSheet(
    BuildContext context, {
    required Future<void> Function(String comment) onSubmit,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ReportSheet(onSubmit: onSubmit),
    );
  }
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.onSubmit});

  final Future<void> Function(String comment) onSubmit;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) return;
    setState(() => _sending = true);
    final comment = _controller.text.trim();
    try {
      await widget.onSubmit(comment);
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Qu\'est-ce qui s\'est passé ?',
              style: FacteurTypography.bodyLarge(colors.textPrimary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 2,
              maxLength: 200,
              enabled: !_sending,
              style: FacteurTypography.bodyMedium(colors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Optionnel — ce que tu faisais, ce qui a bugué.',
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _sending ? null : _submit,
              child: _sending
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Envoyer'),
            ),
          ],
        ),
      ),
    );
  }
}
