import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../../config/constants.dart';
import '../../../core/auth/auth_state.dart';
import '../../../shared/widgets/buttons/primary_button.dart';

import '../../../widgets/design/facteur_logo.dart';
import '../../../core/ui/notification_service.dart';

/// Écran de connexion / inscription
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  bool _isSignUp = false;
  bool _obscurePassword = true;

  bool _rememberMe = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _isSignUp = !_isSignUp;
    });
  }

  Future<void> _submitEmail() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || (password.isEmpty && !_isSignUp)) {
      return;
    }

    final authNotifier = ref.read(authStateProvider.notifier);

    if (_isSignUp) {
      final firstName = _firstNameController.text.trim();
      final lastName = _lastNameController.text.trim();

      if (firstName.isEmpty || lastName.isEmpty) {
        NotificationService.showError('Saisis ton nom et prénom');
        return;
      }

      await authNotifier.signUpWithEmail(
        email: email,
        password: password,
        firstName: firstName,
        lastName: lastName,
      );
    } else {
      await authNotifier.signInWithEmail(email, password,
          rememberMe: _rememberMe);
    }

    // Only trigger the "Save password?" OS prompt if auth succeeded.
    // On failure, errors are caught inside authNotifier (no rethrow),
    // so we check state.error to avoid saving wrong credentials.
    final authState = ref.read(authStateProvider);
    if (authState.error == null && !authState.isLoading) {
      TextInput.finishAutofillContext();
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    final controller = TextEditingController(text: email);

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mot de passe oublié ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Saisis ton adresse email pour recevoir un lien de réinitialisation.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                hintText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              final resetEmail = controller.text.trim();
              if (resetEmail.isEmpty) return;

              Navigator.pop(context);

              try {
                await ref
                    .read(authStateProvider.notifier)
                    .sendPasswordResetEmail(resetEmail);
                if (mounted) {
                  NotificationService.showSuccess(
                      'Email de réinitialisation envoyé !');
                }
              } catch (e) {
                if (mounted) {
                  NotificationService.showError(e.toString());
                }
              }
            },
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
  }

  Future<void> _resendEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      if (mounted) {
        NotificationService.showError('Saisis ton email pour confirmer');
      }
      return;
    }

    try {
      await ref.read(authStateProvider.notifier).resendConfirmationEmail(email);
      if (mounted) {
        NotificationService.showSuccess('Email de confirmation renvoyé !');
      }
    } catch (e) {
      if (mounted) {
        // L'erreur est déjà dans le state affiché
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final colors = context.facteurColors;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: AutofillGroup(
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),

                // Logo / Titre
                const Center(child: FacteurLogo(size: 48)),

                const SizedBox(height: 32),

                if (_isSignUp) ...[
                  Text(
                    'Créer un compte',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Rejoins la communauté Facteur',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ] else ...[
                  Text(
                    'Content de vous (re)voir.',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'L\'information de qualité, triée pour vous.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],

                const SizedBox(height: 40),

                if (_isSignUp) ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _firstNameController,
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.givenName],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: 'Prénom',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _lastNameController,
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.familyName],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: 'Nom',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // Formulaire
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),

                const SizedBox(height: 16),

                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  autofillHints: [
                    _isSignUp
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submitEmail(),
                  decoration: InputDecoration(
                    hintText: 'Mot de passe',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                ),

                if (!_isSignUp) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _forgotPassword,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(50, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Mot de passe oublié ?',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                              decoration: TextDecoration.underline,
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: _rememberMe,
                    onChanged: (value) {
                      setState(() {
                        _rememberMe = value ?? true;
                      });
                    },
                    title: const Text(
                      'Rester connecté',
                      style: TextStyle(fontSize: 14),
                    ),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    activeColor: colors.primary,
                  ),
                ],

                // Erreur
                if (authState.error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: colors.error,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                authState.error!,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: colors.error),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Bouton Renvoyer Email si erreur de confirmation
                  if (authState.error!.contains('confirmer votre email')) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _resendEmail,
                        icon: const Icon(Icons.send_outlined, size: 16),
                        label: const Text('Renvoyer l\'email de confirmation'),
                        style: TextButton.styleFrom(
                          foregroundColor: colors.primary,
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ],

                const SizedBox(height: 24),

                // Bouton principal
                PrimaryButton(
                  label: _isSignUp ? 'Créer un compte' : 'Se connecter',
                  onPressed: _submitEmail,
                  isLoading: authState.isLoading,
                ),

                const SizedBox(height: 16),

                // Séparateur "ou"
                Row(
                  children: [
                    Expanded(
                      child: Divider(
                        color: colors.textTertiary.withValues(alpha: 0.3),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'ou',
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: colors.textTertiary,
                                ),
                      ),
                    ),
                    Expanded(
                      child: Divider(
                        color: colors.textTertiary.withValues(alpha: 0.3),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Bouton Google Sign-In
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: authState.isLoading
                        ? null
                        : () {
                            ref
                                .read(authStateProvider.notifier)
                                .signInWithGoogle();
                          },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: colors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      backgroundColor: colors.surfacePaper,
                    ),
                    icon: Image.asset(
                      'assets/icons/google_g_logo.png',
                      height: 20,
                      width: 20,
                    ),
                    label: Text(
                      _isSignUp
                          ? 'S\'inscrire avec Google'
                          : 'Se connecter avec Google',
                      style:
                          Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: colors.textPrimary,
                              ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Toggle inscription/connexion amélioré
                if (!_isSignUp) ...[
                  // Mode login : afficher un encart attractif pour l'inscription
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: colors.primary.withValues(alpha: 0.3),
                      ),
                      borderRadius: BorderRadius.circular(12),
                      color: colors.primary.withValues(alpha: 0.05),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Pas encore de compte ?',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: colors.textSecondary,
                                  ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _toggleMode,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: colors.primary,
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 24,
                            ),
                          ),
                          child: Text(
                            'Créer un compte gratuitement',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: colors.primary,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // Mode signup : simple lien pour revenir au login
                  Center(
                    child: TextButton(
                      onPressed: _toggleMode,
                      child: Text(
                        'Déjà un compte ? Se connecter',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colors.textSecondary,
                              decoration: TextDecoration.underline,
                            ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // CGV
                Text(
                  'En continuant, tu acceptes nos Conditions d\'utilisation et notre Politique de confidentialité.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textTertiary,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }
}
