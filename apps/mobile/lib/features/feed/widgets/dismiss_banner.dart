import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../config/topic_labels.dart';
import '../models/content_model.dart';

/// Inline banner shown after swipe-left dismiss.
/// Displays undo + mute source + mute topic options.
/// Auto-resolves after 5 seconds or on option tap.
///
/// Wrap in [AnimatedSize] for smooth height transitions.
class DismissBanner extends StatefulWidget {
  final Content content;
  final VoidCallback onUndo;
  final VoidCallback onMuteSource;
  final void Function(String topic) onMuteTopic;
  final VoidCallback onAutoResolve;

  const DismissBanner({
    super.key,
    required this.content,
    required this.onUndo,
    required this.onMuteSource,
    required this.onMuteTopic,
    required this.onAutoResolve,
  });

  @override
  State<DismissBanner> createState() => _DismissBannerState();
}

class _DismissBannerState extends State<DismissBanner> {
  Timer? _autoResolveTimer;
  bool _isCollapsed = false;
  String? _confirmLabel;

  @override
  void initState() {
    super.initState();
    _autoResolveTimer = Timer(const Duration(seconds: 5), _autoResolve);
  }

  @override
  void dispose() {
    _autoResolveTimer?.cancel();
    super.dispose();
  }

  void _autoResolve() {
    if (!mounted || _isCollapsed) return;
    setState(() => _isCollapsed = true);
    // Delay callback to allow AnimatedSize to animate to zero
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) widget.onAutoResolve();
    });
  }

  void _handleUndo() {
    _autoResolveTimer?.cancel();
    widget.onUndo();
    setState(() => _isCollapsed = true);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) widget.onAutoResolve();
    });
  }

  void _handleMuteSource() {
    _autoResolveTimer?.cancel();
    setState(() => _confirmLabel = '✓');
    widget.onMuteSource();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() => _isCollapsed = true);
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) widget.onAutoResolve();
        });
      }
    });
  }

  void _handleMuteTopic(String topic) {
    _autoResolveTimer?.cancel();
    setState(() => _confirmLabel = '✓');
    widget.onMuteTopic(topic);
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() => _isCollapsed = true);
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) widget.onAutoResolve();
        });
      }
    });
  }

  /// Immediately collapse (called when a new banner takes over).
  void collapse() {
    _autoResolveTimer?.cancel();
    if (mounted && !_isCollapsed) {
      setState(() => _isCollapsed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCollapsed) return const SizedBox.shrink();

    final colors = context.facteurColors;
    final sourceName = widget.content.source.name;
    final firstTopic = widget.content.topics.isNotEmpty
        ? widget.content.topics.first
        : null;
    final topicLabel = firstTopic != null ? getTopicLabel(firstTopic) : null;

    if (_confirmLabel != null) {
      return Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.backgroundSecondary,
          borderRadius: BorderRadius.circular(FacteurRadius.small),
        ),
        child: Text(
          _confirmLabel!,
          style: TextStyle(
            fontSize: 16,
            color: colors.textSecondary,
          ),
        ),
      );
    }

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(FacteurRadius.small),
      ),
      child: Row(
        children: [
          _BannerOption(
            icon: PhosphorIcons.arrowCounterClockwise(PhosphorIconsStyle.bold),
            label: 'Annuler',
            color: colors.textSecondary,
            onTap: _handleUndo,
          ),
          _Dot(color: colors.border),
          Flexible(
            child: _BannerOption(
              label: 'Moins de $sourceName',
              color: colors.textSecondary,
              onTap: _handleMuteSource,
            ),
          ),
          if (topicLabel != null) ...[
            _Dot(color: colors.border),
            Flexible(
              child: _BannerOption(
                label: 'Moins sur "$topicLabel"',
                color: colors.textSecondary,
                onTap: () => _handleMuteTopic(firstTopic!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BannerOption extends StatelessWidget {
  final IconData? icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _BannerOption({
    this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        '·',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
