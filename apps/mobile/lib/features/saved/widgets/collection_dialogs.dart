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
}) async {
  final colors = context.facteurColors;
  final controller = TextEditingController(text: initialValue);
  final formKey = GlobalKey<FormState>();

  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: colors.backgroundSecondary,
      title: Text(
        title,
        style: TextStyle(color: colors.textPrimary, fontSize: 17),
      ),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
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
          onFieldSubmitted: (value) {
            if (formKey.currentState!.validate()) {
              Navigator.pop(context, value.trim());
            }
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Annuler',
              style: TextStyle(color: colors.textSecondary)),
        ),
        TextButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.pop(context, controller.text.trim());
            }
          },
          child: Text(confirmLabel,
              style: TextStyle(color: colors.primary)),
        ),
      ],
    ),
  );

  controller.dispose();
  return result;
}
