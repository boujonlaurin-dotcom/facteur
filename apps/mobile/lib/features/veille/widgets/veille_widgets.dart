import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/veille_config.dart';

/// ===== Step header (back/close + 3 pills) =====
class VeilleStepHeader extends StatelessWidget {
  final int step;
  final bool canGoBack;
  final VoidCallback? onBack;
  final VoidCallback onClose;
  /// Action additionnelle insérée entre les pills et la croix close
  /// (ex: bouton "Passer" sur step2).
  final Widget? trailingAction;
  const VeilleStepHeader({
    super.key,
    required this.step,
    required this.onClose,
    this.canGoBack = true,
    this.onBack,
    this.trailingAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: FacteurColors.veilleLineSoft, width: 1),
        ),
      ),
      child: Row(
        children: [
          if (canGoBack)
            _IconBtn(
              icon: PhosphorIcons.arrowLeft(),
              onTap: onBack ?? () {},
              semantic: 'Retour',
            )
          else
            const SizedBox(width: 36),
          const SizedBox(width: 12),
          Expanded(child: _StepPills(step: step)),
          const SizedBox(width: 12),
          if (trailingAction != null) ...[
            trailingAction!,
            const SizedBox(width: 8),
          ],
          _IconBtn(
            icon: PhosphorIcons.x(),
            onTap: onClose,
            semantic: 'Fermer',
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String semantic;
  const _IconBtn({
    required this.icon,
    required this.onTap,
    required this.semantic,
  });
  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 22, color: const Color(0xFF5D5B5A)),
        tooltip: semantic,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      );
}

class _StepPills extends StatelessWidget {
  final int step;
  const _StepPills({required this.step});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(3, (i) {
        final n = i + 1;
        final active = n <= step;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i == 2 ? 0 : 5),
            height: 4,
            decoration: BoxDecoration(
              color: active ? FacteurColors.veille : FacteurColors.veilleSkel,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      }),
    );
  }
}

/// ===== Eyebrow IA pill =====
class VeilleAiEyebrow extends StatelessWidget {
  final String text;
  const VeilleAiEyebrow(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: FacteurColors.veilleTint,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: FacteurColors.veilleLine),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIcons.sparkle(), size: 11, color: FacteurColors.veille),
          const SizedBox(width: 5),
          Text(
            text.toUpperCase(),
            style: GoogleFonts.courierPrime(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: FacteurColors.veille,
            ),
          ),
        ],
      ),
    );
  }
}

/// ===== H1 du flow =====
class VeilleFlowH1 extends StatelessWidget {
  final String text;
  const VeilleFlowH1(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.fraunces(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        height: 1.2,
        color: const Color(0xFF2C2A29),
      ),
    );
  }
}

/// ===== Theme card (grid 2 col) =====
class ThemeCard extends StatelessWidget {
  final VeilleTheme theme;
  final bool selected;
  final VoidCallback onTap;
  const ThemeCard({
    super.key,
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? FacteurColors.veilleTint : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? FacteurColors.veille
                  : FacteurColors.veilleLineSoft,
              width: 1.5,
            ),
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (theme.emoji != null && theme.emoji!.isNotEmpty)
                    Text(
                      theme.emoji!,
                      style: const TextStyle(fontSize: 20, height: 1),
                    )
                  else
                    Icon(
                      phosphorThemeIcon(theme.iconKey),
                      size: 20,
                      color: FacteurColors.veille,
                    ),
                  const SizedBox(height: 6),
                  Text(
                    theme.label,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                      color: const Color(0xFF2C2A29),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    theme.meta.toUpperCase(),
                    style: GoogleFonts.courierPrime(
                      fontSize: 9,
                      letterSpacing: 0.3,
                      color: const Color(0xFF959392),
                    ),
                  ),
                ],
              ),
              Positioned(
                top: 0,
                right: 0,
                child: _RadioDot(selected: selected),
              ),
              if (theme.hot && !selected)
                Positioned(
                  top: 2,
                  left: 2,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: FacteurColors.veille,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: FacteurColors.veilleTint,
                          blurRadius: 0,
                          spreadRadius: 3,
                        ),
                      ],
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

class _RadioDot extends StatelessWidget {
  final bool selected;
  const _RadioDot({required this.selected});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? FacteurColors.veille : Colors.white,
        border: Border.all(
          color: selected ? FacteurColors.veille : const Color(0xFFD2C9BB),
          width: 1.5,
        ),
      ),
      child: selected
          ? const Icon(Icons.check, size: 11, color: Colors.white)
          : null,
    );
  }
}

/// ===== Primary CTA =====
class VeilleCtaButton extends StatelessWidget {
  final String label;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final VoidCallback? onPressed;
  const VeilleCtaButton({
    super.key,
    required this.label,
    this.leadingIcon,
    this.trailingIcon,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: Material(
        color: disabled
            ? FacteurColors.veille.withValues(alpha: 0.3)
            : FacteurColors.veille,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leadingIcon != null) ...[
                  Icon(leadingIcon, size: 18, color: Colors.white),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                if (trailingIcon != null) ...[
                  const SizedBox(width: 8),
                  Icon(trailingIcon, size: 18, color: Colors.white),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ===== Section toggleable (header tap → expand/collapse animé) =====
class VeilleToggleSection extends StatelessWidget {
  final int index;
  final String title;
  final String? subtitleWhenCollapsed;
  final bool expanded;
  final bool enabled;
  final VoidCallback onToggle;
  final Widget child;

  const VeilleToggleSection({
    super.key,
    required this.index,
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.subtitleWhenCollapsed,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    const disabledColor = Color(0xFFB8B0A0);
    final headerColor =
        enabled ? const Color(0xFF2C2A29) : disabledColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: enabled ? onToggle : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionIndexBadge(index: index, enabled: enabled),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.fraunces(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          height: 1.2,
                          color: headerColor,
                        ),
                      ),
                      if (!expanded &&
                          subtitleWhenCollapsed != null &&
                          subtitleWhenCollapsed!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitleWhenCollapsed!,
                          style: GoogleFonts.courierPrime(
                            fontSize: 11,
                            letterSpacing: 0.4,
                            fontWeight: FontWeight.w700,
                            color: FacteurColors.veille,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    PhosphorIcons.caretDown(),
                    size: 18,
                    color: enabled
                        ? const Color(0xFF5D5B5A)
                        : disabledColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        ClipRect(
          child: AnimatedAlign(
            alignment: Alignment.topCenter,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            heightFactor: expanded ? 1 : 0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 260),
              opacity: expanded ? 1 : 0,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: child,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionIndexBadge extends StatelessWidget {
  final int index;
  final bool enabled;
  const _SectionIndexBadge({required this.index, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: enabled ? FacteurColors.veilleTint : const Color(0xFFEDE7D8),
        border: Border.all(
          color: enabled
              ? FacteurColors.veille.withValues(alpha: 0.4)
              : const Color(0xFFD2C9BB),
          width: 1.2,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        '$index',
        style: GoogleFonts.courierPrime(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: enabled ? FacteurColors.veille : const Color(0xFFB8B0A0),
        ),
      ),
    );
  }
}

/// ===== Ghost link (pour CTA secondaires) =====
class GhostLink extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const GhostLink({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(100),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: const Color(0xFFD2C9BB),
                style: BorderStyle.solid,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: FacteurColors.veille),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF5D5B5A),
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

/// Carte d'« Inspirations » affichée en bas du Step 1 — propose un pré-set
/// V1 (label + accroche). Tap → ouvre l'écran preview Step 1.5.
class PresetCard extends StatelessWidget {
  final String label;
  final String accroche;
  final IconData icon;
  final VoidCallback onTap;

  const PresetCard({
    super.key,
    required this.label,
    required this.accroche,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: FacteurColors.veilleLineSoft,
              width: 1.5,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: FacteurColors.veilleTint,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 18, color: FacteurColors.veille),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                        color: const Color(0xFF2C2A29),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      accroche,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        height: 1.4,
                        color: const Color(0xFF5D5B5A),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                PhosphorIcons.arrowRight(),
                size: 16,
                color: const Color(0xFF8B7E63),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// TextField multiline pour le brief éditorial (max 280 chars). Optionnel,
/// contrôlé par le caller via `value` + `onChanged`.
class VeilleEditorialBriefField extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const VeilleEditorialBriefField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _VeilleStyledTextField(
      value: value,
      onChanged: onChanged,
      maxLength: 280,
      maxLines: 4,
      minLines: 3,
      hintText:
          'Ex : "Plutôt analyses long format que breaking news, avec un '
          'focus sur les implications pour les PME"',
    );
  }
}

class _VeilleStyledTextField extends StatefulWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final int maxLength;
  final int maxLines;
  final int minLines;
  final String hintText;

  const _VeilleStyledTextField({
    required this.value,
    required this.onChanged,
    required this.maxLength,
    required this.maxLines,
    required this.minLines,
    required this.hintText,
  });

  @override
  State<_VeilleStyledTextField> createState() =>
      _VeilleStyledTextFieldState();
}

class _VeilleStyledTextFieldState extends State<_VeilleStyledTextField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value ?? '');
  }

  @override
  void didUpdateWidget(covariant _VeilleStyledTextField old) {
    super.didUpdateWidget(old);
    // Sync only when external value changed AND differs (évite clobber typing).
    if (widget.value != old.value && widget.value != _ctrl.text) {
      _ctrl.text = widget.value ?? '';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFE6E1D6), width: 1),
    );
    final isMultiline = widget.maxLines > 1;
    return TextField(
      controller: _ctrl,
      maxLength: widget.maxLength,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      textCapitalization: TextCapitalization.sentences,
      onChanged: widget.onChanged,
      style: GoogleFonts.dmSans(fontSize: 14, height: isMultiline ? 1.4 : 1.2),
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle: GoogleFonts.dmSans(
          fontSize: 13,
          color: const Color(0xFF8B7E63),
          height: isMultiline ? 1.4 : null,
        ),
        contentPadding: isMultiline
            ? const EdgeInsets.all(12)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: border,
        enabledBorder: border,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: FacteurColors.veille, width: 1.5),
        ),
      ),
    );
  }
}
