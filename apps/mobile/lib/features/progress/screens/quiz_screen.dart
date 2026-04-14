import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:confetti/confetti.dart';

import '../../../config/theme.dart';
import '../../../widgets/design/facteur_button.dart';
import '../repositories/progress_repository.dart';
import '../models/progress_models.dart';
import '../../../core/ui/notification_service.dart';

class QuizScreen extends ConsumerStatefulWidget {
  final String topic;

  const QuizScreen({super.key, required this.topic});

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  // State
  bool _isLoading = true;
  String? _error;
  TopicQuiz? _quiz;

  // Selection
  int? _selectedOptionIndex;
  bool _isSubmitting = false;
  QuizResultResponse? _result;
  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 3));
    _fetchQuiz();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _fetchQuiz() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final quiz =
          await ref.read(progressRepositoryProvider).getQuiz(widget.topic);
      if (mounted) {
        setState(() {
          _quiz = quiz;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _submitAnswer() async {
    if (_selectedOptionIndex == null || _quiz == null) return;

    setState(() => _isSubmitting = true);

    try {
      final result = await ref
          .read(progressRepositoryProvider)
          .submitQuiz(_quiz!.id, _selectedOptionIndex!);

      if (mounted) {
        setState(() {
          _result = result;
          _isSubmitting = false;
        });

        if (result.isCorrect) {
          _confettiController.play();
        }

        // Refresh progress list in background
        ref.invalidate(myProgressProvider);
      }
    } catch (e) {
      if (mounted) {
        NotificationService.showError('Erreur: $e', context: context);
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        title: Text(widget.topic),
        centerTitle: true,
        backgroundColor: colors.backgroundPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: _buildBody(colors, textTheme),
      ),
      bottomNavigationBar: _result == null && _quiz != null
          ? Padding(
              padding: const EdgeInsets.all(FacteurSpacing.space4),
              child: FacteurButton(
                label: 'Valider',
                onPressed: _selectedOptionIndex != null && !_isSubmitting
                    ? _submitAnswer
                    : null,
                isLoading: _isSubmitting,
              ),
            )
          : null,
    );
  }

  Widget _buildBody(FacteurColors colors, TextTheme textTheme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Impossible de charger le quiz', style: textTheme.titleMedium),
            TextButton(onPressed: _fetchQuiz, child: const Text('Réessayer')),
          ],
        ),
      );
    }

    if (_quiz == null) return const SizedBox.shrink();

    // Show Result View if answered
    if (_result != null) {
      return _buildResultView(colors, textTheme);
    }

    // Question View
    return SingleChildScrollView(
      padding: const EdgeInsets.all(FacteurSpacing.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Progress/Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PhosphorIcons.lightning(PhosphorIconsStyle.fill),
                    size: 16, color: colors.primary),
                const SizedBox(width: 8),
                Text('Quiz Rapide',
                    style: textTheme.labelMedium?.copyWith(
                        color: colors.primary, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Text(
            _quiz!.question,
            style:
                textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 32),

          // Options
          ...List.generate(_quiz!.options.length, (index) {
            final isSelected = _selectedOptionIndex == index;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: () => setState(() => _selectedOptionIndex = index),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colors.primary.withOpacity(0.1)
                        : colors.surface,
                    border: Border.all(
                      color:
                          isSelected ? colors.primary : colors.surfaceElevated,
                      width: isSelected ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? colors.primary
                                : colors.textTertiary,
                            width: 2,
                          ),
                          color: isSelected ? colors.primary : null,
                        ),
                        child: isSelected
                            ? const Icon(Icons.check,
                                size: 16, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          _quiz!.options[index],
                          style: textTheme.bodyLarge?.copyWith(
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildResultView(FacteurColors colors, TextTheme textTheme) {
    final isCorrect = _result!.isCorrect;

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCorrect
                      ? colors.success.withOpacity(0.1)
                      : colors.error.withOpacity(0.1),
                ),
                child: Icon(
                  isCorrect
                      ? PhosphorIcons.check(PhosphorIconsStyle.bold)
                      : PhosphorIcons.x(PhosphorIconsStyle.bold),
                  size: 48,
                  color: isCorrect ? colors.success : colors.error,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                isCorrect ? 'Bonne réponse !' : 'Oups...',
                style: textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _result!.message,
                textAlign: TextAlign.center,
                style: textTheme.bodyLarge,
              ),
              if (isCorrect) ...[
                const SizedBox(height: 24),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: colors.surfaceElevated,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIcons.trophy(PhosphorIconsStyle.fill),
                          color: Colors.amber),
                      const SizedBox(width: 12),
                      Text(
                        '+${_result!.pointsEarned} pts',
                        style: textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 48),
              FacteurButton(
                label: 'Continuer',
                onPressed: () => context.pop(),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confettiController,
            blastDirectionality: BlastDirectionality.explosive,
            shouldLoop: false,
            colors: const [
              Colors.green,
              Colors.blue,
              Colors.pink,
              Colors.orange,
              Colors.purple
            ],
          ),
        ),
      ],
    );
  }
}
