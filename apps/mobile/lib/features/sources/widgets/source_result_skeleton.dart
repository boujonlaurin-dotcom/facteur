import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/theme.dart';

class SourceResultSkeleton extends StatefulWidget {
  final int count;

  const SourceResultSkeleton({super.key, this.count = 3});

  @override
  State<SourceResultSkeleton> createState() => _SourceResultSkeletonState();
}

class _SourceResultSkeletonState extends State<SourceResultSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  int _dotCount = 1;
  late final Timer _dotTimer;

  static const _messages = [
    'Exploration du catalogue',
    'Analyse de votre recherche',
    'Interrogation des plateformes',
    'Scan du web',
    'Recoupement des sources',
    'Préparation des suggestions',
  ];
  int _messageIndex = 0;
  int _tick = 0;

  // Rotation: un dot par 800ms, message change tous les 6 ticks (~4.8s).
  // Assez lent pour que l'utilisateur lise, assez rapide pour rester vivant.
  static const _ticksPerMessage = 6;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.3, end: 0.7).animate(_controller);

    _dotTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      if (!mounted) return;
      setState(() {
        _dotCount = (_dotCount % 3) + 1;
        _tick += 1;
        if (_tick % _ticksPerMessage == 0) {
          _messageIndex = (_messageIndex + 1) % _messages.length;
        }
      });
    });
  }

  @override
  void dispose() {
    _dotTimer.cancel();
    _controller.dispose();
    super.dispose();
  }

  String get _dots => '.' * _dotCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              Icon(
                PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.regular),
                size: 16,
                color: colors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '${_messages[_messageIndex]}$_dots',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
              ),
            ],
          ),
        ),
        AnimatedBuilder(
          animation: _opacity,
          builder: (context, _) {
            return Column(
              children: List.generate(
                  widget.count, (_) => _buildSkeletonCard(context)),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSkeletonCard(BuildContext context) {
    final colors = context.facteurColors;
    final shimmerColor =
        colors.textTertiary.withOpacity(_opacity.value * 0.3);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: shimmerColor,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 14,
                      width: 140,
                      decoration: BoxDecoration(
                        color: shimmerColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 10,
                      width: 80,
                      decoration: BoxDecoration(
                        color: shimmerColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 10,
            width: double.infinity,
            decoration: BoxDecoration(
              color: shimmerColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 10,
            width: 200,
            decoration: BoxDecoration(
              color: shimmerColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: shimmerColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: shimmerColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
