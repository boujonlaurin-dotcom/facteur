import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../notifications/widgets/notification_activation_modal.dart';
import '../../settings/providers/notifications_settings_provider.dart';
import '../../sources/utils/publication_frequency.dart';
import '../models/alert_item.dart';
import '../providers/alerts_provider.dart';

/// Rangée « Alerte » partagée par la fiche source et la fiche sujet.
///
/// Alertes v2 : le switch n'est **jamais** grisé. La v1 refusait la cloche sur
/// une source bavarde et affichait l'interdiction — ça vendait une frustration.
/// Ici on autorise partout et on remplace le veto par un devis de bruit
/// honnête : la cadence en ligne 2, et sur une cible bruyante un avertissement
/// chiffré plus la case « seulement les plus marquantes », pré-cochée.
///
/// ```
/// [cloche]  Alerte                                       [switch]
///           Publie environ 3 fois par semaine
///           ─────────────────────────────────────────────────────
///           ⚠  Environ 12 alertes par semaine
///           [x] Seulement les plus marquantes (1 max par jour)
/// ```
class AlertToggleRow extends ConsumerStatefulWidget {
  /// Identifiant de la cible — source ou sujet selon [kind].
  final String targetId;
  final AlertKind kind;

  /// Rythme de parution, en articles par semaine.
  ///
  /// C'est la **seule** entrée de cadence : les sources la dérivent de leur
  /// profil, les sujets la reçoivent déjà calculée du backend. Passer par une
  /// valeur commune évite que le devis affiché diverge de celui qui gouverne
  /// réellement les envois.
  final double cadencePerWeek;

  /// `false` = cadence pas encore chargée : la ligne reste muette plutôt que
  /// de promettre un rythme que les chiffres ne soutiennent pas.
  final bool hasProfile;

  const AlertToggleRow({
    super.key,
    required this.targetId,
    required this.kind,
    required this.cadencePerWeek,
    this.hasProfile = true,
  });

  @override
  ConsumerState<AlertToggleRow> createState() => _AlertToggleRowState();
}

class _AlertToggleRowState extends ConsumerState<AlertToggleRow> {
  bool _busy = false;

  /// Réglage local du mode filtré, tant que l'utilisateur n'a pas relâché le
  /// switch. `null` = suivre l'état serveur.
  bool? _pendingFiltered;

  bool get _isNoisy => isNoisyAt(widget.cadencePerWeek);

  Future<void> _setEnabled(bool enabled) async {
    // Sur une cible bruyante, le mode filtré est l'option par défaut : c'est
    // celle qui tient la promesse « une alerte, pas un robinet ».
    final filtered = enabled && (_pendingFiltered ?? _isNoisy);
    await _push(enabled, filtered);
  }

  Future<void> _setFiltered(bool filtered) async {
    setState(() => _pendingFiltered = filtered);
    await _push(true, filtered);
  }

  Future<void> _push(bool enabled, bool filtered) async {
    setState(() => _busy = true);

    // Poser une cloche sans droit de notifier produirait une alerte muette.
    if (enabled) {
      final settings = ref.read(notificationsSettingsProvider);
      if (!settings.pushEnabled) {
        await showNotificationActivationModal(
          context,
          ref,
          trigger: ActivationTrigger.alert,
        );
        if (!mounted) return;
        if (!ref.read(notificationsSettingsProvider).pushEnabled) {
          setState(() => _busy = false);
          return;
        }
      }
    }

    try {
      final notifier = ref.read(alertsProvider.notifier);
      if (widget.kind == AlertKind.topic) {
        await notifier.setTopicAlert(
          widget.targetId,
          enabled,
          filtered: filtered,
        );
      } else {
        await notifier.setAlert(widget.targetId, enabled, filtered: filtered);
      }
      if (mounted && !enabled) setState(() => _pendingFiltered = null);
    } on AlertCapReachedException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tu as déjà ${e.cap} alertes. Désactives-en une dans Mes alertes.',
          ),
          action: SnackBarAction(
            label: 'Voir',
            onPressed: () => context.pushNamed(RouteNames.alerts),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de régler cette alerte.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final alerts = ref.watch(alertsProvider).valueOrNull;

    AlertItem? active;
    for (final item in alerts?.items ?? const <AlertItem>[]) {
      if (item.sourceId == widget.targetId) active = item;
    }
    final enabled = active != null;
    final filtered = _pendingFiltered ?? active?.filtered ?? _isNoisy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              enabled
                  ? PhosphorIcons.bellRinging(PhosphorIconsStyle.fill)
                  : PhosphorIcons.bell(PhosphorIconsStyle.regular),
              size: 18,
              color: enabled ? colors.primary : colors.textTertiary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Alerte',
                    style: textTheme.labelMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 0,
                    ),
                  ),
                  if (widget.hasProfile) ...[
                    const SizedBox(height: 2),
                    Text(
                      cadencePhraseAt(widget.cadencePerWeek),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        color: colors.textTertiary,
                        fontSize: 11.5,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch.adaptive(
              value: enabled,
              onChanged: _busy ? null : _setEnabled,
            ),
          ],
        ),
        // Le réglage fin n'apparaît qu'une fois la cloche posée : avant, il n'a
        // rien à régler.
        if (enabled) ...[
          const SizedBox(height: 10),
          Divider(height: 1, color: colors.surfaceElevated),
          const SizedBox(height: 10),
          if (widget.hasProfile && _isNoisy) ...[
            Row(
              children: [
                Icon(
                  PhosphorIcons.warning(PhosphorIconsStyle.regular),
                  size: 14,
                  color: colors.textTertiary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    expectedAlertsPhraseAt(widget.cadencePerWeek),
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.textTertiary,
                      fontSize: 11.5,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
          InkWell(
            onTap: _busy ? null : () => _setFiltered(!filtered),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: filtered,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: _busy ? null : (v) => _setFiltered(v ?? false),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Seulement les plus marquantes (1 max par jour)',
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                      fontSize: 11.5,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
