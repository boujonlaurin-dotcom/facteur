// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'topic_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

UserTopicProfile _$UserTopicProfileFromJson(Map<String, dynamic> json) {
  return _UserTopicProfile.fromJson(json);
}

/// @nodoc
mixin _$UserTopicProfile {
  String get id => throw _privateConstructorUsedError;
  @JsonKey(name: 'topic_name')
  String get name => throw _privateConstructorUsedError;
  @JsonKey(name: 'slug_parent')
  String? get slugParent => throw _privateConstructorUsedError;
  List<String> get keywords => throw _privateConstructorUsedError;
  @JsonKey(name: 'intent_description')
  String? get intentDescription => throw _privateConstructorUsedError;
  @JsonKey(name: 'priority_multiplier')
  double get priorityMultiplier => throw _privateConstructorUsedError;
  @JsonKey(name: 'composite_score')
  double get compositeScore => throw _privateConstructorUsedError;
  @JsonKey(name: 'source_type', unknownEnumValue: TopicSourceType.explicit)
  TopicSourceType get sourceType => throw _privateConstructorUsedError;
  @JsonKey(name: 'entity_type')
  String? get entityType => throw _privateConstructorUsedError;
  @JsonKey(name: 'canonical_name')
  String? get canonicalName => throw _privateConstructorUsedError;
  @JsonKey(name: 'excluded_from_serein')
  bool get excludedFromSerein => throw _privateConstructorUsedError;
  @JsonKey(name: 'created_at')
  DateTime? get createdAt => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $UserTopicProfileCopyWith<UserTopicProfile> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $UserTopicProfileCopyWith<$Res> {
  factory $UserTopicProfileCopyWith(
          UserTopicProfile value, $Res Function(UserTopicProfile) then) =
      _$UserTopicProfileCopyWithImpl<$Res, UserTopicProfile>;
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'topic_name') String name,
      @JsonKey(name: 'slug_parent') String? slugParent,
      List<String> keywords,
      @JsonKey(name: 'intent_description') String? intentDescription,
      @JsonKey(name: 'priority_multiplier') double priorityMultiplier,
      @JsonKey(name: 'composite_score') double compositeScore,
      @JsonKey(name: 'source_type', unknownEnumValue: TopicSourceType.explicit)
      TopicSourceType sourceType,
      @JsonKey(name: 'entity_type') String? entityType,
      @JsonKey(name: 'canonical_name') String? canonicalName,
      @JsonKey(name: 'excluded_from_serein') bool excludedFromSerein,
      @JsonKey(name: 'created_at') DateTime? createdAt});
}

/// @nodoc
class _$UserTopicProfileCopyWithImpl<$Res, $Val extends UserTopicProfile>
    implements $UserTopicProfileCopyWith<$Res> {
  _$UserTopicProfileCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? slugParent = freezed,
    Object? keywords = null,
    Object? intentDescription = freezed,
    Object? priorityMultiplier = null,
    Object? compositeScore = null,
    Object? sourceType = null,
    Object? entityType = freezed,
    Object? canonicalName = freezed,
    Object? excludedFromSerein = null,
    Object? createdAt = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      slugParent: freezed == slugParent
          ? _value.slugParent
          : slugParent // ignore: cast_nullable_to_non_nullable
              as String?,
      keywords: null == keywords
          ? _value.keywords
          : keywords // ignore: cast_nullable_to_non_nullable
              as List<String>,
      intentDescription: freezed == intentDescription
          ? _value.intentDescription
          : intentDescription // ignore: cast_nullable_to_non_nullable
              as String?,
      priorityMultiplier: null == priorityMultiplier
          ? _value.priorityMultiplier
          : priorityMultiplier // ignore: cast_nullable_to_non_nullable
              as double,
      compositeScore: null == compositeScore
          ? _value.compositeScore
          : compositeScore // ignore: cast_nullable_to_non_nullable
              as double,
      sourceType: null == sourceType
          ? _value.sourceType
          : sourceType // ignore: cast_nullable_to_non_nullable
              as TopicSourceType,
      entityType: freezed == entityType
          ? _value.entityType
          : entityType // ignore: cast_nullable_to_non_nullable
              as String?,
      canonicalName: freezed == canonicalName
          ? _value.canonicalName
          : canonicalName // ignore: cast_nullable_to_non_nullable
              as String?,
      excludedFromSerein: null == excludedFromSerein
          ? _value.excludedFromSerein
          : excludedFromSerein // ignore: cast_nullable_to_non_nullable
              as bool,
      createdAt: freezed == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$UserTopicProfileImplCopyWith<$Res>
    implements $UserTopicProfileCopyWith<$Res> {
  factory _$$UserTopicProfileImplCopyWith(_$UserTopicProfileImpl value,
          $Res Function(_$UserTopicProfileImpl) then) =
      __$$UserTopicProfileImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'topic_name') String name,
      @JsonKey(name: 'slug_parent') String? slugParent,
      List<String> keywords,
      @JsonKey(name: 'intent_description') String? intentDescription,
      @JsonKey(name: 'priority_multiplier') double priorityMultiplier,
      @JsonKey(name: 'composite_score') double compositeScore,
      @JsonKey(name: 'source_type', unknownEnumValue: TopicSourceType.explicit)
      TopicSourceType sourceType,
      @JsonKey(name: 'entity_type') String? entityType,
      @JsonKey(name: 'canonical_name') String? canonicalName,
      @JsonKey(name: 'excluded_from_serein') bool excludedFromSerein,
      @JsonKey(name: 'created_at') DateTime? createdAt});
}

/// @nodoc
class __$$UserTopicProfileImplCopyWithImpl<$Res>
    extends _$UserTopicProfileCopyWithImpl<$Res, _$UserTopicProfileImpl>
    implements _$$UserTopicProfileImplCopyWith<$Res> {
  __$$UserTopicProfileImplCopyWithImpl(_$UserTopicProfileImpl _value,
      $Res Function(_$UserTopicProfileImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? slugParent = freezed,
    Object? keywords = null,
    Object? intentDescription = freezed,
    Object? priorityMultiplier = null,
    Object? compositeScore = null,
    Object? sourceType = null,
    Object? entityType = freezed,
    Object? canonicalName = freezed,
    Object? excludedFromSerein = null,
    Object? createdAt = freezed,
  }) {
    return _then(_$UserTopicProfileImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      slugParent: freezed == slugParent
          ? _value.slugParent
          : slugParent // ignore: cast_nullable_to_non_nullable
              as String?,
      keywords: null == keywords
          ? _value._keywords
          : keywords // ignore: cast_nullable_to_non_nullable
              as List<String>,
      intentDescription: freezed == intentDescription
          ? _value.intentDescription
          : intentDescription // ignore: cast_nullable_to_non_nullable
              as String?,
      priorityMultiplier: null == priorityMultiplier
          ? _value.priorityMultiplier
          : priorityMultiplier // ignore: cast_nullable_to_non_nullable
              as double,
      compositeScore: null == compositeScore
          ? _value.compositeScore
          : compositeScore // ignore: cast_nullable_to_non_nullable
              as double,
      sourceType: null == sourceType
          ? _value.sourceType
          : sourceType // ignore: cast_nullable_to_non_nullable
              as TopicSourceType,
      entityType: freezed == entityType
          ? _value.entityType
          : entityType // ignore: cast_nullable_to_non_nullable
              as String?,
      canonicalName: freezed == canonicalName
          ? _value.canonicalName
          : canonicalName // ignore: cast_nullable_to_non_nullable
              as String?,
      excludedFromSerein: null == excludedFromSerein
          ? _value.excludedFromSerein
          : excludedFromSerein // ignore: cast_nullable_to_non_nullable
              as bool,
      createdAt: freezed == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$UserTopicProfileImpl implements _UserTopicProfile {
  const _$UserTopicProfileImpl(
      {required this.id,
      @JsonKey(name: 'topic_name') required this.name,
      @JsonKey(name: 'slug_parent') this.slugParent,
      final List<String> keywords = const [],
      @JsonKey(name: 'intent_description') this.intentDescription,
      @JsonKey(name: 'priority_multiplier') this.priorityMultiplier = 1.0,
      @JsonKey(name: 'composite_score') this.compositeScore = 0.0,
      @JsonKey(name: 'source_type', unknownEnumValue: TopicSourceType.explicit)
      this.sourceType = TopicSourceType.explicit,
      @JsonKey(name: 'entity_type') this.entityType,
      @JsonKey(name: 'canonical_name') this.canonicalName,
      @JsonKey(name: 'excluded_from_serein') this.excludedFromSerein = false,
      @JsonKey(name: 'created_at') this.createdAt})
      : _keywords = keywords;

  factory _$UserTopicProfileImpl.fromJson(Map<String, dynamic> json) =>
      _$$UserTopicProfileImplFromJson(json);

  @override
  final String id;
  @override
  @JsonKey(name: 'topic_name')
  final String name;
  @override
  @JsonKey(name: 'slug_parent')
  final String? slugParent;
  final List<String> _keywords;
  @override
  @JsonKey()
  List<String> get keywords {
    if (_keywords is EqualUnmodifiableListView) return _keywords;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_keywords);
  }

  @override
  @JsonKey(name: 'intent_description')
  final String? intentDescription;
  @override
  @JsonKey(name: 'priority_multiplier')
  final double priorityMultiplier;
  @override
  @JsonKey(name: 'composite_score')
  final double compositeScore;
  @override
  @JsonKey(name: 'source_type', unknownEnumValue: TopicSourceType.explicit)
  final TopicSourceType sourceType;
  @override
  @JsonKey(name: 'entity_type')
  final String? entityType;
  @override
  @JsonKey(name: 'canonical_name')
  final String? canonicalName;
  @override
  @JsonKey(name: 'excluded_from_serein')
  final bool excludedFromSerein;
  @override
  @JsonKey(name: 'created_at')
  final DateTime? createdAt;

  @override
  String toString() {
    return 'UserTopicProfile(id: $id, name: $name, slugParent: $slugParent, keywords: $keywords, intentDescription: $intentDescription, priorityMultiplier: $priorityMultiplier, compositeScore: $compositeScore, sourceType: $sourceType, entityType: $entityType, canonicalName: $canonicalName, excludedFromSerein: $excludedFromSerein, createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$UserTopicProfileImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.slugParent, slugParent) ||
                other.slugParent == slugParent) &&
            const DeepCollectionEquality().equals(other._keywords, _keywords) &&
            (identical(other.intentDescription, intentDescription) ||
                other.intentDescription == intentDescription) &&
            (identical(other.priorityMultiplier, priorityMultiplier) ||
                other.priorityMultiplier == priorityMultiplier) &&
            (identical(other.compositeScore, compositeScore) ||
                other.compositeScore == compositeScore) &&
            (identical(other.sourceType, sourceType) ||
                other.sourceType == sourceType) &&
            (identical(other.entityType, entityType) ||
                other.entityType == entityType) &&
            (identical(other.canonicalName, canonicalName) ||
                other.canonicalName == canonicalName) &&
            (identical(other.excludedFromSerein, excludedFromSerein) ||
                other.excludedFromSerein == excludedFromSerein) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      name,
      slugParent,
      const DeepCollectionEquality().hash(_keywords),
      intentDescription,
      priorityMultiplier,
      compositeScore,
      sourceType,
      entityType,
      canonicalName,
      excludedFromSerein,
      createdAt);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$UserTopicProfileImplCopyWith<_$UserTopicProfileImpl> get copyWith =>
      __$$UserTopicProfileImplCopyWithImpl<_$UserTopicProfileImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$UserTopicProfileImplToJson(
      this,
    );
  }
}

abstract class _UserTopicProfile implements UserTopicProfile {
  const factory _UserTopicProfile(
      {required final String id,
      @JsonKey(name: 'topic_name') required final String name,
      @JsonKey(name: 'slug_parent') final String? slugParent,
      final List<String> keywords,
      @JsonKey(name: 'intent_description') final String? intentDescription,
      @JsonKey(name: 'priority_multiplier') final double priorityMultiplier,
      @JsonKey(name: 'composite_score') final double compositeScore,
      @JsonKey(name: 'source_type', unknownEnumValue: TopicSourceType.explicit)
      final TopicSourceType sourceType,
      @JsonKey(name: 'entity_type') final String? entityType,
      @JsonKey(name: 'canonical_name') final String? canonicalName,
      @JsonKey(name: 'excluded_from_serein') final bool excludedFromSerein,
      @JsonKey(name: 'created_at')
      final DateTime? createdAt}) = _$UserTopicProfileImpl;

  factory _UserTopicProfile.fromJson(Map<String, dynamic> json) =
      _$UserTopicProfileImpl.fromJson;

  @override
  String get id;
  @override
  @JsonKey(name: 'topic_name')
  String get name;
  @override
  @JsonKey(name: 'slug_parent')
  String? get slugParent;
  @override
  List<String> get keywords;
  @override
  @JsonKey(name: 'intent_description')
  String? get intentDescription;
  @override
  @JsonKey(name: 'priority_multiplier')
  double get priorityMultiplier;
  @override
  @JsonKey(name: 'composite_score')
  double get compositeScore;
  @override
  @JsonKey(name: 'source_type', unknownEnumValue: TopicSourceType.explicit)
  TopicSourceType get sourceType;
  @override
  @JsonKey(name: 'entity_type')
  String? get entityType;
  @override
  @JsonKey(name: 'canonical_name')
  String? get canonicalName;
  @override
  @JsonKey(name: 'excluded_from_serein')
  bool get excludedFromSerein;
  @override
  @JsonKey(name: 'created_at')
  DateTime? get createdAt;
  @override
  @JsonKey(ignore: true)
  _$$UserTopicProfileImplCopyWith<_$UserTopicProfileImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

PopularEntity _$PopularEntityFromJson(Map<String, dynamic> json) {
  return _PopularEntity.fromJson(json);
}

/// @nodoc
mixin _$PopularEntity {
  String get name => throw _privateConstructorUsedError;
  String get type => throw _privateConstructorUsedError;
  String? get theme => throw _privateConstructorUsedError;
  int get count => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $PopularEntityCopyWith<PopularEntity> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PopularEntityCopyWith<$Res> {
  factory $PopularEntityCopyWith(
          PopularEntity value, $Res Function(PopularEntity) then) =
      _$PopularEntityCopyWithImpl<$Res, PopularEntity>;
  @useResult
  $Res call({String name, String type, String? theme, int count});
}

/// @nodoc
class _$PopularEntityCopyWithImpl<$Res, $Val extends PopularEntity>
    implements $PopularEntityCopyWith<$Res> {
  _$PopularEntityCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? type = null,
    Object? theme = freezed,
    Object? count = null,
  }) {
    return _then(_value.copyWith(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as String,
      theme: freezed == theme
          ? _value.theme
          : theme // ignore: cast_nullable_to_non_nullable
              as String?,
      count: null == count
          ? _value.count
          : count // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$PopularEntityImplCopyWith<$Res>
    implements $PopularEntityCopyWith<$Res> {
  factory _$$PopularEntityImplCopyWith(
          _$PopularEntityImpl value, $Res Function(_$PopularEntityImpl) then) =
      __$$PopularEntityImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String name, String type, String? theme, int count});
}

/// @nodoc
class __$$PopularEntityImplCopyWithImpl<$Res>
    extends _$PopularEntityCopyWithImpl<$Res, _$PopularEntityImpl>
    implements _$$PopularEntityImplCopyWith<$Res> {
  __$$PopularEntityImplCopyWithImpl(
      _$PopularEntityImpl _value, $Res Function(_$PopularEntityImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? type = null,
    Object? theme = freezed,
    Object? count = null,
  }) {
    return _then(_$PopularEntityImpl(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as String,
      theme: freezed == theme
          ? _value.theme
          : theme // ignore: cast_nullable_to_non_nullable
              as String?,
      count: null == count
          ? _value.count
          : count // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$PopularEntityImpl implements _PopularEntity {
  const _$PopularEntityImpl(
      {required this.name, required this.type, this.theme, this.count = 0});

  factory _$PopularEntityImpl.fromJson(Map<String, dynamic> json) =>
      _$$PopularEntityImplFromJson(json);

  @override
  final String name;
  @override
  final String type;
  @override
  final String? theme;
  @override
  @JsonKey()
  final int count;

  @override
  String toString() {
    return 'PopularEntity(name: $name, type: $type, theme: $theme, count: $count)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PopularEntityImpl &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.theme, theme) || other.theme == theme) &&
            (identical(other.count, count) || other.count == count));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, name, type, theme, count);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$PopularEntityImplCopyWith<_$PopularEntityImpl> get copyWith =>
      __$$PopularEntityImplCopyWithImpl<_$PopularEntityImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$PopularEntityImplToJson(
      this,
    );
  }
}

abstract class _PopularEntity implements PopularEntity {
  const factory _PopularEntity(
      {required final String name,
      required final String type,
      final String? theme,
      final int count}) = _$PopularEntityImpl;

  factory _PopularEntity.fromJson(Map<String, dynamic> json) =
      _$PopularEntityImpl.fromJson;

  @override
  String get name;
  @override
  String get type;
  @override
  String? get theme;
  @override
  int get count;
  @override
  @JsonKey(ignore: true)
  _$$PopularEntityImplCopyWith<_$PopularEntityImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

DisambiguationSuggestion _$DisambiguationSuggestionFromJson(
    Map<String, dynamic> json) {
  return _DisambiguationSuggestion.fromJson(json);
}

/// @nodoc
mixin _$DisambiguationSuggestion {
  @JsonKey(name: 'canonical_name')
  String get canonicalName => throw _privateConstructorUsedError;
  @JsonKey(name: 'entity_type')
  String? get entityType => throw _privateConstructorUsedError;
  String get description => throw _privateConstructorUsedError;
  @JsonKey(name: 'slug_parent')
  String get slugParent => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $DisambiguationSuggestionCopyWith<DisambiguationSuggestion> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DisambiguationSuggestionCopyWith<$Res> {
  factory $DisambiguationSuggestionCopyWith(DisambiguationSuggestion value,
          $Res Function(DisambiguationSuggestion) then) =
      _$DisambiguationSuggestionCopyWithImpl<$Res, DisambiguationSuggestion>;
  @useResult
  $Res call(
      {@JsonKey(name: 'canonical_name') String canonicalName,
      @JsonKey(name: 'entity_type') String? entityType,
      String description,
      @JsonKey(name: 'slug_parent') String slugParent});
}

/// @nodoc
class _$DisambiguationSuggestionCopyWithImpl<$Res,
        $Val extends DisambiguationSuggestion>
    implements $DisambiguationSuggestionCopyWith<$Res> {
  _$DisambiguationSuggestionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? canonicalName = null,
    Object? entityType = freezed,
    Object? description = null,
    Object? slugParent = null,
  }) {
    return _then(_value.copyWith(
      canonicalName: null == canonicalName
          ? _value.canonicalName
          : canonicalName // ignore: cast_nullable_to_non_nullable
              as String,
      entityType: freezed == entityType
          ? _value.entityType
          : entityType // ignore: cast_nullable_to_non_nullable
              as String?,
      description: null == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
      slugParent: null == slugParent
          ? _value.slugParent
          : slugParent // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$DisambiguationSuggestionImplCopyWith<$Res>
    implements $DisambiguationSuggestionCopyWith<$Res> {
  factory _$$DisambiguationSuggestionImplCopyWith(
          _$DisambiguationSuggestionImpl value,
          $Res Function(_$DisambiguationSuggestionImpl) then) =
      __$$DisambiguationSuggestionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'canonical_name') String canonicalName,
      @JsonKey(name: 'entity_type') String? entityType,
      String description,
      @JsonKey(name: 'slug_parent') String slugParent});
}

/// @nodoc
class __$$DisambiguationSuggestionImplCopyWithImpl<$Res>
    extends _$DisambiguationSuggestionCopyWithImpl<$Res,
        _$DisambiguationSuggestionImpl>
    implements _$$DisambiguationSuggestionImplCopyWith<$Res> {
  __$$DisambiguationSuggestionImplCopyWithImpl(
      _$DisambiguationSuggestionImpl _value,
      $Res Function(_$DisambiguationSuggestionImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? canonicalName = null,
    Object? entityType = freezed,
    Object? description = null,
    Object? slugParent = null,
  }) {
    return _then(_$DisambiguationSuggestionImpl(
      canonicalName: null == canonicalName
          ? _value.canonicalName
          : canonicalName // ignore: cast_nullable_to_non_nullable
              as String,
      entityType: freezed == entityType
          ? _value.entityType
          : entityType // ignore: cast_nullable_to_non_nullable
              as String?,
      description: null == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
      slugParent: null == slugParent
          ? _value.slugParent
          : slugParent // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$DisambiguationSuggestionImpl implements _DisambiguationSuggestion {
  const _$DisambiguationSuggestionImpl(
      {@JsonKey(name: 'canonical_name') required this.canonicalName,
      @JsonKey(name: 'entity_type') this.entityType,
      required this.description,
      @JsonKey(name: 'slug_parent') required this.slugParent});

  factory _$DisambiguationSuggestionImpl.fromJson(Map<String, dynamic> json) =>
      _$$DisambiguationSuggestionImplFromJson(json);

  @override
  @JsonKey(name: 'canonical_name')
  final String canonicalName;
  @override
  @JsonKey(name: 'entity_type')
  final String? entityType;
  @override
  final String description;
  @override
  @JsonKey(name: 'slug_parent')
  final String slugParent;

  @override
  String toString() {
    return 'DisambiguationSuggestion(canonicalName: $canonicalName, entityType: $entityType, description: $description, slugParent: $slugParent)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DisambiguationSuggestionImpl &&
            (identical(other.canonicalName, canonicalName) ||
                other.canonicalName == canonicalName) &&
            (identical(other.entityType, entityType) ||
                other.entityType == entityType) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.slugParent, slugParent) ||
                other.slugParent == slugParent));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType, canonicalName, entityType, description, slugParent);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$DisambiguationSuggestionImplCopyWith<_$DisambiguationSuggestionImpl>
      get copyWith => __$$DisambiguationSuggestionImplCopyWithImpl<
          _$DisambiguationSuggestionImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$DisambiguationSuggestionImplToJson(
      this,
    );
  }
}

abstract class _DisambiguationSuggestion implements DisambiguationSuggestion {
  const factory _DisambiguationSuggestion(
          {@JsonKey(name: 'canonical_name') required final String canonicalName,
          @JsonKey(name: 'entity_type') final String? entityType,
          required final String description,
          @JsonKey(name: 'slug_parent') required final String slugParent}) =
      _$DisambiguationSuggestionImpl;

  factory _DisambiguationSuggestion.fromJson(Map<String, dynamic> json) =
      _$DisambiguationSuggestionImpl.fromJson;

  @override
  @JsonKey(name: 'canonical_name')
  String get canonicalName;
  @override
  @JsonKey(name: 'entity_type')
  String? get entityType;
  @override
  String get description;
  @override
  @JsonKey(name: 'slug_parent')
  String get slugParent;
  @override
  @JsonKey(ignore: true)
  _$$DisambiguationSuggestionImplCopyWith<_$DisambiguationSuggestionImpl>
      get copyWith => throw _privateConstructorUsedError;
}
