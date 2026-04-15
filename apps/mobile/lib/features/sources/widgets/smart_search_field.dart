import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/theme.dart';

class SmartSearchField extends StatefulWidget {
  final ValueChanged<String> onSearch;
  final bool enabled;

  const SmartSearchField({
    super.key,
    required this.onSearch,
    this.enabled = true,
  });

  @override
  State<SmartSearchField> createState() => _SmartSearchFieldState();
}

class _SmartSearchFieldState extends State<SmartSearchField> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      widget.onSearch(value.trim());
    });
  }

  void _onSubmitted(String value) {
    _debounce?.cancel();
    widget.onSearch(value.trim());
  }

  void _clear() {
    _controller.clear();
    _debounce?.cancel();
    widget.onSearch('');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        hintText: 'Rechercher une source...',
        prefixIcon: Icon(
            PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.regular)),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (_, value, __) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return IconButton(
              icon: Icon(PhosphorIcons.xCircle(PhosphorIconsStyle.fill),
                  color: colors.textTertiary),
              onPressed: _clear,
            );
          },
        ),
      ),
      keyboardType: TextInputType.url,
      autocorrect: false,
      enabled: widget.enabled,
      style: Theme.of(context).textTheme.bodyMedium,
      onChanged: _onChanged,
      onSubmitted: _onSubmitted,
    );
  }
}
