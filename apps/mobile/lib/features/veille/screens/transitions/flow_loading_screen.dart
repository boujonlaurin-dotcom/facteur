import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/theme.dart';
import '../../widgets/halo_loader.dart';
import '../../widgets/veille_widgets.dart';

class FlowLoadingScreen extends StatelessWidget {
  /// `from` = étape qu'on quitte (1, 2 ou 3).
  final int from;
  const FlowLoadingScreen({super.key, required this.from});

  static const _labels = {
    1: _LoadingLabels(
      eyebrow: 'Le facteur écoute…',
      h: 'Analyse de ton thème',
      s:
          'Il croise tes lectures, sous-thèmes et sujets précis pour préparer des suggestions pertinentes.',
      checks: [
        _Check.done('Lecture de ton historique'),
        _Check.done('Cartographie des sous-thèmes'),
        _Check.running('Recherche d\'angles complémentaires…'),
        _Check.todo('Mise en forme des suggestions'),
      ],
    ),
    2: _LoadingLabels(
      eyebrow: 'Le facteur prospecte…',
      h: 'Recherche des sources',
      s:
          'Il identifie sources de confiance déjà suivies, et explore le terrain niche pour couvrir tes angles.',
      checks: [
        _Check.done('Sources suivies récupérées'),
        _Check.done('Cartographie des angles'),
        _Check.running('Sélection des sources niches…'),
        _Check.todo('Évaluation de la couverture'),
      ],
    ),
    3: _LoadingLabels(
      eyebrow: 'Le facteur calibre…',
      h: 'Préparation de ta première veille',
      s:
          'Il assemble la première livraison à partir des articles de la semaine.',
      checks: [
        _Check.done('Sources interrogées (6)'),
        _Check.done('Articles collectés (47)'),
        _Check.running('Détection des angles…'),
        _Check.todo('Justifications & biais'),
      ],
    ),
  };

  @override
  Widget build(BuildContext context) {
    final cur = _labels[from] ?? _labels[1]!;
    return Column(
      children: [
        // Header simplifié (pills uniquement, pas de back/close — le loading
        // bloque la nav le temps de la transition).
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          child: Row(
            children: [
              const SizedBox(width: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: List.generate(4, (i) {
                    final n = i + 1;
                    final done = n <= from;
                    return Expanded(
                      child: Container(
                        margin: EdgeInsets.only(right: i == 3 ? 0 : 5),
                        height: 4,
                        decoration: BoxDecoration(
                          color: done
                              ? FacteurColors.veille
                              : FacteurColors.veilleSkel,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(width: 12),
              const SizedBox(width: 36),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 40, 28, 28),
            child: Column(
              children: [
                const HaloLoader(),
                const SizedBox(height: 24),
                VeilleAiEyebrow(cur.eyebrow),
                const SizedBox(height: 14),
                Text(
                  cur.h,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.fraunces(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    height: 1.25,
                    color: const Color(0xFF2C2A29),
                  ),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 290),
                  child: Text(
                    cur.s,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmSans(
                      fontSize: 13.5,
                      height: 1.5,
                      color: const Color(0xFF5D5B5A),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                _Checklist(items: cur.checks),
                const SizedBox(height: 22),
                _Tip(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LoadingLabels {
  final String eyebrow;
  final String h;
  final String s;
  final List<_Check> checks;
  const _LoadingLabels({
    required this.eyebrow,
    required this.h,
    required this.s,
    required this.checks,
  });
}

enum _CheckState { done, running, todo }

class _Check {
  final _CheckState state;
  final String label;
  const _Check(this.state, this.label);
  const _Check.done(String l) : this(_CheckState.done, l);
  const _Check.running(String l) : this(_CheckState.running, l);
  const _Check.todo(String l) : this(_CheckState.todo, l);
}

class _Checklist extends StatelessWidget {
  final List<_Check> items;
  const _Checklist({required this.items});
  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFDFBF7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: FacteurColors.veilleLineSoft),
        ),
        child: Column(
          children: [
            for (int i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _row(items[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(_Check c) {
    Widget icon;
    Color color;
    FontWeight weight = FontWeight.w400;
    switch (c.state) {
      case _CheckState.done:
        icon = Icon(
          PhosphorIcons.check(),
          size: 14,
          color: FacteurColors.veille,
        );
        color = FacteurColors.veille;
        break;
      case _CheckState.running:
        icon = const MiniSpinner();
        color = const Color(0xFF2C2A29);
        weight = FontWeight.w700;
        break;
      case _CheckState.todo:
        icon = Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: const BoxDecoration(
            color: Color(0xFFD2C9BB),
            shape: BoxShape.circle,
          ),
        );
        color = const Color(0xFF959392).withValues(alpha: 0.7);
        break;
    }
    return Row(
      children: [
        SizedBox(width: 14, child: Center(child: icon)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            c.label,
            style: GoogleFonts.courierPrime(
              fontSize: 11,
              letterSpacing: 0.3,
              fontWeight: weight,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _Tip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFEBE0CC),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                PhosphorIcons.quotes(),
                size: 14,
                color: FacteurColors.veille,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Une bonne veille demande quelques secondes — comme un facteur qui trie le courrier avant de le distribuer.',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  height: 1.45,
                  color: const Color(0xFF5D5B5A),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
