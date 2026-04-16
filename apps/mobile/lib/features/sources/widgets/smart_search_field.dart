import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/theme.dart';

/// Champ de recherche de sources.
///
/// Le déclenchement de la recherche est explicite : `onSubmit` est appelé
/// uniquement quand l'utilisateur valide (touche "Rechercher" du clavier)
/// ou quand le parent le déclenche via le bouton "Rechercher" attenant.
/// Aucun debounce sur les keystrokes — chaque appel coûte du quota
/// Brave/Mistral côté backend.
class SmartSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final VoidCallback onClear;
  final VoidCallback? onSearch;
  final bool enabled;

  const SmartSearchField({
    super.key,
    required this.controller,
    required this.onSubmit,
    required this.onClear,
    this.onSearch,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: 'Rechercher une source...',
        prefixIcon: Icon(
            PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.regular)),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, value, __) {
            final hasText = value.text.isNotEmpty;
            if (hasText) {
              return IconButton(
                icon: Icon(PhosphorIcons.xCircle(PhosphorIconsStyle.fill),
                    color: colors.textTertiary),
                onPressed: onClear,
              );
            }
            if (onSearch != null) {
              return IconButton(
                icon: Icon(
                    PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.bold),
                    color: colors.primary),
                onPressed: onSearch,
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.search,
      autocorrect: false,
      enabled: enabled,
      style: Theme.of(context).textTheme.bodyMedium,
      onSubmitted: (value) => onSubmit(value.trim()),
    );
  }
}
