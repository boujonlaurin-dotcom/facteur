import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/theme.dart';
import '../../../widgets/design/facteur_button.dart';
import '../models/source_model.dart';
import '../providers/sources_providers.dart';
import '../services/premium_session_store.dart';
import 'premium_web_view.dart';
import 'source_logo_avatar.dart';

typedef PremiumWebViewBuilder = Widget Function(
  BuildContext context,
  String url,
  ValueChanged<WebUri?>? onLoadStop, {
  VoidCallback? onPaywallDetected,
  ValueChanged<int?>? onLoadError,
});

/// Nombre de pills affichées dans les WebView steps : login → vérification →
/// terminé. Les écrans intro/succès ne portent pas de pills.
const int _kTotalSteps = 3;

class PremiumSourceConnection extends ConsumerStatefulWidget {
  final Source source;
  final Future<void> Function() onConnected;
  final VoidCallback? onFinished;
  final PremiumWebViewBuilder? webViewBuilder;
  final Future<void> Function(String url)? openExternal;

  /// Connexion à utiliser. Optionnelle : par défaut on lit
  /// `source.premiumConnection`, mais l'appelant peut fournir une connexion
  /// synthétisée (fallback générique) quand la source n'en porte pas.
  final PremiumConnection? connection;

  const PremiumSourceConnection({
    super.key,
    required this.source,
    required this.onConnected,
    this.onFinished,
    this.webViewBuilder,
    this.openExternal,
    this.connection,
  });

  @override
  ConsumerState<PremiumSourceConnection> createState() =>
      _PremiumSourceConnectionState();
}

class _PremiumSourceConnectionState
    extends ConsumerState<PremiumSourceConnection> {
  int _step = 0;
  bool _saving = false;
  String? _error;

  /// Passe à `true` dès que la WebView de login quitte l'URL de connexion
  /// initiale (l'utilisateur a saisi ses identifiants / a été redirigé). Gate le
  /// CTA du step 1 pour ne pas inviter à cliquer avant d'avoir navigué.
  bool _loginNavigated = false;

  /// Étape 2 : la sonde paywall (`PremiumWebView.detectPaywall`) a repéré un
  /// article encore réservé → bannière d'avertissement **non bloquante**.
  bool _paywallWarning = false;

  /// La frame principale n'a pas pu charger (404 / erreur transport) → encart de
  /// guidage en overlay. Reset à chaque transition d'étape.
  bool _loadError = false;

  /// Bumpé au « Réessayer » pour reconstruire la WebView (nouvelle `ValueKey`
  /// → `onWebViewCreated` rejoue le chargement).
  int _webViewEpoch = 0;

  PremiumConnection get _connection =>
      widget.connection ?? widget.source.premiumConnection!;

  /// Heuristique host+path (query/fragment ignorés) : la moindre différence par
  /// rapport à l'URL de login initiale signale que l'utilisateur a avancé.
  void _handleLoginNavigation(WebUri? url) {
    if (_loginNavigated || url == null) return;
    final initial = Uri.tryParse(_connection.loginUrl);
    if (initial == null) return;
    if (url.host != initial.host || url.path != initial.path) {
      setState(() => _loginNavigated = true);
    }
  }

  PremiumSessionStore get _sessionStore =>
      ref.read(premiumSessionStoreProvider);

  Future<void> _openExternal(String url) async {
    if (widget.openExternal != null) {
      await widget.openExternal!(url);
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Entre dans une étape WebView en repartant d'un état propre : les bannières
  /// transitoires (`_paywallWarning`, `_loadError`) sont les seules à reset ici
  /// et au « Réessayer ». Centralisé pour garder l'invariant en un point.
  void _goToStep(int next) {
    setState(() {
      _step = next;
      _paywallWarning = false;
      _loadError = false;
    });
  }

  /// Reconstruit la WebView de l'étape courante (« Réessayer » de l'overlay
  /// d'erreur) en changeant sa `ValueKey`, ce qui rejoue `onWebViewCreated`.
  void _retryWebView() {
    setState(() {
      _loadError = false;
      _webViewEpoch++;
    });
  }

  Future<void> _confirm() async {
    setState(() {
      _saving = true;
      _error = null;
      _paywallWarning = false;
    });
    try {
      // Session validée par l'utilisateur : on capture les cookies du média
      // (store partagé, jamais recréé entre login et test) AVANT de persister
      // l'abonnement côté backend.
      final testUri = WebUri(_connection.testUrl);
      await _sessionStore.captureForSource(widget.source, testUri);
      await widget.onConnected();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _step = 3;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Impossible de connecter cet abonnement.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: _buildAppBar(context, colors),
      body: SafeArea(child: _buildStep(context, colors)),
    );
  }

  /// AppBar unifié : sur les étapes WebView (1 & 2) il fusionne le chrome — titre
  /// « Connecter {source} », barre d'étapes (pills) et raccourci navigateur
  /// externe — pour rendre toute la hauteur à la WebView. Sur intro/succès, seul
  /// le titre (nom de la source), sans pills.
  PreferredSizeWidget _buildAppBar(BuildContext context, FacteurColors colors) {
    final isWebViewStep = _step == 1 || _step == 2;
    final titleText =
        isWebViewStep ? 'Connecter ${widget.source.name}' : widget.source.name;
    return AppBar(
      backgroundColor: colors.backgroundPrimary,
      elevation: 0,
      leading: IconButton(
        icon: Icon(PhosphorIcons.x(), color: colors.textPrimary),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(
        titleText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
      ),
      actions: isWebViewStep ? _appBarStepActions(colors) : null,
    );
  }

  List<Widget> _appBarStepActions(FacteurColors colors) {
    // Le label d'étape ('Connexion'/'Vérification') reste porté par la
    // sémantique des pills (a11y + tests `find.bySemanticsLabel`).
    final stepLabel = _step == 1 ? 'Connexion' : 'Vérification';
    final externalUrl = _step == 1 ? _connection.loginUrl : _connection.testUrl;
    return [
      Center(
        child: Semantics(
          label: stepLabel,
          child: SizedBox(
            width: 72,
            child: _PremiumStepPills(
              totalSteps: _kTotalSteps,
              currentStep: _step,
            ),
          ),
        ),
      ),
      IconButton(
        onPressed: () => _openExternal(externalUrl),
        icon: Icon(PhosphorIcons.arrowSquareOut(), size: 20),
        color: colors.textPrimary,
        tooltip: 'Ouvrir dans le navigateur externe',
      ),
      const SizedBox(width: FacteurSpacing.space2),
    ];
  }

  Widget _buildStep(BuildContext context, FacteurColors colors) {
    switch (_step) {
      case 1:
        return _WebViewStep(
          key: ValueKey('premium-webview-login-$_webViewEpoch'),
          url: _connection.loginUrl,
          source: widget.source,
          sessionStore: _sessionStore,
          actionLabel: 'Continuer',
          webViewBuilder: widget.webViewBuilder,
          showAction: _loginNavigated,
          onLoadStop: _handleLoginNavigation,
          onAction: () => _goToStep(2),
          onOpenExternal: () => _openExternal(_connection.loginUrl),
          loadError: _loadError,
          onLoadError: (_) => setState(() => _loadError = true),
          onRetry: _retryWebView,
        );
      case 2:
        return _WebViewStep(
          key: ValueKey('premium-webview-test-$_webViewEpoch'),
          url: _connection.testUrl,
          source: widget.source,
          sessionStore: _sessionStore,
          actionLabel: 'Je suis connecté(e)',
          webViewBuilder: widget.webViewBuilder,
          instruction:
              'Ouvre un article réservé aux abonnés et vérifie qu’il '
              's’affiche en entier.',
          paywallWarning: _paywallWarning,
          onPaywallDetected: () => setState(() => _paywallWarning = true),
          onAction: _saving ? null : _confirm,
          onOpenExternal: () => _openExternal(_connection.testUrl),
          isLoading: _saving,
          error: _error,
          loadError: _loadError,
          onLoadError: (_) => setState(() => _loadError = true),
          onRetry: _retryWebView,
        );
      case 3:
        return Padding(
          padding: const EdgeInsets.all(FacteurSpacing.space6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                size: 56,
                color: colors.success,
              ),
              const SizedBox(height: FacteurSpacing.space4),
              Text(
                'Abonnement connecté',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: FacteurSpacing.space2),
              Text(
                'Les articles de ${widget.source.name} s\'ouvriront dans Facteur tant que la session du média reste active.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                      height: 1.4,
                    ),
              ),
              const SizedBox(height: FacteurSpacing.space6),
              FacteurButton(
                label: 'Terminer',
                type: FacteurButtonType.primary,
                icon: PhosphorIcons.check(),
                onPressed: () {
                  widget.onFinished?.call();
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      default:
        return Padding(
          padding: const EdgeInsets.all(FacteurSpacing.space6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(child: SourceLogoAvatar(source: widget.source, size: 72)),
              const SizedBox(height: FacteurSpacing.space6),
              Text(
                'Connecter ${widget.source.name}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: FacteurSpacing.space3),
              Text(
                _connection.displayHint ??
                    'Connectez-vous dans la WebView du média, puis confirmez que votre session est bien active.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                      height: 1.45,
                    ),
              ),
              const Spacer(),
              FacteurButton(
                label: 'Commencer',
                type: FacteurButtonType.primary,
                icon: PhosphorIcons.link(),
                onPressed: () => _goToStep(1),
              ),
            ],
          ),
        );
    }
  }
}

class _WebViewStep extends StatelessWidget {
  final String url;
  final Source source;
  final PremiumSessionStore sessionStore;
  final String actionLabel;
  final PremiumWebViewBuilder? webViewBuilder;
  final ValueChanged<WebUri?>? onLoadStop;
  final VoidCallback? onAction;
  final VoidCallback onOpenExternal;

  /// Consigne discrète rendue juste au-dessus de la WebView (étape de
  /// vérification). `null` à l'étape de login → aucune ligne.
  final String? instruction;

  /// Remonté quand la sonde paywall repère un article encore réservé. Non nul
  /// ⇒ la sonde est injectée dans la WebView (étape de vérification).
  final VoidCallback? onPaywallDetected;

  /// Affiche la bannière « article encore réservé » (non bloquante, le CTA reste
  /// actif : on informe, on ne bloque pas).
  final bool paywallWarning;

  /// Échec de chargement de la frame principale (404 / transport) → overlay de
  /// guidage par-dessus la WebView. [onRetry] recharge la page.
  final ValueChanged<int?>? onLoadError;
  final bool loadError;
  final VoidCallback? onRetry;

  /// Masque le CTA principal tant qu'il n'a pas de sens (step login avant que
  /// l'utilisateur ait navigué). Un `SizedBox` prend sa place pour éviter un
  /// saut de layout de la WebView à l'apparition du bouton.
  final bool showAction;
  final bool isLoading;
  final String? error;

  const _WebViewStep({
    super.key,
    required this.url,
    required this.source,
    required this.sessionStore,
    required this.actionLabel,
    required this.onAction,
    required this.onOpenExternal,
    this.webViewBuilder,
    this.onLoadStop,
    this.instruction,
    this.onPaywallDetected,
    this.paywallWarning = false,
    this.onLoadError,
    this.loadError = false,
    this.onRetry,
    this.showAction = true,
    this.isLoading = false,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final webView = webViewBuilder?.call(
          context,
          url,
          onLoadStop,
          onPaywallDetected: onPaywallDetected,
          onLoadError: onLoadError,
        ) ??
        PremiumWebView(
          source: source,
          url: WebUri(url),
          sessionStore: sessionStore,
          enableScrollBridge: false,
          // La sonde n'a de sens qu'à l'étape de vérification, signalée par un
          // callback non nul.
          detectPaywall: onPaywallDetected != null,
          onLoadStop: onLoadStop,
          onPaywallDetected: onPaywallDetected,
          onLoadError: onLoadError,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (instruction != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FacteurSpacing.space4,
              FacteurSpacing.space2,
              FacteurSpacing.space4,
              FacteurSpacing.space2,
            ),
            child: Text(
              instruction!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
            ),
          ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: webView),
              if (loadError)
                Positioned.fill(
                  child: _LoadErrorGuidance(
                    onOpenExternal: onOpenExternal,
                    onRetry: onRetry,
                  ),
                ),
            ],
          ),
        ),
        if (paywallWarning)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(
              'Cet article semble encore réservé. Ta session n’est '
              'peut-être pas active.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.warning),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(
              error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.error),
            ),
          ),
        if (showAction)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FacteurSpacing.space4,
              FacteurSpacing.space2,
              FacteurSpacing.space4,
              FacteurSpacing.space3,
            ),
            child: FacteurButton(
              label: isLoading ? 'Connexion...' : actionLabel,
              type: FacteurButtonType.primary,
              icon: PhosphorIcons.arrowRight(),
              onPressed: onAction,
            ),
          )
        else
          const SizedBox(height: FacteurSpacing.space2),
      ],
    );
  }
}

/// Encart de guidage affiché en overlay quand la page ne se charge pas (404 /
/// erreur transport). Non destructif : la WebView reste dessous, l'utilisateur
/// garde l'échappatoire navigateur et peut réessayer.
class _LoadErrorGuidance extends StatelessWidget {
  final VoidCallback onOpenExternal;
  final VoidCallback? onRetry;

  const _LoadErrorGuidance({required this.onOpenExternal, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Container(
      color: colors.backgroundPrimary,
      padding: const EdgeInsets.all(FacteurSpacing.space6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            PhosphorIcons.warningCircle(),
            size: 48,
            color: colors.textSecondary,
          ),
          const SizedBox(height: FacteurSpacing.space4),
          Text(
            'La page ne s’est pas chargée',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: FacteurSpacing.space2),
          Text(
            'Ouvre le site du média et appuie sur « Se connecter », ou '
            'ouvre-le dans ton navigateur.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                  height: 1.4,
                ),
          ),
          const SizedBox(height: FacteurSpacing.space6),
          FacteurButton(
            label: 'Ouvrir dans le navigateur',
            type: FacteurButtonType.primary,
            icon: PhosphorIcons.arrowSquareOut(),
            onPressed: onOpenExternal,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: FacteurSpacing.space2),
            FacteurButton(
              label: 'Réessayer',
              type: FacteurButtonType.secondary,
              icon: PhosphorIcons.arrowClockwise(),
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}

/// Barre de progression segmentée (pills) des WebView steps. Calquée sur
/// `_StepPills` de `veille_widgets.dart` ; tokens génériques `colors.primary`
/// (actif) / `colors.border` (inactif).
class _PremiumStepPills extends StatelessWidget {
  final int totalSteps;
  final int currentStep; // 1-based

  const _PremiumStepPills({required this.totalSteps, required this.currentStep});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Row(
      children: List.generate(totalSteps, (i) {
        final n = i + 1;
        final active = n <= currentStep;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i == totalSteps - 1 ? 0 : 5),
            height: 4,
            decoration: BoxDecoration(
              color: active ? colors.primary : colors.border,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      }),
    );
  }
}
