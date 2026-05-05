import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';

import '../../../config/theme.dart';
import '../../sources/widgets/source_detail_modal.dart';
import '../../sources/widgets/source_logo_avatar.dart';
import '../models/veille_config.dart';
import '../models/veille_delivery.dart';
import '../providers/veille_source_examples_provider.dart';

/// Carte source pour le flow Veille — palette sépia, logo réel,
/// CTA "Connecter/Connectée" unifié, badge "Source de confiance" pour les
/// sources déjà suivies par l'user. Tap → SourceDetailModal en consultation.
/// Footer expansible "Voir 2 exemples récents" qui charge à la demande
/// les derniers articles de la source via [veilleSourceExamplesProvider].
class VeilleSourceCard extends ConsumerStatefulWidget {
  final VeilleSource source;
  final bool inVeille;
  final bool isAlreadyFollowed;
  final VoidCallback onToggle;

  const VeilleSourceCard({
    super.key,
    required this.source,
    required this.inVeille,
    required this.isAlreadyFollowed,
    required this.onToggle,
  });

  @override
  ConsumerState<VeilleSourceCard> createState() => _VeilleSourceCardState();
}

class _VeilleSourceCardState extends ConsumerState<VeilleSourceCard> {
  bool _expanded = false;

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    final catalogSource = source.toCatalogSource();
    final showBiasDot =
        source.biasStance != 'unknown' && source.biasStance != 'neutral';
    return Material(
      color: widget.inVeille ? FacteurColors.veilleTint : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => SourceDetailModal(
            source: catalogSource,
            onToggleTrust: () {},
          ),
        ),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.inVeille
                  ? FacteurColors.veille
                  : (widget.isAlreadyFollowed
                      ? FacteurColors.veilleLineSoft
                      : FacteurColors.veilleLine),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SourceLogoAvatar(
                    source: catalogSource,
                    size: 36,
                    radius: 8,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                source.name,
                                style: GoogleFonts.dmSans(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                  color: const Color(0xFF2C2A29),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (showBiasDot) ...[
                              const SizedBox(width: 6),
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: catalogSource.getBiasColor(),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                            if (widget.isAlreadyFollowed) ...[
                              const SizedBox(width: 6),
                              const _SourceDeConfianceBadge(),
                            ],
                          ],
                        ),
                        if (source.editorialMeta != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            source.editorialMeta!,
                            style: GoogleFonts.dmSans(
                              fontSize: 11.5,
                              height: 1.35,
                              color: const Color(0xFF959392),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (source.why != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Icon(
                                  PhosphorIcons.sparkle(),
                                  size: 10,
                                  color: FacteurColors.veille,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  source.why!,
                                  style: GoogleFonts.dmSans(
                                    fontSize: 11.5,
                                    fontStyle: FontStyle.italic,
                                    height: 1.4,
                                    color: FacteurColors.veille,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ConnectButton(
                    active: widget.inVeille,
                    onTap: widget.onToggle,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _ExamplesToggle(
                expanded: _expanded,
                onTap: _toggleExpanded,
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _expanded
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _ExamplesPanel(sourceId: source.id),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExamplesToggle extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;
  const _ExamplesToggle({required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            Icon(
              PhosphorIcons.arrowSquareOut(),
              size: 12,
              color: const Color(0xFF5D5B5A),
            ),
            const SizedBox(width: 6),
            Text(
              'Voir 2 exemples récents',
              style: GoogleFonts.dmSans(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF5D5B5A),
              ),
            ),
            const Spacer(),
            Icon(
              expanded
                  ? PhosphorIcons.caretUp()
                  : PhosphorIcons.caretDown(),
              size: 12,
              color: const Color(0xFF5D5B5A),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExamplesPanel extends ConsumerWidget {
  final String sourceId;
  const _ExamplesPanel({required this.sourceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(veilleSourceExamplesProvider(sourceId));
    return async.when(
      loading: () => const Column(
        children: [
          _ExampleSkeleton(),
          SizedBox(height: 6),
          _ExampleSkeleton(),
        ],
      ),
      error: (_, __) => const _ExamplesEmpty(),
      data: (items) {
        if (items.isEmpty) return const _ExamplesEmpty();
        return Column(
          children: [
            for (int i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              _ExampleRow(item: items[i]),
            ],
          ],
        );
      },
    );
  }
}

class _ExampleRow extends StatelessWidget {
  final VeilleSourceExample item;
  const _ExampleRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final dateLabel = _formatRelative(item.publishedAt);
    return InkWell(
      onTap: () async {
        final uri = Uri.tryParse(item.url);
        if (uri == null) return;
        await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      },
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Icon(
                PhosphorIcons.dotOutline(),
                size: 10,
                color: FacteurColors.veille,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      height: 1.35,
                      color: const Color(0xFF2C2A29),
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (dateLabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      dateLabel,
                      style: GoogleFonts.dmSans(
                        fontSize: 10.5,
                        color: const Color(0xFF959392),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String? _formatRelative(DateTime? date) {
    if (date == null) return null;
    return timeago.format(date, locale: 'fr_short');
  }
}

class _ExampleSkeleton extends StatelessWidget {
  const _ExampleSkeleton();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: FacteurColors.veilleSkel,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

class _ExamplesEmpty extends StatelessWidget {
  const _ExamplesEmpty();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Text(
        "Pas d'exemples récents disponibles.",
        style: GoogleFonts.dmSans(
          fontSize: 11.5,
          fontStyle: FontStyle.italic,
          color: const Color(0xFF959392),
        ),
      ),
    );
  }
}

class _SourceDeConfianceBadge extends StatelessWidget {
  const _SourceDeConfianceBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: FacteurColors.veilleTint,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FacteurColors.veilleLine, width: 1),
      ),
      child: Text(
        'CONFIANCE',
        style: GoogleFonts.courierPrime(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: FacteurColors.veille,
        ),
      ),
    );
  }
}

class _ConnectButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _ConnectButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? FacteurColors.veille : Colors.white,
      borderRadius: BorderRadius.circular(100),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: active ? FacteurColors.veille : const Color(0xFFD2C9BB),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active
                    ? PhosphorIcons.check(PhosphorIconsStyle.bold)
                    : PhosphorIcons.plus(PhosphorIconsStyle.bold),
                size: 12,
                color: active ? Colors.white : FacteurColors.veille,
              ),
              const SizedBox(width: 5),
              Text(
                active ? 'Connectée' : 'Connecter',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : FacteurColors.veille,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
