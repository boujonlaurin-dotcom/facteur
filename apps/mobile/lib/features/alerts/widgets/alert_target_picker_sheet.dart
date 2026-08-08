import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../my_interests/models/user_interests_state.dart';
import '../../my_interests/models/user_sources_state.dart';
import '../../my_interests/providers/user_interests_provider.dart';
import '../../my_interests/providers/user_sources_state_provider.dart';
import '../../sources/models/source_model.dart';
import '../../sources/providers/sources_providers.dart';
import '../../sources/utils/publication_frequency.dart';
import '../../sources/widgets/source_logo_avatar.dart';
import '../models/alert_item.dart';
import '../providers/alerts_provider.dart';
import 'alert_activation_sheet.dart';

/// Une cible sur laquelle une cloche peut se poser : source ou sujet suivi.
@immutable
class _AlertTarget {
  final AlertKind kind;
  final String id;
  final String name;
  final String? logoUrl;

  const _AlertTarget({
    required this.kind,
    required this.id,
    required this.name,
    this.logoUrl,
  });
}

/// Ouvre le sélecteur de cible.
///
/// Rien à renvoyer : la pose passe par `alertsProvider`, donc « Mes alertes »
/// se met à jour toute seule.
Future<void> showAlertTargetPicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _AlertTargetPickerSheet(),
  );
}

/// Sélecteur « Ajouter une alerte » — le geste qui manquait à « Mes alertes ».
///
/// Avant la 30.5, poser une cloche imposait de quitter l'écran, de retrouver la
/// fiche d'une source ou d'un sujet, et d'y actionner le switch. Ici les cibles
/// éligibles (sources suivies + sujets suivis) sont listées sur place.
///
/// **Aucun nouvel appel réseau de listage** : les trois providers existants
/// portent déjà tout ce qu'il faut — `userSourcesStateProvider` (états),
/// `userSourcesProvider` (catalogue : nom + logo) et `userInterestsProvider`
/// (sujets personnalisés). La cadence, elle, n'est résolue qu'au tap, pour la
/// **seule** cible choisie (`sourceProfileProvider` / `topicFrequencyProvider`) :
/// c'est la même source de vérité que la fiche, donc le devis de bruit affiché
/// ne peut pas diverger de celui qui gouverne les envois.
class _AlertTargetPickerSheet extends ConsumerStatefulWidget {
  const _AlertTargetPickerSheet();

  @override
  ConsumerState<_AlertTargetPickerSheet> createState() =>
      _AlertTargetPickerSheetState();
}

class _AlertTargetPickerSheetState
    extends ConsumerState<_AlertTargetPickerSheet> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  /// Identifiant de la cible en cours de pose — une seule à la fois.
  String? _busyId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Cibles éligibles, sources puis sujets, chacune triée par nom.
  List<_AlertTarget> _targets() {
    final sourcesState = ref.watch(userSourcesStateProvider).valueOrNull;
    final catalog =
        ref.watch(userSourcesProvider).valueOrNull ?? const <Source>[];
    final interests = ref.watch(userInterestsProvider).valueOrNull;

    const followed = {InterestState.followed, InterestState.favorite};
    final byId = {for (final s in catalog) s.id: s};

    final sources = <_AlertTarget>[
      for (final s in sourcesState?.sources ?? const <SourceInterest>[])
        if (followed.contains(s.state) && byId[s.sourceId] != null)
          _AlertTarget(
            kind: AlertKind.source,
            id: s.sourceId,
            name: byId[s.sourceId]!.name,
            logoUrl: byId[s.sourceId]!.logoUrl,
          ),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final topics = <_AlertTarget>[
      for (final t in interests?.customTopics ?? const <CustomTopicInterest>[])
        if (followed.contains(t.state))
          _AlertTarget(kind: AlertKind.topic, id: t.id, name: t.topicName),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return [...sources, ...topics];
  }

  /// Cadence de la cible choisie, puis pose de la cloche.
  ///
  /// Le mode filtré suit le même arbitrage que la fiche : sur une cible
  /// bruyante c'est le défaut, c'est lui qui tient la promesse « une alerte,
  /// pas un robinet ».
  Future<void> _pose(_AlertTarget target) async {
    setState(() => _busyId = target.id);

    if (!await ensureAlertPushPermission(context, ref)) {
      if (mounted) setState(() => _busyId = null);
      return;
    }
    if (!mounted) return;

    try {
      final double perWeek;
      if (target.kind == AlertKind.topic) {
        perWeek =
            (await ref.read(topicFrequencyProvider(target.id).future))
                .cadencePerWeek;
      } else {
        final profile = await ref.read(sourceProfileProvider(target.id).future);
        perWeek = cadencePerWeek(profile.articles30d, profile.oldestContentAt);
      }
      final noisy = isNoisyAt(perWeek);

      final notifier = ref.read(alertsProvider.notifier);
      if (target.kind == AlertKind.topic) {
        await notifier.setTopicAlert(target.id, true, filtered: noisy);
      } else {
        await notifier.setAlert(target.id, true, filtered: noisy);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            noisy
                ? 'Alerte posée sur ${target.name}. '
                    'Seulement les plus marquantes, 1 max par jour.'
                : 'Alerte posée sur ${target.name}. '
                    '${cadencePhraseAt(perWeek)}.',
          ),
        ),
      );
    } on AlertCapReachedException catch (e) {
      if (!mounted) return;
      setState(() => _busyId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tu as déjà ${e.cap} alertes. Désactives-en une pour en poser '
            'une autre.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busyId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de poser cette alerte.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final alerts = ref.watch(alertsProvider).valueOrNull;
    final active = {
      for (final i in alerts?.items ?? const <AlertItem>[]) i.sourceId,
    };
    final full = alerts?.isFull ?? false;

    final all = _targets();
    final query = _query.trim().toLowerCase();
    final visible = query.isEmpty
        ? all
        : all.where((t) => t.name.toLowerCase().contains(query)).toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, controller) => Container(
            decoration: BoxDecoration(
              color: colors.backgroundPrimary,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(FacteurRadius.large),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: FacteurSpacing.space2),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    FacteurSpacing.space4,
                    FacteurSpacing.space4,
                    FacteurSpacing.space4,
                    FacteurSpacing.space2,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Poser une alerte',
                        style: textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        full
                            ? 'Plafond atteint. Retire une alerte pour en '
                                'poser une autre.'
                            : 'Choisis une source ou un sujet que tu suis.',
                        style: textTheme.bodySmall?.copyWith(
                          color: full ? colors.error : colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: FacteurSpacing.space3),
                      TextField(
                        controller: _search,
                        onChanged: (v) => setState(() => _query = v),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Rechercher',
                          prefixIcon: Icon(
                            PhosphorIcons.magnifyingGlass(
                              PhosphorIconsStyle.regular,
                            ),
                            size: 18,
                          ),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(FacteurRadius.medium),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: all.isEmpty
                      ? const _NoTargetsView()
                      : ListView.builder(
                          controller: controller,
                          padding: const EdgeInsets.fromLTRB(
                            FacteurSpacing.space4,
                            FacteurSpacing.space2,
                            FacteurSpacing.space4,
                            FacteurSpacing.space6,
                          ),
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final target = visible[index];
                            final already = active.contains(target.id);
                            return _TargetRow(
                              target: target,
                              alreadyActive: already,
                              busy: _busyId == target.id,
                              // Une cible déjà sous cloche, ou le plafond
                              // atteint : la rangée reste lisible mais inerte.
                              onTap: already || full || _busyId != null
                                  ? null
                                  : () => _pose(target),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TargetRow extends StatelessWidget {
  final _AlertTarget target;
  final bool alreadyActive;
  final bool busy;
  final VoidCallback? onTap;

  const _TargetRow({
    required this.target,
    required this.alreadyActive,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final isTopic = target.kind == AlertKind.topic;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(FacteurRadius.medium),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space2,
          vertical: FacteurSpacing.space3,
        ),
        child: Row(
          children: [
            if (isTopic)
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  PhosphorIcons.hash(PhosphorIconsStyle.regular),
                  size: 18,
                  color: colors.primary,
                ),
              )
            else
              SourceLogoAvatar.fromUrl(
                logoUrl: target.logoUrl,
                name: target.name,
                size: 32,
                radius: 8,
              ),
            const SizedBox(width: FacteurSpacing.space3),
            Expanded(
              child: Text(
                target.name,
                style: textTheme.bodyMedium?.copyWith(
                  color: onTap == null && !alreadyActive
                      ? colors.textTertiary
                      : colors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (busy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (alreadyActive)
              Text(
                'Déjà alerté',
                style: textTheme.bodySmall?.copyWith(color: colors.textTertiary),
              )
            else
              Icon(
                PhosphorIcons.bell(PhosphorIconsStyle.regular),
                size: 18,
                color: onTap == null ? colors.textTertiary : colors.primary,
              ),
          ],
        ),
      ),
    );
  }
}

class _NoTargetsView extends StatelessWidget {
  const _NoTargetsView();

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FacteurSpacing.space6),
        child: Text(
          'Tu ne suis encore aucune source ni aucun sujet. '
          'Suis-en un depuis Mes sources ou Mes intérêts, '
          'puis reviens poser ta cloche.',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: colors.textSecondary),
        ),
      ),
    );
  }
}
