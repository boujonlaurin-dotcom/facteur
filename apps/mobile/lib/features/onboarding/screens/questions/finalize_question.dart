import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../config/theme.dart';
import '../../../../config/routes.dart';
import '../../../../core/auth/auth_state.dart';
import '../../providers/onboarding_provider.dart';
import '../../onboarding_strings.dart';

/// Écran de finalisation avant l'animation de conclusion.
///
/// Story 31.1 — c'est ici, et seulement ici, que le compte se crée. Le
/// questionnaire s'est déroulé sur une session **anonyme** ; la conversion
/// conserve le même `user.id`, donc thèmes, sous-sujets et sources déjà
/// enregistrés restent attachés. Un utilisateur déjà authentifié qui refait son
/// onboarding ne voit, lui, que le résumé.
class FinalizeQuestion extends ConsumerStatefulWidget {
  const FinalizeQuestion({super.key});

  @override
  ConsumerState<FinalizeQuestion> createState() => _FinalizeQuestionState();
}

class _FinalizeQuestionState extends ConsumerState<FinalizeQuestion> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _validationError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _finalizeAndGoToConclusion() {
    ref.read(onboardingProvider.notifier).finalizeOnboarding();
    context.goNamed(RouteNames.onboardingConclusion);
  }

  Future<void> _createAccount() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (!email.contains('@') || !email.contains('.')) {
      setState(
        () => _validationError = OnboardingStrings.finalizeAccountEmailInvalid,
      );
      return;
    }
    if (password.length < 6) {
      setState(
        () => _validationError =
            OnboardingStrings.finalizeAccountPasswordTooShort,
      );
      return;
    }

    setState(() {
      _validationError = null;
      _submitting = true;
    });

    final converted = await ref
        .read(authStateProvider.notifier)
        .convertAnonymousToAccount(email: email, password: password);

    if (!mounted) return;
    setState(() => _submitting = false);
    if (!converted) return;

    // Le profil est enregistré par l'écran de conclusion, sous le même user id.
    // Le router laisse passer les écrans d'onboarding malgré l'email encore non
    // confirmé, puis renvoie vers /emailConfirmation à la sortie.
    _finalizeAndGoToConclusion();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingProvider);
    final answers = state.answers;
    final colors = context.facteurColors;
    final isAnonymous = ref.watch(authStateProvider).isAnonymous;

    final themesCount = answers.themes?.length ?? 0;
    final sourcesCount = answers.preferredSources?.length ?? 0;
    final articleCount = answers.dailyArticleCount ?? 5;
    final isSerein = (answers.digestMode ?? 'pour_vous') == 'serein';

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: FacteurSpacing.space6,
        right: FacteurSpacing.space6,
        top: FacteurSpacing.space4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + FacteurSpacing.space6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isAnonymous
                ? OnboardingStrings.finalizeAccountTitle
                : OnboardingStrings.finalizeTitle,
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text(
            isAnonymous
                ? OnboardingStrings.finalizeAccountSubtitle
                : OnboardingStrings.finalizeSubtitle,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space6),

          Container(
            padding: const EdgeInsets.all(FacteurSpacing.space4),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(FacteurRadius.medium),
            ),
            child: Column(
              children: [
                _SummaryRow(
                  emoji: '🎨',
                  label: OnboardingStrings.finalizeThemeSummary(themesCount),
                ),
                const SizedBox(height: FacteurSpacing.space3),
                _SummaryRow(
                  emoji: '📰',
                  label: OnboardingStrings.finalizeSourcesSummary(sourcesCount),
                ),
                const SizedBox(height: FacteurSpacing.space3),
                _SummaryRow(
                  emoji: '📋',
                  label: OnboardingStrings.finalizeArticleCountSummary(
                      articleCount),
                ),
                const SizedBox(height: FacteurSpacing.space3),
                _SummaryRow(
                  emoji: isSerein ? '🌿' : '☀️',
                  label: 'Mode : ${isSerein ? "Serein" : "Tout voir"}',
                ),
              ],
            ),
          ),

          const SizedBox(height: FacteurSpacing.space6),

          if (isAnonymous)
            ..._buildAccountForm(context, colors)
          else
            ElevatedButton(
              onPressed: _finalizeAndGoToConclusion,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 24),
              ),
              child: const Text(OnboardingStrings.finalizeButton),
            ),

          const SizedBox(height: FacteurSpacing.space4),
        ],
      ),
    );
  }

  List<Widget> _buildAccountForm(BuildContext context, FacteurColors colors) {
    final authError = ref.watch(authStateProvider).error;
    final message = _validationError ?? authError;

    return [
      TextField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        autofillHints: const [AutofillHints.email],
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          hintText: OnboardingStrings.finalizeAccountEmailHint,
          prefixIcon: Icon(Icons.email_outlined),
        ),
      ),
      const SizedBox(height: FacteurSpacing.space3),
      TextField(
        controller: _passwordController,
        obscureText: _obscurePassword,
        autofillHints: const [AutofillHints.newPassword],
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submitting ? null : _createAccount(),
        decoration: InputDecoration(
          hintText: OnboardingStrings.finalizeAccountPasswordHint,
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
      ),
      if (message != null) ...[
        const SizedBox(height: FacteurSpacing.space3),
        Text(
          message,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: colors.error),
          textAlign: TextAlign.center,
        ),
      ],
      const SizedBox(height: FacteurSpacing.space4),
      ElevatedButton(
        onPressed: _submitting ? null : _createAccount,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 24),
        ),
        child: _submitting
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text(OnboardingStrings.finalizeAccountButton),
      ),
      TextButton(
        onPressed: _submitting ? null : () => context.go(RoutePaths.login),
        child: const Text(OnboardingStrings.finalizeAccountAlreadyHave),
      ),
    ];
  }
}

class _SummaryRow extends StatelessWidget {
  final String emoji;
  final String label;

  const _SummaryRow({required this.emoji, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
        const SizedBox(width: FacteurSpacing.space3),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Icon(Icons.check_circle, color: colors.success, size: 20),
      ],
    );
  }
}
