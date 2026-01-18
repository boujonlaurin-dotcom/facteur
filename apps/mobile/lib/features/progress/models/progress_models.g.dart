// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'progress_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$UserTopicProgressImpl _$$UserTopicProgressImplFromJson(
        Map<String, dynamic> json) =>
    _$UserTopicProgressImpl(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      topic: json['topic'] as String,
      level: (json['level'] as num).toInt(),
      points: (json['points'] as num).toInt(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$$UserTopicProgressImplToJson(
        _$UserTopicProgressImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'user_id': instance.userId,
      'topic': instance.topic,
      'level': instance.level,
      'points': instance.points,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
    };

_$TopicQuizImpl _$$TopicQuizImplFromJson(Map<String, dynamic> json) =>
    _$TopicQuizImpl(
      id: json['id'] as String,
      topic: json['topic'] as String,
      question: json['question'] as String,
      options:
          (json['options'] as List<dynamic>).map((e) => e as String).toList(),
      difficulty: (json['difficulty'] as num).toInt(),
    );

Map<String, dynamic> _$$TopicQuizImplToJson(_$TopicQuizImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'topic': instance.topic,
      'question': instance.question,
      'options': instance.options,
      'difficulty': instance.difficulty,
    };

_$QuizResultResponseImpl _$$QuizResultResponseImplFromJson(
        Map<String, dynamic> json) =>
    _$QuizResultResponseImpl(
      isCorrect: json['is_correct'] as bool,
      correctAnswer: (json['correct_answer'] as num).toInt(),
      pointsEarned: (json['points_earned'] as num).toInt(),
      newLevel: (json['new_level'] as num?)?.toInt(),
      message: json['message'] as String,
    );

Map<String, dynamic> _$$QuizResultResponseImplToJson(
        _$QuizResultResponseImpl instance) =>
    <String, dynamic>{
      'is_correct': instance.isCorrect,
      'correct_answer': instance.correctAnswer,
      'points_earned': instance.pointsEarned,
      'new_level': instance.newLevel,
      'message': instance.message,
    };
