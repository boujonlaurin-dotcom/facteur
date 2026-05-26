import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// "Plus d'articles" — opens the dedicated theme page (slide-from-right)
/// instead of paginating in-place. Visual cousin of [PlusDeButton] so the
/// bottom-of-section CTA family stays consistent.
class SeeAllSectionButton extends StatelessWidget {
  final int hiddenCount;
  final VoidCallback onTap;

  const SeeAllSectionButton({
    super.key,
    required this.hiddenCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final label = hiddenCount > 0
        ? 'Lire plus (+$hiddenCount)'
        : 'Lire plus';
    return _ButtonShell(
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.arrow_forward,
            color: colors.textSecondary,
            size: 16,
          ),
        ],
      ),
    );
  }
}

/// "Plus de…" expand/collapse button for a Flux Continu section.
///
/// Soft off-white pill, single neutral colour across all sections — section
/// accents stay confined to the hero banner so the bottom-of-section CTA
/// reads as quiet UI chrome rather than as a second hero element.
class PlusDeButton extends StatelessWidget {
  final String sectionLabel;
  final bool isOpen;
  final int hiddenCount;
  final VoidCallback onTap;

  const PlusDeButton({
    super.key,
    required this.sectionLabel,
    required this.isOpen,
    required this.hiddenCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final label = isOpen
        ? 'Replier $sectionLabel'
        : 'Plus de $sectionLabel${hiddenCount > 0 ? " (+$hiddenCount)" : ""}';
    return _ButtonShell(
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isOpen ? Icons.expand_less : Icons.expand_more,
            color: colors.textSecondary,
            size: 18,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Section suivante ↓" — bottom-of-section CTA that marks the section as
/// consumed for the next session and scrolls smoothly to the next section.
/// When [isMarked] is true, the button flips to a discreet "Passé" state
/// with a coloured circular check and a short scale-pop on the icon
/// (transition false→true only — restoring a marked session at cold start
/// must not replay it). The flip is also applied optimistically the moment
/// the user taps, before the provider propagates [isMarked].
///
/// The non-marked state tints the pill with the next section's hero accent
/// so the CTA preflighs the section the tap will land on. Falls back to
/// the Facteur primary when no next accent is provided (last section).
class NextSectionButton extends StatefulWidget {
  final bool isMarked;
  final Color? nextAccent;
  final VoidCallback? onTap;

  const NextSectionButton({
    super.key,
    required this.isMarked,
    required this.onTap,
    this.nextAccent,
  });

  @override
  State<NextSectionButton> createState() => _NextSectionButtonState();
}

class _NextSectionButtonState extends State<NextSectionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  // Optimistic flip: tapping the button must show the "Lu ✔" state on the
  // very next frame even if the provider takes a tick to propagate isMarked.
  bool _localMarked = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.08), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(covariant NextSectionButton old) {
    super.didUpdateWidget(old);
    if (!old.isMarked && widget.isMarked) {
      if (!_localMarked &&
          _ctrl.status != AnimationStatus.forward &&
          _ctrl.status != AnimationStatus.completed) {
        _ctrl.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (!_localMarked && !widget.isMarked) {
      setState(() => _localMarked = true);
      if (_ctrl.status != AnimationStatus.forward &&
          _ctrl.status != AnimationStatus.completed) {
        _ctrl.forward(from: 0);
      }
    }
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final marked = widget.isMarked || _localMarked;
    final accent = widget.nextAccent ?? colors.primary;
    final label = marked ? 'Passé' : 'Section suivante';
    final foreground =
        marked ? colors.textSecondary : accent;
    final background = marked
        ? colors.textPrimary.withValues(alpha: 0.05)
        : accent.withValues(alpha: 0.08);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: widget.onTap == null ? null : _handleTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const SizedBox(width: 6),
              ScaleTransition(
                scale: _scale,
                child: Icon(
                  marked ? Icons.check_circle : Icons.arrow_downward,
                  color: marked ? colors.success : foreground,
                  size: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared shell for [SeeAllSectionButton] and [PlusDeButton]: same soft
/// off-white Material + InkWell + full-width padded container.
class _ButtonShell extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;

  const _ButtonShell({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Material(
      color: colors.surfaceElevated.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: child,
        ),
      ),
    );
  }
}
