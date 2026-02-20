import 'dart:async';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/theme.dart';
import '../../../core/api/api_client.dart';
import '../../../core/ui/notification_service.dart';
import '../../feed/repositories/feed_repository.dart';

/// Bottom sheet for creating/editing a note on an article.
/// Auto-saves after a debounce period. Calls [onFirstCharacter] when the note
/// transitions from empty to non-empty (triggers auto-bookmark).
class NoteInputSheet extends StatefulWidget {
  final String contentId;
  final String? initialNoteText;
  final VoidCallback? onFirstCharacter;
  final VoidCallback? onNoteDeleted;
  final ValueChanged<String>? onNoteSaved;

  const NoteInputSheet({
    super.key,
    required this.contentId,
    this.initialNoteText,
    this.onFirstCharacter,
    this.onNoteDeleted,
    this.onNoteSaved,
  });

  /// Show as a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required String contentId,
    String? initialNoteText,
    VoidCallback? onFirstCharacter,
    VoidCallback? onNoteDeleted,
    ValueChanged<String>? onNoteSaved,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NoteInputSheet(
        contentId: contentId,
        initialNoteText: initialNoteText,
        onFirstCharacter: onFirstCharacter,
        onNoteDeleted: onNoteDeleted,
        onNoteSaved: onNoteSaved,
      ),
    );
  }

  @override
  State<NoteInputSheet> createState() => _NoteInputSheetState();
}

class _NoteInputSheetState extends State<NoteInputSheet> {
  late TextEditingController _controller;
  Timer? _debounceTimer;
  bool _isDirty = false;
  bool _isSaving = false;
  bool _hasTriggeredFirstChar = false;
  static const int _maxLength = 1000;
  static const Duration _debounceDuration = Duration(milliseconds: 800);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNoteText ?? '');
    _hasTriggeredFirstChar =
        widget.initialNoteText != null && widget.initialNoteText!.isNotEmpty;
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final text = _controller.text;

    // Trigger auto-bookmark on first character
    if (!_hasTriggeredFirstChar && text.isNotEmpty) {
      _hasTriggeredFirstChar = true;
      widget.onFirstCharacter?.call();
    }

    _isDirty = true;
    _debounceTimer?.cancel();

    if (text.isNotEmpty) {
      _debounceTimer = Timer(_debounceDuration, _saveNote);
    }
  }

  Future<void> _saveNote() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSaving || !mounted) return;

    setState(() => _isSaving = true);
    try {
      final supabase = Supabase.instance.client;
      final apiClient = ApiClient(supabase);
      final repository = FeedRepository(apiClient);
      await repository.upsertNote(widget.contentId, text);
      _isDirty = false;
      if (mounted) widget.onNoteSaved?.call(text);
    } catch (e) {
      if (mounted) {
        NotificationService.showError(
          'Erreur de sauvegarde de la note',
          context: context,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteNote() async {
    setState(() => _isSaving = true);
    try {
      final supabase = Supabase.instance.client;
      final apiClient = ApiClient(supabase);
      final repository = FeedRepository(apiClient);
      await repository.deleteNote(widget.contentId);
      _controller.clear();
      _isDirty = false;
      _hasTriggeredFirstChar = false;
      widget.onNoteDeleted?.call();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        NotificationService.showError(
          'Erreur de suppression',
          context: context,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    // Save on dispose if dirty (protection against accidental close)
    if (_isDirty && _controller.text.trim().isNotEmpty) {
      // Notify parent synchronously before dispose so state is updated
      widget.onNoteSaved?.call(_controller.text.trim());
      _saveNoteSync();
    }
    _controller.dispose();
    super.dispose();
  }

  /// Fire-and-forget save on dispose.
  void _saveNoteSync() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    try {
      final supabase = Supabase.instance.client;
      final apiClient = ApiClient(supabase);
      final repository = FeedRepository(apiClient);
      repository.upsertNote(widget.contentId, text);
    } catch (_) {
      // Best-effort on dispose
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final hasExistingNote =
        widget.initialNoteText != null && widget.initialNoteText!.isNotEmpty;
    final currentLength = _controller.text.length;

    return Container(
      decoration: BoxDecoration(
        color: colors.backgroundPrimary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textSecondary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header: title + delete button
            Row(
              children: [
                Icon(
                  PhosphorIcons.pencilLine(PhosphorIconsStyle.fill),
                  size: 20,
                  color: colors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  hasExistingNote ? 'Modifier la note' : 'Ajouter une note',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                const Spacer(),
                if (_isSaving)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.textSecondary,
                    ),
                  ),
                if (hasExistingNote || _controller.text.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(),
                    onPressed: _isSaving ? null : _deleteNote,
                    icon: Icon(
                      PhosphorIcons.trash(PhosphorIconsStyle.regular),
                      size: 20,
                      color: colors.error,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),

            // Text field
            TextField(
              controller: _controller,
              maxLines: 5,
              minLines: 3,
              maxLength: _maxLength,
              autofocus: !hasExistingNote,
              textCapitalization: TextCapitalization.sentences,
              style: textTheme.bodyMedium?.copyWith(
                color: colors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText:
                    'Qu\'est-ce que j\'en retiens ? Quel point de vue ai-je aujourd\'hui sur le sujet ?',
                hintStyle: textTheme.bodyMedium?.copyWith(
                  color: colors.textTertiary,
                ),
                filled: true,
                fillColor: colors.surfaceElevated,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(16),
                counterText: '',
              ),
            ),
            const SizedBox(height: 8),

            // Character count + auto-save hint
            Row(
              children: [
                Text(
                  'Sauvegarde automatique',
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.textTertiary,
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                Text(
                  '$currentLength/$_maxLength',
                  style: textTheme.bodySmall?.copyWith(
                    color: currentLength > _maxLength * 0.9
                        ? colors.error
                        : colors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
