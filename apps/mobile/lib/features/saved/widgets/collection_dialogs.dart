import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// Dialogue de création d'une collection.
Future<String?> showCreateCollectionDialog(BuildContext context) {
  return _showNameDialog(
    context,
    title: 'Nouvelle collection',
    hint: 'Nom de la collection',
    confirmLabel: 'Créer',
  );
}

/// Dialogue de renommage d'une collection.
Future<String?> showRenameCollectionDialog(
    BuildContext context, String currentName) {
  return _showNameDialog(
    context,
    title: 'Renommer',
    hint: 'Nom de la collection',
    initialValue: currentName,
    confirmLabel: 'Renommer',
  );
}

/// Dialogue de confirmation de suppression.
Future<bool> showDeleteCollectionConfirmation(
    BuildContext context, String collectionName) async {
  final colors = context.facteurColors;

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: colors.backgroundSecondary,
      title: Text(
        'Supprimer "$collectionName" ?',
        style: TextStyle(color: colors.textPrimary, fontSize: 17),
      ),
      content: Text(
        'Les articles ne seront pas retirés de vos sauvegardes.',
        style: TextStyle(color: colors.textSecondary, fontSize: 14),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Annuler',
              style: TextStyle(color: colors.textSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('Supprimer', style: TextStyle(color: colors.error)),
        ),
      ],
    ),
  );

  return result ?? false;
}

Future<String?> _showNameDialog(
  BuildContext context, {
  required String title,
  required String hint,
  required String confirmLabel,
  String? initialValue,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _NameDialog(
      title: title,
      hint: hint,
      confirmLabel: confirmLabel,
      initialValue: initialValue,
    ),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.hint,
    required this.confirmLabel,
    this.initialValue,
  });

  final String title;
  final String hint;
  final String confirmLabel;
  final String? initialValue;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.pop(context, _controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return AlertDialog(
      backgroundColor: colors.backgroundSecondary,
      title: Text(
        widget.title,
        style: TextStyle(color: colors.textPrimary, fontSize: 17),
      ),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          maxLength: 100,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: TextStyle(color: colors.textTertiary),
            counterStyle: TextStyle(color: colors.textTertiary),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: colors.primary),
            ),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Le nom ne peut pas être vide';
            }
            return null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Annuler',
              style: TextStyle(color: colors.textSecondary)),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(widget.confirmLabel,
              style: TextStyle(color: colors.primary)),
        ),
      ],
    );
  }
}
