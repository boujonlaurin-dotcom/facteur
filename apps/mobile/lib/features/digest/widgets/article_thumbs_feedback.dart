import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../core/providers/analytics_provider.dart';
import '../providers/digest_provider.dart';

/// Discreet thumbs-up / thumbs-down feedback row for a digest article.
///
/// - Thumbs up: instant API call, icon filled.
/// - Thumbs down: expands contextual reason chips, auto-submits after 2s idle.
class ArticleThumbsFeedback extends ConsumerStatefulWidget {
  /// The content ID to submit feedback for.
  /// For carousels, the caller should pass the currently-visible article's ID.
  final String contentId;

  const ArticleThumbsFeedback({
    super.key,
    required this.contentId,
  });

  @override
  ConsumerState<ArticleThumbsFeedback> createState() =>
      _ArticleThumbsFeedbackState();
}

class _ArticleThumbsFeedbackState extends ConsumerState<ArticleThumbsFeedback> {
  String? _sentiment; // null | 'positive' | 'negative'
  final Set<String> _selectedReasons = {};
  bool _showChips = false;
  bool _showTextField = false;
  final _commentController = TextEditingController();
  Timer? _autoSubmitTimer;

  static const _reasons = [
    'Sujet pas intéressant',
    'Déjà vu ailleurs',
    'Trop long',
    'Pas pour moi',
    'Autre...',
  ];

  @override
  void dispose() {
    _autoSubmitTimer?.cancel();
    _commentController.dispose();
    super.dispose();
  }

  void _onThumbsUp() {
    if (_sentiment == 'positive') return;
    setState(() {
      _sentiment = 'positive';
      _showChips = false;
      _selectedReasons.clear();
    });
    HapticFeedback.lightImpact();
    _submitFeedback('positive');
  }

  void _onThumbsDown() {
    if (_sentiment == 'negative' && _showChips) return;
    setState(() {
      _sentiment = 'negative';
      _showChips = true;
    });
    HapticFeedback.lightImpact();
  }

  void _onChipToggle(String reason) {
    setState(() {
      if (reason == 'Autre...') {
        _showTextField = !_showTextField;
        if (!_showTextField) {
          _selectedReasons.remove(reason);
          _commentController.clear();
        } else {
          _selectedReasons.add(reason);
        }
      } else {
        if (_selectedReasons.contains(reason)) {
          _selectedReasons.remove(reason);
        } else {
          _selectedReasons.add(reason);
        }
      }
    });
    _resetAutoSubmit();
  }

  void _resetAutoSubmit() {
    _autoSubmitTimer?.cancel();
    _autoSubmitTimer = Timer(const Duration(seconds: 2), () {
      if (_sentiment == 'negative' && _selectedReasons.isNotEmpty) {
        _submitFeedback('negative');
      }
    });
  }

  void _submitFeedback(String sentiment) {
    _autoSubmitTimer?.cancel();
    final reasons = _selectedReasons
        .where((r) => r != 'Autre...')
        .toList();
    final comment =
        _commentController.text.trim().isEmpty ? null : _commentController.text.trim();

    final repo = ref.read(digestRepositoryProvider);
    repo.submitArticleFeedback(
      contentId: widget.contentId,
      sentiment: sentiment,
      reasons: reasons,
      comment: comment,
    );

    // Sprint 2 PR1 — mirror the submission as an analytics event so we can
    // compute the article_feedback rate without reading the article_feedback
    // table directly.
    unawaited(
      ref.read(analyticsServiceProvider).trackArticleFeedbackSubmitted(
        contentId: widget.contentId,
        feedbackType: sentiment == 'positive' ? 'thumbs_up' : 'thumbs_down',
        origin: 'digest',
        extra: {
          if (reasons.isNotEmpty) 'reasons': reasons,
          if (comment != null) 'has_comment': true,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Column(
      children: [
        // Thumbs row — aligned to the right edge of cards
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 12, top: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
            children: [
              _ThumbButton(
                icon: _sentiment == 'positive'
                    ? PhosphorIcons.thumbsUp(PhosphorIconsStyle.fill)
                    : PhosphorIcons.thumbsUp(),
                isActive: _sentiment == 'positive',
                activeColor: colors.primary,
                inactiveColor: colors.textTertiary,
                onTap: _onThumbsUp,
              ),
              const SizedBox(width: 12),
              _ThumbButton(
                icon: _sentiment == 'negative'
                    ? PhosphorIcons.thumbsDown(PhosphorIconsStyle.fill)
                    : PhosphorIcons.thumbsDown(),
                isActive: _sentiment == 'negative',
                activeColor: colors.textTertiary,
                inactiveColor: colors.textTertiary,
                onTap: _onThumbsDown,
              ),
            ],
          ),
          ),
        ),

        // Expandable chips for thumbs-down
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _showChips
              ? Padding(
                  padding: const EdgeInsets.only(right: 12, left: 12, top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        alignment: WrapAlignment.end,
                        children: _reasons.map((reason) {
                          final isSelected = _selectedReasons.contains(reason);
                          return GestureDetector(
                            onTap: () => _onChipToggle(reason),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? colors.primary.withOpacity(0.12)
                                    : Colors.transparent,
                                border: Border.all(
                                  color: isSelected
                                      ? colors.primary.withOpacity(0.4)
                                      : colors.textTertiary
                                          .withOpacity(0.3),
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                reason,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: isSelected
                                      ? colors.primary
                                      : colors.textTertiary,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      if (_showTextField) ...[
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 36,
                          child: TextField(
                            controller: _commentController,
                            maxLength: 100,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Précisez...',
                              hintStyle: TextStyle(
                                fontSize: 12,
                                color: colors.textTertiary,
                              ),
                              counterText: '',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color:
                                      colors.textTertiary.withOpacity(0.3),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color:
                                      colors.textTertiary.withOpacity(0.3),
                                ),
                              ),
                            ),
                            onSubmitted: (_) => _submitFeedback('negative'),
                            onChanged: (_) => _resetAutoSubmit(),
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _ThumbButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  const _ThumbButton({
    required this.icon,
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Icon(
            icon,
            key: ValueKey('$icon-$isActive'),
            size: 16,
            color: isActive ? activeColor : inactiveColor.withOpacity(0.4),
          ),
        ),
      ),
    );
  }
}
