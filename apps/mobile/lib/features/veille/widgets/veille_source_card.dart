import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../sources/widgets/source_detail_modal.dart';
import '../../sources/widgets/source_logo_avatar.dart';
import '../models/veille_config.dart';

/// Carte source pour le flow Veille — palette sépia, logo réel,
/// CTA "Suivre/Suivi" unifié, tap → SourceDetailModal en consultation.
class VeilleSourceCard extends StatelessWidget {
  final VeilleSource source;
  final bool inVeille;
  final bool isNiche;
  final VoidCallback onToggle;

  const VeilleSourceCard({
    super.key,
    required this.source,
    required this.inVeille,
    required this.isNiche,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final catalogSource = source.toCatalogSource();
    final showBiasDot = source.biasStance != 'unknown' &&
        source.biasStance != 'neutral';
    return Material(
      color: inVeille ? FacteurColors.veilleTint : Colors.white,
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
              color: inVeille
                  ? FacteurColors.veille
                  : (isNiche
                      ? FacteurColors.veilleLine
                      : FacteurColors.veilleLineSoft),
              width: 1.5,
            ),
          ),
          child: Row(
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
                        if (!isNiche) ...[
                          const SizedBox(width: 6),
                          const _SuivieStamp(),
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
                    if (isNiche && source.why != null) ...[
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
              _FollowButton(active: inVeille, onTap: onToggle),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuivieStamp extends StatelessWidget {
  const _SuivieStamp();
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
        'SUIVIE',
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

class _FollowButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _FollowButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? FacteurColors.veille : Colors.white,
      borderRadius: BorderRadius.circular(100),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
                active ? 'Suivie' : 'Suivre',
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
