import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../providers/veille_config_provider.dart';
import 'steps/step1_theme_screen.dart';
import 'steps/step2_suggestions_screen.dart';
import 'steps/step3_sources_screen.dart';
import 'steps/step4_frequency_screen.dart';
import 'transitions/flow_loading_screen.dart';

/// Host du flow de configuration de la veille.
/// Switch entre les 4 écrans + écran de loading IA entre étapes.
class VeilleConfigScreen extends ConsumerWidget {
  const VeilleConfigScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(veilleConfigProvider);

    void close() {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/feed');
      }
    }

    Future<void> handleSubmit() async {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Veille configurée — première livraison bientôt en preview.',
          ),
        ),
      );
      close();
    }

    Widget body;
    if (state.isLoading) {
      body = FlowLoadingScreen(from: state.loadingFrom!);
    } else {
      switch (state.step) {
        case 1:
          body = Step1ThemeScreen(onClose: close);
          break;
        case 2:
          body = Step2SuggestionsScreen(onClose: close);
          break;
        case 3:
          body = Step3SourcesScreen(onClose: close);
          break;
        case 4:
        default:
          body = Step4FrequencyScreen(
            onClose: close,
            onSubmit: handleSubmit,
          );
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF2E8D5),
      body: SafeArea(
        bottom: true,
        child: AnimatedSwitcher(
          duration: FacteurDurations.medium,
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: KeyedSubtree(
            key: ValueKey(
              state.isLoading ? 'load-${state.loadingFrom}' : 'step-${state.step}',
            ),
            child: body,
          ),
        ),
      ),
    );
  }
}
