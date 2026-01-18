// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'progress_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

UserTopicProgress _$UserTopicProgressFromJson(Map<String, dynamic> json) {
  return _UserTopicProgress.fromJson(json);
}

/// @nodoc
mixin _$UserTopicProgress {
  String get id => throw _privateConstructorUsedError;
  @JsonKey(name: 'user_id')
  String get userId => throw _privateConstructorUsedError;
  String get topic => throw _privateConstructorUsedError;
  int get level => throw _privateConstructorUsedError;
  int get points => throw _privateConstructorUsedError;
  @JsonKey(name: 'created_at')
  DateTime get createdAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'updated_at')
  DateTime get updatedAt => throw _privateConstructorUsedError;

  /// Serializes this UserTopicProgress to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of UserTopicProgress
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $UserTopicProgressCopyWith<UserTopicProgress> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $UserTopicProgressCopyWith<$Res> {
  factory $UserTopicProgressCopyWith(
          UserTopicProgress value, $Res Function(UserTopicProgress) then) =
      _$UserTopicProgressCopyWithImpl<$Res, UserTopicProgress>;
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'user_id') String userId,
      String topic,
      int level,
      int points,
      @JsonKey(name: 'created_at') DateTime createdAt,
      @JsonKey(name: 'updated_at') DateTime updatedAt});
}

/// @nodoc
class _$UserTopicProgressCopyWithImpl<$Res, $Val extends UserTopicProgress>
    implements $UserTopicProgressCopyWith<$Res> {
  _$UserTopicProgressCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of UserTopicProgress
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? userId = null,
    Object? topic = null,
    Object? level = null,
    Object? points = null,
    Object? createdAt = null,
    Object? updatedAt = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      userId: null == userId
          ? _value.userId
          : userId // ignore: cast_nullable_to_non_nullable
              as String,
      topic: null == topic
          ? _value.topic
          : topic // ignore: cast_nullable_to_non_nullable
              as String,
      level: null == level
          ? _value.level
          : level // ignore: cast_nullable_to_non_nullable
              as int,
      points: null == points
          ? _value.points
          : points // ignore: cast_nullable_to_non_nullable
              as int,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      updatedAt: null == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$UserTopicProgressImplCopyWith<$Res>
    implements $UserTopicProgressCopyWith<$Res> {
  factory _$$UserTopicProgressImplCopyWith(_$UserTopicProgressImpl value,
          $Res Function(_$UserTopicProgressImpl) then) =
      __$$UserTopicProgressImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'user_id') String userId,
      String topic,
      int level,
      int points,
      @JsonKey(name: 'created_at') DateTime createdAt,
      @JsonKey(name: 'updated_at') DateTime updatedAt});
}

/// @nodoc
class __$$UserTopicProgressImplCopyWithImpl<$Res>
    extends _$UserTopicProgressCopyWithImpl<$Res, _$UserTopicProgressImpl>
    implements _$$UserTopicProgressImplCopyWith<$Res> {
  __$$UserTopicProgressImplCopyWithImpl(_$UserTopicProgressImpl _value,
      $Res Function(_$UserTopicProgressImpl) _then)
      : super(_value, _then);

  /// Create a copy of UserTopicProgress
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? userId = null,
    Object? topic = null,
    Object? level = null,
    Object? points = null,
    Object? createdAt = null,
    Object? updatedAt = null,
  }) {
    return _then(_$UserTopicProgressImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      userId: null == userId
          ? _value.userId
          : userId // ignore: cast_nullable_to_non_nullable
              as String,
      topic: null == topic
          ? _value.topic
          : topic // ignore: cast_nullable_to_non_nullable
              as String,
      level: null == level
          ? _value.level
          : level // ignore: cast_nullable_to_non_nullable
              as int,
      points: null == points
          ? _value.points
          : points // ignore: cast_nullable_to_non_nullable
              as int,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      updatedAt: null == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$UserTopicProgressImpl implements _UserTopicProgress {
  const _$UserTopicProgressImpl(
      {required this.id,
      @JsonKey(name: 'user_id') required this.userId,
      required this.topic,
      required this.level,
      required this.points,
      @JsonKey(name: 'created_at') required this.createdAt,
      @JsonKey(name: 'updated_at') required this.updatedAt});

  factory _$UserTopicProgressImpl.fromJson(Map<String, dynamic> json) =>
      _$$UserTopicProgressImplFromJson(json);

  @override
  final String id;
  @override
  @JsonKey(name: 'user_id')
  final String userId;
  @override
  final String topic;
  @override
  final int level;
  @override
  final int points;
  @override
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @override
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  @override
  String toString() {
    return 'UserTopicProgress(id: $id, userId: $userId, topic: $topic, level: $level, points: $points, createdAt: $createdAt, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$UserTopicProgressImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.userId, userId) || other.userId == userId) &&
            (identical(other.topic, topic) || other.topic == topic) &&
            (identical(other.level, level) || other.level == level) &&
            (identical(other.points, points) || other.points == points) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType, id, userId, topic, level, points, createdAt, updatedAt);

  /// Create a copy of UserTopicProgress
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$UserTopicProgressImplCopyWith<_$UserTopicProgressImpl> get copyWith =>
      __$$UserTopicProgressImplCopyWithImpl<_$UserTopicProgressImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$UserTopicProgressImplToJson(
      this,
    );
  }
}

abstract class _UserTopicProgress implements UserTopicProgress {
  const factory _UserTopicProgress(
          {required final String id,
          @JsonKey(name: 'user_id') required final String userId,
          required final String topic,
          required final int level,
          required final int points,
          @JsonKey(name: 'created_at') required final DateTime createdAt,
          @JsonKey(name: 'updated_at') required final DateTime updatedAt}) =
      _$UserTopicProgressImpl;

  factory _UserTopicProgress.fromJson(Map<String, dynamic> json) =
      _$UserTopicProgressImpl.fromJson;

  @override
  String get id;
  @override
  @JsonKey(name: 'user_id')
  String get userId;
  @override
  String get topic;
  @override
  int get level;
  @override
  int get points;
  @override
  @JsonKey(name: 'created_at')
  DateTime get createdAt;
  @override
  @JsonKey(name: 'updated_at')
  DateTime get updatedAt;

  /// Create a copy of UserTopicProgress
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$UserTopicProgressImplCopyWith<_$UserTopicProgressImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

TopicQuiz _$TopicQuizFromJson(Map<String, dynamic> json) {
  return _TopicQuiz.fromJson(json);
}

/// @nodoc
mixin _$TopicQuiz {
  String get id => throw _privateConstructorUsedError;
  String get topic => throw _privateConstructorUsedError;
  String get question => throw _privateConstructorUsedError;
  List<String> get options => throw _privateConstructorUsedError;
  int get difficulty => throw _privateConstructorUsedError;

  /// Serializes this TopicQuiz to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of TopicQuiz
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $TopicQuizCopyWith<TopicQuiz> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TopicQuizCopyWith<$Res> {
  factory $TopicQuizCopyWith(TopicQuiz value, $Res Function(TopicQuiz) then) =
      _$TopicQuizCopyWithImpl<$Res, TopicQuiz>;
  @useResult
  $Res call(
      {String id,
      String topic,
      String question,
      List<String> options,
      int difficulty});
}

/// @nodoc
class _$TopicQuizCopyWithImpl<$Res, $Val extends TopicQuiz>
    implements $TopicQuizCopyWith<$Res> {
  _$TopicQuizCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of TopicQuiz
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? topic = null,
    Object? question = null,
    Object? options = null,
    Object? difficulty = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      topic: null == topic
          ? _value.topic
          : topic // ignore: cast_nullable_to_non_nullable
              as String,
      question: null == question
          ? _value.question
          : question // ignore: cast_nullable_to_non_nullable
              as String,
      options: null == options
          ? _value.options
          : options // ignore: cast_nullable_to_non_nullable
              as List<String>,
      difficulty: null == difficulty
          ? _value.difficulty
          : difficulty // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$TopicQuizImplCopyWith<$Res>
    implements $TopicQuizCopyWith<$Res> {
  factory _$$TopicQuizImplCopyWith(
          _$TopicQuizImpl value, $Res Function(_$TopicQuizImpl) then) =
      __$$TopicQuizImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String topic,
      String question,
      List<String> options,
      int difficulty});
}

/// @nodoc
class __$$TopicQuizImplCopyWithImpl<$Res>
    extends _$TopicQuizCopyWithImpl<$Res, _$TopicQuizImpl>
    implements _$$TopicQuizImplCopyWith<$Res> {
  __$$TopicQuizImplCopyWithImpl(
      _$TopicQuizImpl _value, $Res Function(_$TopicQuizImpl) _then)
      : super(_value, _then);

  /// Create a copy of TopicQuiz
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? topic = null,
    Object? question = null,
    Object? options = null,
    Object? difficulty = null,
  }) {
    return _then(_$TopicQuizImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      topic: null == topic
          ? _value.topic
          : topic // ignore: cast_nullable_to_non_nullable
              as String,
      question: null == question
          ? _value.question
          : question // ignore: cast_nullable_to_non_nullable
              as String,
      options: null == options
          ? _value._options
          : options // ignore: cast_nullable_to_non_nullable
              as List<String>,
      difficulty: null == difficulty
          ? _value.difficulty
          : difficulty // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$TopicQuizImpl implements _TopicQuiz {
  const _$TopicQuizImpl(
      {required this.id,
      required this.topic,
      required this.question,
      required final List<String> options,
      required this.difficulty})
      : _options = options;

  factory _$TopicQuizImpl.fromJson(Map<String, dynamic> json) =>
      _$$TopicQuizImplFromJson(json);

  @override
  final String id;
  @override
  final String topic;
  @override
  final String question;
  final List<String> _options;
  @override
  List<String> get options {
    if (_options is EqualUnmodifiableListView) return _options;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_options);
  }

  @override
  final int difficulty;

  @override
  String toString() {
    return 'TopicQuiz(id: $id, topic: $topic, question: $question, options: $options, difficulty: $difficulty)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TopicQuizImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.topic, topic) || other.topic == topic) &&
            (identical(other.question, question) ||
                other.question == question) &&
            const DeepCollectionEquality().equals(other._options, _options) &&
            (identical(other.difficulty, difficulty) ||
                other.difficulty == difficulty));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, topic, question,
      const DeepCollectionEquality().hash(_options), difficulty);

  /// Create a copy of TopicQuiz
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TopicQuizImplCopyWith<_$TopicQuizImpl> get copyWith =>
      __$$TopicQuizImplCopyWithImpl<_$TopicQuizImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$TopicQuizImplToJson(
      this,
    );
  }
}

abstract class _TopicQuiz implements TopicQuiz {
  const factory _TopicQuiz(
      {required final String id,
      required final String topic,
      required final String question,
      required final List<String> options,
      required final int difficulty}) = _$TopicQuizImpl;

  factory _TopicQuiz.fromJson(Map<String, dynamic> json) =
      _$TopicQuizImpl.fromJson;

  @override
  String get id;
  @override
  String get topic;
  @override
  String get question;
  @override
  List<String> get options;
  @override
  int get difficulty;

  /// Create a copy of TopicQuiz
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TopicQuizImplCopyWith<_$TopicQuizImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

QuizResultResponse _$QuizResultResponseFromJson(Map<String, dynamic> json) {
  return _QuizResultResponse.fromJson(json);
}

/// @nodoc
mixin _$QuizResultResponse {
  @JsonKey(name: 'is_correct')
  bool get isCorrect => throw _privateConstructorUsedError;
  @JsonKey(name: 'correct_answer')
  int get correctAnswer => throw _privateConstructorUsedError;
  @JsonKey(name: 'points_earned')
  int get pointsEarned => throw _privateConstructorUsedError;
  @JsonKey(name: 'new_level')
  int? get newLevel => throw _privateConstructorUsedError;
  String get message => throw _privateConstructorUsedError;

  /// Serializes this QuizResultResponse to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of QuizResultResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $QuizResultResponseCopyWith<QuizResultResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $QuizResultResponseCopyWith<$Res> {
  factory $QuizResultResponseCopyWith(
          QuizResultResponse value, $Res Function(QuizResultResponse) then) =
      _$QuizResultResponseCopyWithImpl<$Res, QuizResultResponse>;
  @useResult
  $Res call(
      {@JsonKey(name: 'is_correct') bool isCorrect,
      @JsonKey(name: 'correct_answer') int correctAnswer,
      @JsonKey(name: 'points_earned') int pointsEarned,
      @JsonKey(name: 'new_level') int? newLevel,
      String message});
}

/// @nodoc
class _$QuizResultResponseCopyWithImpl<$Res, $Val extends QuizResultResponse>
    implements $QuizResultResponseCopyWith<$Res> {
  _$QuizResultResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of QuizResultResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? isCorrect = null,
    Object? correctAnswer = null,
    Object? pointsEarned = null,
    Object? newLevel = freezed,
    Object? message = null,
  }) {
    return _then(_value.copyWith(
      isCorrect: null == isCorrect
          ? _value.isCorrect
          : isCorrect // ignore: cast_nullable_to_non_nullable
              as bool,
      correctAnswer: null == correctAnswer
          ? _value.correctAnswer
          : correctAnswer // ignore: cast_nullable_to_non_nullable
              as int,
      pointsEarned: null == pointsEarned
          ? _value.pointsEarned
          : pointsEarned // ignore: cast_nullable_to_non_nullable
              as int,
      newLevel: freezed == newLevel
          ? _value.newLevel
          : newLevel // ignore: cast_nullable_to_non_nullable
              as int?,
      message: null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$QuizResultResponseImplCopyWith<$Res>
    implements $QuizResultResponseCopyWith<$Res> {
  factory _$$QuizResultResponseImplCopyWith(_$QuizResultResponseImpl value,
          $Res Function(_$QuizResultResponseImpl) then) =
      __$$QuizResultResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'is_correct') bool isCorrect,
      @JsonKey(name: 'correct_answer') int correctAnswer,
      @JsonKey(name: 'points_earned') int pointsEarned,
      @JsonKey(name: 'new_level') int? newLevel,
      String message});
}

/// @nodoc
class __$$QuizResultResponseImplCopyWithImpl<$Res>
    extends _$QuizResultResponseCopyWithImpl<$Res, _$QuizResultResponseImpl>
    implements _$$QuizResultResponseImplCopyWith<$Res> {
  __$$QuizResultResponseImplCopyWithImpl(_$QuizResultResponseImpl _value,
      $Res Function(_$QuizResultResponseImpl) _then)
      : super(_value, _then);

  /// Create a copy of QuizResultResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? isCorrect = null,
    Object? correctAnswer = null,
    Object? pointsEarned = null,
    Object? newLevel = freezed,
    Object? message = null,
  }) {
    return _then(_$QuizResultResponseImpl(
      isCorrect: null == isCorrect
          ? _value.isCorrect
          : isCorrect // ignore: cast_nullable_to_non_nullable
              as bool,
      correctAnswer: null == correctAnswer
          ? _value.correctAnswer
          : correctAnswer // ignore: cast_nullable_to_non_nullable
              as int,
      pointsEarned: null == pointsEarned
          ? _value.pointsEarned
          : pointsEarned // ignore: cast_nullable_to_non_nullable
              as int,
      newLevel: freezed == newLevel
          ? _value.newLevel
          : newLevel // ignore: cast_nullable_to_non_nullable
              as int?,
      message: null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$QuizResultResponseImpl implements _QuizResultResponse {
  const _$QuizResultResponseImpl(
      {@JsonKey(name: 'is_correct') required this.isCorrect,
      @JsonKey(name: 'correct_answer') required this.correctAnswer,
      @JsonKey(name: 'points_earned') required this.pointsEarned,
      @JsonKey(name: 'new_level') this.newLevel,
      required this.message});

  factory _$QuizResultResponseImpl.fromJson(Map<String, dynamic> json) =>
      _$$QuizResultResponseImplFromJson(json);

  @override
  @JsonKey(name: 'is_correct')
  final bool isCorrect;
  @override
  @JsonKey(name: 'correct_answer')
  final int correctAnswer;
  @override
  @JsonKey(name: 'points_earned')
  final int pointsEarned;
  @override
  @JsonKey(name: 'new_level')
  final int? newLevel;
  @override
  final String message;

  @override
  String toString() {
    return 'QuizResultResponse(isCorrect: $isCorrect, correctAnswer: $correctAnswer, pointsEarned: $pointsEarned, newLevel: $newLevel, message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$QuizResultResponseImpl &&
            (identical(other.isCorrect, isCorrect) ||
                other.isCorrect == isCorrect) &&
            (identical(other.correctAnswer, correctAnswer) ||
                other.correctAnswer == correctAnswer) &&
            (identical(other.pointsEarned, pointsEarned) ||
                other.pointsEarned == pointsEarned) &&
            (identical(other.newLevel, newLevel) ||
                other.newLevel == newLevel) &&
            (identical(other.message, message) || other.message == message));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType, isCorrect, correctAnswer, pointsEarned, newLevel, message);

  /// Create a copy of QuizResultResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$QuizResultResponseImplCopyWith<_$QuizResultResponseImpl> get copyWith =>
      __$$QuizResultResponseImplCopyWithImpl<_$QuizResultResponseImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$QuizResultResponseImplToJson(
      this,
    );
  }
}

abstract class _QuizResultResponse implements QuizResultResponse {
  const factory _QuizResultResponse(
      {@JsonKey(name: 'is_correct') required final bool isCorrect,
      @JsonKey(name: 'correct_answer') required final int correctAnswer,
      @JsonKey(name: 'points_earned') required final int pointsEarned,
      @JsonKey(name: 'new_level') final int? newLevel,
      required final String message}) = _$QuizResultResponseImpl;

  factory _QuizResultResponse.fromJson(Map<String, dynamic> json) =
      _$QuizResultResponseImpl.fromJson;

  @override
  @JsonKey(name: 'is_correct')
  bool get isCorrect;
  @override
  @JsonKey(name: 'correct_answer')
  int get correctAnswer;
  @override
  @JsonKey(name: 'points_earned')
  int get pointsEarned;
  @override
  @JsonKey(name: 'new_level')
  int? get newLevel;
  @override
  String get message;

  /// Create a copy of QuizResultResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$QuizResultResponseImplCopyWith<_$QuizResultResponseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
