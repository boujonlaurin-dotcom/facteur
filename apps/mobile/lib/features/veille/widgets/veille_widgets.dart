import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/veille_config.dart';

/// ===== Step header (back/close + 4 pills) =====
class VeilleStepHeader extends StatelessWidget {
  final int step;
  final bool canGoBack;
  final VoidCallback? onBack;
  final VoidCallback onClose;
  const VeilleStepHeader({
    super.key,
    required this.step,
    required this.onClose,
    this.canGoBack = true,
    this.onBack,
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
      children: List.generate(4, (i) {
        final n = i + 1;
        final active = n <= step;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i == 3 ? 0 : 5),
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

/// ===== Block label =====
class VeilleBlockLabel extends StatelessWidget {
  final String text;
  const VeilleBlockLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: GoogleFonts.dmSans(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF2C2A29),
        ),
      ),
    );
  }
}

class VeilleHelpHint extends StatelessWidget {
  final List<InlineSpan> spans;
  const VeilleHelpHint({super.key, required this.spans});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              PhosphorIcons.sparkle(),
              size: 13,
              color: FacteurColors.veille,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  height: 1.45,
                  color: const Color(0xFF5D5B5A),
                ),
                children: spans,
              ),
            ),
          ),
        ],
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

/// ===== Check row (label + reason + checkbox carré) =====
class CheckRow extends StatelessWidget {
  final String label;
  final String reason;
  final bool selected;
  final VoidCallback onTap;
  const CheckRow({
    super.key,
    required this.label,
    required this.reason,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? FacteurColors.veilleTint : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? FacteurColors.veille
                  : FacteurColors.veilleLineSoft,
              width: 1.5,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 18,
                height: 18,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  color: selected ? FacteurColors.veille : Colors.white,
                  border: Border.all(
                    color: selected
                        ? FacteurColors.veille
                        : const Color(0xFFD2C9BB),
                    width: 1.5,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check, size: 11, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: const Color(0xFF2C2A29),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      reason,
                      style: GoogleFonts.dmSans(
                        fontSize: 11.5,
                        height: 1.4,
                        color: const Color(0xFF959392),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ===== Suggestion row (plus-circle / check-circle) =====
class SuggestionRow extends StatelessWidget {
  final String label;
  final String reason;
  final bool selected;
  final VoidCallback onTap;
  const SuggestionRow({
    super.key,
    required this.label,
    required this.reason,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? FacteurColors.veilleTint : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? FacteurColors.veille
                  : FacteurColors.veilleLineSoft,
              width: 1.5,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? PhosphorIcons.checkCircle(PhosphorIconsStyle.fill)
                    : PhosphorIcons.plusCircle(),
                size: 18,
                color: selected
                    ? FacteurColors.veille
                    : const Color(0xFF959392),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: const Color(0xFF2C2A29),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          PhosphorIcons.sparkle(),
                          size: 10,
                          color: FacteurColors.veille,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            reason,
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ===== Frequency radio =====
class FrequencyRow extends StatelessWidget {
  final VeilleFrequency freq;
  final bool selected;
  final VoidCallback onTap;
  const FrequencyRow({
    super.key,
    required this.freq,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? FacteurColors.veilleTint : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? FacteurColors.veille
                  : FacteurColors.veilleLineSoft,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? FacteurColors.veille
                        : const Color(0xFFD2C9BB),
                    width: 1.5,
                  ),
                ),
                child: selected
                    ? Center(
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: FacteurColors.veille,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Text(
                freq.label,
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF2C2A29),
                ),
              ),
              if (freq.recommended) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: FacteurColors.veille,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    'CONSEILLÉ',
                    style: GoogleFonts.courierPrime(
                      fontSize: 9,
                      letterSpacing: 0.3,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
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

/// ===== Day pill =====
class DayPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const DayPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? FacteurColors.veille : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? FacteurColors.veille
                  : FacteurColors.veilleLineSoft,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label.toUpperCase(),
            style: GoogleFonts.courierPrime(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: selected ? Colors.white : const Color(0xFF5D5B5A),
            ),
          ),
        ),
      ),
    );
  }
}

/// ===== Final recap card (étape 4) =====
class FinalRecapCard extends StatelessWidget {
  final String title;
  final String schedule;
  final int angles;
  final int sources;
  final int topics;
  const FinalRecapCard({
    super.key,
    required this.title,
    required this.schedule,
    required this.angles,
    required this.sources,
    required this.topics,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFBF7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: FacteurColors.veilleLine, width: 1.5),
      ),
      child: Stack(
        children: [
          // Rail dotted vertical
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            child: CustomPaint(
              size: const Size(3, double.infinity),
              painter: _DottedRailPainter(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Stamp(),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: GoogleFonts.fraunces(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    height: 1.2,
                    color: const Color(0xFF2C2A29),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      PhosphorIcons.calendarBlank(),
                      size: 14,
                      color: FacteurColors.veille,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            color: const Color(0xFF5D5B5A),
                          ),
                          children: [
                            const TextSpan(text: 'Tous les '),
                            TextSpan(
                              text: schedule,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF2C2A29),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.only(top: 14),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: FacteurColors.veilleLine,
                        style: BorderStyle.solid,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      _Stat(num: angles, lbl: 'angles\nsuivis'),
                      _Stat(num: sources, lbl: 'sources\nactives'),
                      _Stat(num: topics, lbl: 'sujets\nprécis'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(
          color: FacteurColors.veille.withValues(alpha: 0.5),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            PhosphorIcons.binoculars(),
            size: 11,
            color: FacteurColors.veille,
          ),
          const SizedBox(width: 4),
          Text(
            'MA VEILLE',
            style: GoogleFonts.courierPrime(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: FacteurColors.veille,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final int num;
  final String lbl;
  const _Stat({required this.num, required this.lbl});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$num',
            style: GoogleFonts.fraunces(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              height: 1,
              color: FacteurColors.veille,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            lbl.toUpperCase(),
            style: GoogleFonts.courierPrime(
              fontSize: 9,
              letterSpacing: 0.4,
              height: 1.3,
              color: const Color(0xFF959392),
            ),
          ),
        ],
      ),
    );
  }
}

class _DottedRailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = FacteurColors.veille;
    const step = 6.0;
    for (double y = 0; y < size.height; y += step) {
      canvas.drawCircle(Offset(1.5, y + 1), 1.2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DottedRailPainter oldDelegate) => false;
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

/// ===== Ghost link (Step 2 "Proposer d'autres angles") =====
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
