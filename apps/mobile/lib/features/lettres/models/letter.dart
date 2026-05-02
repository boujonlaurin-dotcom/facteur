import 'package:flutter/foundation.dart';

enum LetterStatus { upcoming, active, archived }

LetterStatus _letterStatusFromJson(String raw) {
  switch (raw) {
    case 'upcoming':
      return LetterStatus.upcoming;
    case 'active':
      return LetterStatus.active;
    case 'archived':
      return LetterStatus.archived;
    default:
      return LetterStatus.upcoming;
  }
}

enum LetterActionStatus { todo, active, done }

@immutable
class LetterAction {
  final String id;
  final String label;
  final String help;
  final LetterActionStatus status;

  const LetterAction({
    required this.id,
    required this.label,
    required this.help,
    required this.status,
  });
}

@immutable
class Letter {
  final String id;
  final String letterNum;
  final String title;
  final String message;
  final String signature;
  final LetterStatus status;
  final List<LetterAction> actions;
  final List<String> completedActions;
  final double progress;
  final DateTime? startedAt;
  final DateTime? archivedAt;

  const Letter({
    required this.id,
    required this.letterNum,
    required this.title,
    required this.message,
    required this.signature,
    required this.status,
    required this.actions,
    required this.completedActions,
    required this.progress,
    required this.startedAt,
    required this.archivedAt,
  });

  factory Letter.fromJson(Map<String, dynamic> json) {
    final status = _letterStatusFromJson(json['status'] as String);
    final completed = (json['completed_actions'] as List<dynamic>? ?? [])
        .whereType<String>()
        .toList();
    final completedSet = completed.toSet();

    final rawActions = (json['actions'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final isActive = status == LetterStatus.active;

    final actions = <LetterAction>[];
    var firstUncompleted = true;
    for (final raw in rawActions) {
      final id = raw['id'] as String;
      final isDone = completedSet.contains(id);
      LetterActionStatus actionStatus;
      if (isDone) {
        actionStatus = LetterActionStatus.done;
      } else if (isActive && firstUncompleted) {
        actionStatus = LetterActionStatus.active;
        firstUncompleted = false;
      } else {
        actionStatus = LetterActionStatus.todo;
        firstUncompleted = false;
      }
      actions.add(LetterAction(
        id: id,
        label: raw['label'] as String? ?? '',
        help: raw['help'] as String? ?? '',
        status: actionStatus,
      ));
    }

    DateTime? parseTs(Object? v) {
      if (v is! String || v.isEmpty) return null;
      return DateTime.tryParse(v)?.toUtc();
    }

    return Letter(
      id: json['id'] as String,
      letterNum: json['num'] as String? ?? '',
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      signature: json['signature'] as String? ?? '',
      status: status,
      actions: actions,
      completedActions: completed,
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      startedAt: parseTs(json['started_at']),
      archivedAt: parseTs(json['archived_at']),
    );
  }
}
