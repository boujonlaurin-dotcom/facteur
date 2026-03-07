import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// Compact floating pill showing a mini proportional bias distribution bar.
/// Appears on the detail screen to indicate available perspectives.
class PerspectivesPill extends StatefulWidget {
  final Map<String, int> biasDistribution;
  final bool isLoading;
  final bool isEmpty;
  final VoidCallback onTap;

  const PerspectivesPill({
    super.key,
    required this.biasDistribution,
    required this.isLoading,
    required this.isEmpty,
    required this.onTap,
  });

  @override
  State<PerspectivesPill> createState() => _PerspectivesPillState();
}

class _PerspectivesPillState extends State<PerspectivesPill>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    ));

    // Delay entrance animation by 1s
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) _animController.forward();
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: widget.isEmpty
                  ? colors.surface.withValues(alpha: 0.7)
                  : colors.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: widget.isLoading
                ? _buildLoading(colors)
                : widget.isEmpty
                    ? _buildEmpty(colors)
                    : _buildMiniBiasBar(colors),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading(FacteurColors colors) {
    return SizedBox(
      width: 56,
      height: 12,
      child: LinearProgressIndicator(
        borderRadius: BorderRadius.circular(6),
        backgroundColor: colors.textTertiary.withValues(alpha: 0.1),
        valueColor:
            AlwaysStoppedAnimation<Color>(colors.primary.withValues(alpha: 0.4)),
      ),
    );
  }

  Widget _buildEmpty(FacteurColors colors) {
    return Text(
      '—',
      style: TextStyle(
        fontSize: 12,
        color: colors.textTertiary,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildMiniBiasBar(FacteurColors colors) {
    // 3 merged segments: Gauche (left+center-left), Centre, Droite (center-right+right)
    final dist = widget.biasDistribution;
    final segments = [
      ((dist['left'] ?? 0) + (dist['center-left'] ?? 0), colors.biasLeft),
      (dist['center'] ?? 0, colors.biasCenter),
      ((dist['center-right'] ?? 0) + (dist['right'] ?? 0), colors.biasRight),
    ];

    final total = segments.fold<int>(0, (sum, s) => sum + s.$1);

    if (total == 0) {
      return _buildEmpty(colors);
    }

    return SizedBox(
      width: 56,
      height: 10,
      child: Row(
        children: segments.map((seg) {
          final fraction =
              seg.$1 > 0 ? (seg.$1 / total).clamp(0.15, 1.0) : 0.0;
          if (fraction == 0) return const SizedBox.shrink();

          return Expanded(
            flex: (fraction * 100).round().clamp(15, 100),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 0.5),
              decoration: BoxDecoration(
                color: seg.$2,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
