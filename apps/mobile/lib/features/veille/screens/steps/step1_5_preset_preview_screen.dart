import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/theme.dart';
import '../../models/veille_config.dart';
import '../../providers/veille_config_provider.dart';
import '../../providers/veille_presets_provider.dart';
import '../../widgets/veille_widgets.dart';

/// Step 1.5 — Preview pré-set. Affiche le recap (thème + topics + sources
/// curées) et propose 2 actions :
/// - « Personnaliser » : applyPreset puis retour Step 1 pour ajuster
/// - « Continuer avec ce pré-set » : applyPreset puis jump direct au Step 4
///
/// Le state.step reste à 1 sous le capot ; c'est `state.previewPresetId`
/// (non-null) qui force l'orchestrator à rendre cet écran.
class Step15PresetPreviewScreen extends ConsumerWidget {
  final String presetSlug;
  final VoidCallback onClose;

  const Step15PresetPreviewScreen({
    super.key,
    required this.presetSlug,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncPresets = ref.watch(veillePresetsProvider);
    final notifier = ref.read(veilleConfigProvider.notifier);

    return asyncPresets.when(
      loading: () => _Scaffold(
        onClose: onClose,
        onBack: notifier.closePresetPreview,
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => _Scaffold(
        onClose: onClose,
        onBack: notifier.closePresetPreview,
        body: _ErrorState(onBack: notifier.closePresetPreview),
      ),
      data: (presets) {
        final preset = presets.where((p) => p.slug == presetSlug).firstOrNull;
        if (preset == null) {
          return _Scaffold(
            onClose: onClose,
            onBack: notifier.closePresetPreview,
            body: _ErrorState(onBack: notifier.closePresetPreview),
          );
        }
        return _Scaffold(
          onClose: onClose,
          onBack: notifier.closePresetPreview,
          body: _PreviewBody(preset: preset),
          footer: _Footer(
            onCustomize: () =>
                notifier.applyPreset(preset, jumpToStep4: false),
            onContinue: () =>
                notifier.applyPreset(preset, jumpToStep4: true),
          ),
        );
      },
    );
  }
}

class _Scaffold extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback onBack;
  final Widget body;
  final Widget? footer;

  const _Scaffold({
    required this.onClose,
    required this.onBack,
    required this.body,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        VeilleStepHeader(
          step: 1,
          canGoBack: true,
          onBack: onBack,
          onClose: onClose,
        ),
        Expanded(child: body),
        if (footer != null) footer!,
      ],
    );
  }
}

class _PreviewBody extends StatelessWidget {
  final VeillePreset preset;
  const _PreviewBody({required this.preset});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            preset.label,
            style: GoogleFonts.dmSerifDisplay(
              fontSize: 26,
              height: 1.2,
              color: const Color(0xFF2C2A29),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            preset.accroche,
            style: GoogleFonts.dmSans(
              fontSize: 14,
              height: 1.5,
              color: const Color(0xFF5D5B5A),
            ),
          ),
          const SizedBox(height: 20),
          _ChipRow(label: 'Thème', items: [preset.themeLabel]),
          if (preset.topics.isNotEmpty) ...[
            const SizedBox(height: 16),
            _ChipRow(label: 'Sujets', items: preset.topics),
          ],
          const SizedBox(height: 20),
          Text(
            'Sources curées (${preset.sources.length})',
            style: GoogleFonts.courierPrime(
              fontSize: 11,
              letterSpacing: 0.5,
              color: const Color(0xFF8B7E63),
            ),
          ),
          const SizedBox(height: 10),
          if (preset.sources.isEmpty)
            Text(
              'Aucune source curée trouvée pour ce thème.',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: const Color(0xFF8B7E63),
              ),
            )
          else
            _SourcesGrid(sources: preset.sources),
        ],
      ),
    );
  }
}

class _ChipRow extends StatelessWidget {
  final String label;
  final List<String> items;
  const _ChipRow({required this.label, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.courierPrime(
            fontSize: 11,
            letterSpacing: 0.5,
            color: const Color(0xFF8B7E63),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in items)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: FacteurColors.veilleTint,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: FacteurColors.veilleLineSoft,
                  ),
                ),
                child: Text(
                  t,
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF2C2A29),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SourcesGrid extends StatelessWidget {
  final List<VeillePresetSource> sources;
  const _SourcesGrid({required this.sources});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in sources)
          Container(
            width: 96,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: FacteurColors.veilleLineSoft),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (s.logoUrl != null && s.logoUrl!.isNotEmpty)
                  ClipOval(
                    child: Image.network(
                      s.logoUrl!,
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _SourceInitial(name: s.name),
                    ),
                  )
                else
                  _SourceInitial(name: s.name),
                const SizedBox(height: 6),
                Text(
                  s.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    height: 1.2,
                    color: const Color(0xFF2C2A29),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SourceInitial extends StatelessWidget {
  final String name;
  const _SourceInitial({required this.name});

  @override
  Widget build(BuildContext context) {
    final letter = name.isEmpty ? '?' : name[0].toUpperCase();
    return Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(
        color: FacteurColors.veilleTint,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: GoogleFonts.dmSerifDisplay(
          fontSize: 16,
          color: FacteurColors.veille,
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final VoidCallback onCustomize;
  final VoidCallback onContinue;

  const _Footer({required this.onCustomize, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: FacteurColors.veilleLineSoft, width: 1),
        ),
      ),
      child: Column(
        children: [
          VeilleCtaButton(
            label: 'Continuer avec ce pré-set',
            trailingIcon: PhosphorIcons.arrowRight(),
            onPressed: onContinue,
          ),
          const SizedBox(height: 8),
          GhostLink(
            label: 'Personnaliser',
            icon: PhosphorIcons.pencilSimple(),
            onTap: onCustomize,
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onBack;
  const _ErrorState({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Impossible de charger ce pré-set.',
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 14,
              color: const Color(0xFF5D5B5A),
            ),
          ),
          const SizedBox(height: 16),
          GhostLink(
            label: 'Retour aux thèmes',
            icon: PhosphorIcons.arrowLeft(),
            onTap: onBack,
          ),
        ],
      ),
    );
  }
}
