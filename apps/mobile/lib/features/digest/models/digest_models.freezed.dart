// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'digest_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

DigestScoreBreakdown _$DigestScoreBreakdownFromJson(Map<String, dynamic> json) {
  return _DigestScoreBreakdown.fromJson(json);
}

/// @nodoc
mixin _$DigestScoreBreakdown {
  String get label => throw _privateConstructorUsedError;
  double get points => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_positive')
  bool get isPositive => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $DigestScoreBreakdownCopyWith<DigestScoreBreakdown> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DigestScoreBreakdownCopyWith<$Res> {
  factory $DigestScoreBreakdownCopyWith(DigestScoreBreakdown value,
          $Res Function(DigestScoreBreakdown) then) =
      _$DigestScoreBreakdownCopyWithImpl<$Res, DigestScoreBreakdown>;
  @useResult
  $Res call(
      {String label,
      double points,
      @JsonKey(name: 'is_positive') bool isPositive});
}

/// @nodoc
class _$DigestScoreBreakdownCopyWithImpl<$Res,
        $Val extends DigestScoreBreakdown>
    implements $DigestScoreBreakdownCopyWith<$Res> {
  _$DigestScoreBreakdownCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? label = null,
    Object? points = null,
    Object? isPositive = null,
  }) {
    return _then(_value.copyWith(
      label: null == label
          ? _value.label
          : label // ignore: cast_nullable_to_non_nullable
              as String,
      points: null == points
          ? _value.points
          : points // ignore: cast_nullable_to_non_nullable
              as double,
      isPositive: null == isPositive
          ? _value.isPositive
          : isPositive // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$DigestScoreBreakdownImplCopyWith<$Res>
    implements $DigestScoreBreakdownCopyWith<$Res> {
  factory _$$DigestScoreBreakdownImplCopyWith(_$DigestScoreBreakdownImpl value,
          $Res Function(_$DigestScoreBreakdownImpl) then) =
      __$$DigestScoreBreakdownImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String label,
      double points,
      @JsonKey(name: 'is_positive') bool isPositive});
}

/// @nodoc
class __$$DigestScoreBreakdownImplCopyWithImpl<$Res>
    extends _$DigestScoreBreakdownCopyWithImpl<$Res, _$DigestScoreBreakdownImpl>
    implements _$$DigestScoreBreakdownImplCopyWith<$Res> {
  __$$DigestScoreBreakdownImplCopyWithImpl(_$DigestScoreBreakdownImpl _value,
      $Res Function(_$DigestScoreBreakdownImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? label = null,
    Object? points = null,
    Object? isPositive = null,
  }) {
    return _then(_$DigestScoreBreakdownImpl(
      label: null == label
          ? _value.label
          : label // ignore: cast_nullable_to_non_nullable
              as String,
      points: null == points
          ? _value.points
          : points // ignore: cast_nullable_to_non_nullable
              as double,
      isPositive: null == isPositive
          ? _value.isPositive
          : isPositive // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$DigestScoreBreakdownImpl implements _DigestScoreBreakdown {
  const _$DigestScoreBreakdownImpl(
      {required this.label,
      required this.points,
      @JsonKey(name: 'is_positive') required this.isPositive});

  factory _$DigestScoreBreakdownImpl.fromJson(Map<String, dynamic> json) =>
      _$$DigestScoreBreakdownImplFromJson(json);

  @override
  final String label;
  @override
  final double points;
  @override
  @JsonKey(name: 'is_positive')
  final bool isPositive;

  @override
  String toString() {
    return 'DigestScoreBreakdown(label: $label, points: $points, isPositive: $isPositive)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DigestScoreBreakdownImpl &&
            (identical(other.label, label) || other.label == label) &&
            (identical(other.points, points) || other.points == points) &&
            (identical(other.isPositive, isPositive) ||
                other.isPositive == isPositive));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, label, points, isPositive);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$DigestScoreBreakdownImplCopyWith<_$DigestScoreBreakdownImpl>
      get copyWith =>
          __$$DigestScoreBreakdownImplCopyWithImpl<_$DigestScoreBreakdownImpl>(
              this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$DigestScoreBreakdownImplToJson(
      this,
    );
  }
}

abstract class _DigestScoreBreakdown implements DigestScoreBreakdown {
  const factory _DigestScoreBreakdown(
          {required final String label,
          required final double points,
          @JsonKey(name: 'is_positive') required final bool isPositive}) =
      _$DigestScoreBreakdownImpl;

  factory _DigestScoreBreakdown.fromJson(Map<String, dynamic> json) =
      _$DigestScoreBreakdownImpl.fromJson;

  @override
  String get label;
  @override
  double get points;
  @override
  @JsonKey(name: 'is_positive')
  bool get isPositive;
  @override
  @JsonKey(ignore: true)
  _$$DigestScoreBreakdownImplCopyWith<_$DigestScoreBreakdownImpl>
      get copyWith => throw _privateConstructorUsedError;
}

DigestRecommendationReason _$DigestRecommendationReasonFromJson(
    Map<String, dynamic> json) {
  return _DigestRecommendationReason.fromJson(json);
}

/// @nodoc
mixin _$DigestRecommendationReason {
  String get label => throw _privateConstructorUsedError;
  @JsonKey(name: 'score_total')
  double get scoreTotal => throw _privateConstructorUsedError;
  List<DigestScoreBreakdown> get breakdown =>
      throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $DigestRecommendationReasonCopyWith<DigestRecommendationReason>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DigestRecommendationReasonCopyWith<$Res> {
  factory $DigestRecommendationReasonCopyWith(DigestRecommendationReason value,
          $Res Function(DigestRecommendationReason) then) =
      _$DigestRecommendationReasonCopyWithImpl<$Res,
          DigestRecommendationReason>;
  @useResult
  $Res call(
      {String label,
      @JsonKey(name: 'score_total') double scoreTotal,
      List<DigestScoreBreakdown> breakdown});
}

/// @nodoc
class _$DigestRecommendationReasonCopyWithImpl<$Res,
        $Val extends DigestRecommendationReason>
    implements $DigestRecommendationReasonCopyWith<$Res> {
  _$DigestRecommendationReasonCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? label = null,
    Object? scoreTotal = null,
    Object? breakdown = null,
  }) {
    return _then(_value.copyWith(
      label: null == label
          ? _value.label
          : label // ignore: cast_nullable_to_non_nullable
              as String,
      scoreTotal: null == scoreTotal
          ? _value.scoreTotal
          : scoreTotal // ignore: cast_nullable_to_non_nullable
              as double,
      breakdown: null == breakdown
          ? _value.breakdown
          : breakdown // ignore: cast_nullable_to_non_nullable
              as List<DigestScoreBreakdown>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$DigestRecommendationReasonImplCopyWith<$Res>
    implements $DigestRecommendationReasonCopyWith<$Res> {
  factory _$$DigestRecommendationReasonImplCopyWith(
          _$DigestRecommendationReasonImpl value,
          $Res Function(_$DigestRecommendationReasonImpl) then) =
      __$$DigestRecommendationReasonImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String label,
      @JsonKey(name: 'score_total') double scoreTotal,
      List<DigestScoreBreakdown> breakdown});
}

/// @nodoc
class __$$DigestRecommendationReasonImplCopyWithImpl<$Res>
    extends _$DigestRecommendationReasonCopyWithImpl<$Res,
        _$DigestRecommendationReasonImpl>
    implements _$$DigestRecommendationReasonImplCopyWith<$Res> {
  __$$DigestRecommendationReasonImplCopyWithImpl(
      _$DigestRecommendationReasonImpl _value,
      $Res Function(_$DigestRecommendationReasonImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? label = null,
    Object? scoreTotal = null,
    Object? breakdown = null,
  }) {
    return _then(_$DigestRecommendationReasonImpl(
      label: null == label
          ? _value.label
          : label // ignore: cast_nullable_to_non_nullable
              as String,
      scoreTotal: null == scoreTotal
          ? _value.scoreTotal
          : scoreTotal // ignore: cast_nullable_to_non_nullable
              as double,
      breakdown: null == breakdown
          ? _value._breakdown
          : breakdown // ignore: cast_nullable_to_non_nullable
              as List<DigestScoreBreakdown>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$DigestRecommendationReasonImpl implements _DigestRecommendationReason {
  const _$DigestRecommendationReasonImpl(
      {required this.label,
      @JsonKey(name: 'score_total') required this.scoreTotal,
      required final List<DigestScoreBreakdown> breakdown})
      : _breakdown = breakdown;

  factory _$DigestRecommendationReasonImpl.fromJson(
          Map<String, dynamic> json) =>
      _$$DigestRecommendationReasonImplFromJson(json);

  @override
  final String label;
  @override
  @JsonKey(name: 'score_total')
  final double scoreTotal;
  final List<DigestScoreBreakdown> _breakdown;
  @override
  List<DigestScoreBreakdown> get breakdown {
    if (_breakdown is EqualUnmodifiableListView) return _breakdown;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_breakdown);
  }

  @override
  String toString() {
    return 'DigestRecommendationReason(label: $label, scoreTotal: $scoreTotal, breakdown: $breakdown)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DigestRecommendationReasonImpl &&
            (identical(other.label, label) || other.label == label) &&
            (identical(other.scoreTotal, scoreTotal) ||
                other.scoreTotal == scoreTotal) &&
            const DeepCollectionEquality()
                .equals(other._breakdown, _breakdown));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, label, scoreTotal,
      const DeepCollectionEquality().hash(_breakdown));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$DigestRecommendationReasonImplCopyWith<_$DigestRecommendationReasonImpl>
      get copyWith => __$$DigestRecommendationReasonImplCopyWithImpl<
          _$DigestRecommendationReasonImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$DigestRecommendationReasonImplToJson(
      this,
    );
  }
}

abstract class _DigestRecommendationReason
    implements DigestRecommendationReason {
  const factory _DigestRecommendationReason(
          {required final String label,
          @JsonKey(name: 'score_total') required final double scoreTotal,
          required final List<DigestScoreBreakdown> breakdown}) =
      _$DigestRecommendationReasonImpl;

  factory _DigestRecommendationReason.fromJson(Map<String, dynamic> json) =
      _$DigestRecommendationReasonImpl.fromJson;

  @override
  String get label;
  @override
  @JsonKey(name: 'score_total')
  double get scoreTotal;
  @override
  List<DigestScoreBreakdown> get breakdown;
  @override
  @JsonKey(ignore: true)
  _$$DigestRecommendationReasonImplCopyWith<_$DigestRecommendationReasonImpl>
      get copyWith => throw _privateConstructorUsedError;
}

SourceMini _$SourceMiniFromJson(Map<String, dynamic> json) {
  return _SourceMini.fromJson(json);
}

/// @nodoc
mixin _$SourceMini {
  @JsonKey(name: 'id')
  String? get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  @JsonKey(name: 'logo_url')
  String? get logoUrl => throw _privateConstructorUsedError;
  @JsonKey(name: 'type')
  String? get type => throw _privateConstructorUsedError;
  String? get theme => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $SourceMiniCopyWith<SourceMini> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SourceMiniCopyWith<$Res> {
  factory $SourceMiniCopyWith(
          SourceMini value, $Res Function(SourceMini) then) =
      _$SourceMiniCopyWithImpl<$Res, SourceMini>;
  @useResult
  $Res call(
      {@JsonKey(name: 'id') String? id,
      String name,
      @JsonKey(name: 'logo_url') String? logoUrl,
      @JsonKey(name: 'type') String? type,
      String? theme});
}

/// @nodoc
class _$SourceMiniCopyWithImpl<$Res, $Val extends SourceMini>
    implements $SourceMiniCopyWith<$Res> {
  _$SourceMiniCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = freezed,
    Object? name = null,
    Object? logoUrl = freezed,
    Object? type = freezed,
    Object? theme = freezed,
  }) {
    return _then(_value.copyWith(
      id: freezed == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String?,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      logoUrl: freezed == logoUrl
          ? _value.logoUrl
          : logoUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      type: freezed == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as String?,
      theme: freezed == theme
          ? _value.theme
          : theme // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SourceMiniImplCopyWith<$Res>
    implements $SourceMiniCopyWith<$Res> {
  factory _$$SourceMiniImplCopyWith(
          _$SourceMiniImpl value, $Res Function(_$SourceMiniImpl) then) =
      __$$SourceMiniImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'id') String? id,
      String name,
      @JsonKey(name: 'logo_url') String? logoUrl,
      @JsonKey(name: 'type') String? type,
      String? theme});
}

/// @nodoc
class __$$SourceMiniImplCopyWithImpl<$Res>
    extends _$SourceMiniCopyWithImpl<$Res, _$SourceMiniImpl>
    implements _$$SourceMiniImplCopyWith<$Res> {
  __$$SourceMiniImplCopyWithImpl(
      _$SourceMiniImpl _value, $Res Function(_$SourceMiniImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = freezed,
    Object? name = null,
    Object? logoUrl = freezed,
    Object? type = freezed,
    Object? theme = freezed,
  }) {
    return _then(_$SourceMiniImpl(
      id: freezed == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String?,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      logoUrl: freezed == logoUrl
          ? _value.logoUrl
          : logoUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      type: freezed == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as String?,
      theme: freezed == theme
          ? _value.theme
          : theme // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SourceMiniImpl implements _SourceMini {
  const _$SourceMiniImpl(
      {@JsonKey(name: 'id') this.id,
      this.name = 'Inconnu',
      @JsonKey(name: 'logo_url') this.logoUrl,
      @JsonKey(name: 'type') this.type,
      this.theme});

  factory _$SourceMiniImpl.fromJson(Map<String, dynamic> json) =>
      _$$SourceMiniImplFromJson(json);

  @override
  @JsonKey(name: 'id')
  final String? id;
  @override
  @JsonKey()
  final String name;
  @override
  @JsonKey(name: 'logo_url')
  final String? logoUrl;
  @override
  @JsonKey(name: 'type')
  final String? type;
  @override
  final String? theme;

  @override
  String toString() {
    return 'SourceMini(id: $id, name: $name, logoUrl: $logoUrl, type: $type, theme: $theme)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SourceMiniImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.logoUrl, logoUrl) || other.logoUrl == logoUrl) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.theme, theme) || other.theme == theme));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, id, name, logoUrl, type, theme);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$SourceMiniImplCopyWith<_$SourceMiniImpl> get copyWith =>
      __$$SourceMiniImplCopyWithImpl<_$SourceMiniImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SourceMiniImplToJson(
      this,
    );
  }
}

abstract class _SourceMini implements SourceMini {
  const factory _SourceMini(
      {@JsonKey(name: 'id') final String? id,
      final String name,
      @JsonKey(name: 'logo_url') final String? logoUrl,
      @JsonKey(name: 'type') final String? type,
      final String? theme}) = _$SourceMiniImpl;

  factory _SourceMini.fromJson(Map<String, dynamic> json) =
      _$SourceMiniImpl.fromJson;

  @override
  @JsonKey(name: 'id')
  String? get id;
  @override
  String get name;
  @override
  @JsonKey(name: 'logo_url')
  String? get logoUrl;
  @override
  @JsonKey(name: 'type')
  String? get type;
  @override
  String? get theme;
  @override
  @JsonKey(ignore: true)
  _$$SourceMiniImplCopyWith<_$SourceMiniImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

DigestItem _$DigestItemFromJson(Map<String, dynamic> json) {
  return _DigestItem.fromJson(json);
}

/// @nodoc
mixin _$DigestItem {
  @JsonKey(name: 'content_id')
  String get contentId => throw _privateConstructorUsedError;
  String get title => throw _privateConstructorUsedError;
  String get url => throw _privateConstructorUsedError;
  @JsonKey(name: 'thumbnail_url')
  String? get thumbnailUrl => throw _privateConstructorUsedError;
  String? get description => throw _privateConstructorUsedError;
  List<String> get topics => throw _privateConstructorUsedError;
  @JsonKey(
      name: 'content_type',
      fromJson: _contentTypeFromJson,
      toJson: _contentTypeToJson)
  ContentType get contentType => throw _privateConstructorUsedError;
  @JsonKey(name: 'duration_seconds')
  int? get durationSeconds => throw _privateConstructorUsedError;
  @JsonKey(name: 'published_at')
  DateTime? get publishedAt => throw _privateConstructorUsedError;
  SourceMini? get source => throw _privateConstructorUsedError;
  int get rank => throw _privateConstructorUsedError;
  String get reason => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_paid')
  bool get isPaid => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_read')
  bool get isRead => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_saved')
  bool get isSaved => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_liked')
  bool get isLiked => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_dismissed')
  bool get isDismissed => throw _privateConstructorUsedError;
  @JsonKey(name: 'recommendation_reason')
  DigestRecommendationReason? get recommendationReason =>
      throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $DigestItemCopyWith<DigestItem> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DigestItemCopyWith<$Res> {
  factory $DigestItemCopyWith(
          DigestItem value, $Res Function(DigestItem) then) =
      _$DigestItemCopyWithImpl<$Res, DigestItem>;
  @useResult
  $Res call(
      {@JsonKey(name: 'content_id') String contentId,
      String title,
      String url,
      @JsonKey(name: 'thumbnail_url') String? thumbnailUrl,
      String? description,
      List<String> topics,
      @JsonKey(
          name: 'content_type',
          fromJson: _contentTypeFromJson,
          toJson: _contentTypeToJson)
      ContentType contentType,
      @JsonKey(name: 'duration_seconds') int? durationSeconds,
      @JsonKey(name: 'published_at') DateTime? publishedAt,
      SourceMini? source,
      int rank,
      String reason,
      @JsonKey(name: 'is_paid') bool isPaid,
      @JsonKey(name: 'is_read') bool isRead,
      @JsonKey(name: 'is_saved') bool isSaved,
      @JsonKey(name: 'is_liked') bool isLiked,
      @JsonKey(name: 'is_dismissed') bool isDismissed,
      @JsonKey(name: 'recommendation_reason')
      DigestRecommendationReason? recommendationReason});

  $SourceMiniCopyWith<$Res>? get source;
  $DigestRecommendationReasonCopyWith<$Res>? get recommendationReason;
}

/// @nodoc
class _$DigestItemCopyWithImpl<$Res, $Val extends DigestItem>
    implements $DigestItemCopyWith<$Res> {
  _$DigestItemCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? contentId = null,
    Object? title = null,
    Object? url = null,
    Object? thumbnailUrl = freezed,
    Object? description = freezed,
    Object? topics = null,
    Object? contentType = null,
    Object? durationSeconds = freezed,
    Object? publishedAt = freezed,
    Object? source = freezed,
    Object? rank = null,
    Object? reason = null,
    Object? isPaid = null,
    Object? isRead = null,
    Object? isSaved = null,
    Object? isLiked = null,
    Object? isDismissed = null,
    Object? recommendationReason = freezed,
  }) {
    return _then(_value.copyWith(
      contentId: null == contentId
          ? _value.contentId
          : contentId // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      url: null == url
          ? _value.url
          : url // ignore: cast_nullable_to_non_nullable
              as String,
      thumbnailUrl: freezed == thumbnailUrl
          ? _value.thumbnailUrl
          : thumbnailUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
      topics: null == topics
          ? _value.topics
          : topics // ignore: cast_nullable_to_non_nullable
              as List<String>,
      contentType: null == contentType
          ? _value.contentType
          : contentType // ignore: cast_nullable_to_non_nullable
              as ContentType,
      durationSeconds: freezed == durationSeconds
          ? _value.durationSeconds
          : durationSeconds // ignore: cast_nullable_to_non_nullable
              as int?,
      publishedAt: freezed == publishedAt
          ? _value.publishedAt
          : publishedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      source: freezed == source
          ? _value.source
          : source // ignore: cast_nullable_to_non_nullable
              as SourceMini?,
      rank: null == rank
          ? _value.rank
          : rank // ignore: cast_nullable_to_non_nullable
              as int,
      reason: null == reason
          ? _value.reason
          : reason // ignore: cast_nullable_to_non_nullable
              as String,
      isPaid: null == isPaid
          ? _value.isPaid
          : isPaid // ignore: cast_nullable_to_non_nullable
              as bool,
      isRead: null == isRead
          ? _value.isRead
          : isRead // ignore: cast_nullable_to_non_nullable
              as bool,
      isSaved: null == isSaved
          ? _value.isSaved
          : isSaved // ignore: cast_nullable_to_non_nullable
              as bool,
      isLiked: null == isLiked
          ? _value.isLiked
          : isLiked // ignore: cast_nullable_to_non_nullable
              as bool,
      isDismissed: null == isDismissed
          ? _value.isDismissed
          : isDismissed // ignore: cast_nullable_to_non_nullable
              as bool,
      recommendationReason: freezed == recommendationReason
          ? _value.recommendationReason
          : recommendationReason // ignore: cast_nullable_to_non_nullable
              as DigestRecommendationReason?,
    ) as $Val);
  }

  @override
  @pragma('vm:prefer-inline')
  $SourceMiniCopyWith<$Res>? get source {
    if (_value.source == null) {
      return null;
    }

    return $SourceMiniCopyWith<$Res>(_value.source!, (value) {
      return _then(_value.copyWith(source: value) as $Val);
    });
  }

  @override
  @pragma('vm:prefer-inline')
  $DigestRecommendationReasonCopyWith<$Res>? get recommendationReason {
    if (_value.recommendationReason == null) {
      return null;
    }

    return $DigestRecommendationReasonCopyWith<$Res>(
        _value.recommendationReason!, (value) {
      return _then(_value.copyWith(recommendationReason: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$DigestItemImplCopyWith<$Res>
    implements $DigestItemCopyWith<$Res> {
  factory _$$DigestItemImplCopyWith(
          _$DigestItemImpl value, $Res Function(_$DigestItemImpl) then) =
      __$$DigestItemImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'content_id') String contentId,
      String title,
      String url,
      @JsonKey(name: 'thumbnail_url') String? thumbnailUrl,
      String? description,
      List<String> topics,
      @JsonKey(
          name: 'content_type',
          fromJson: _contentTypeFromJson,
          toJson: _contentTypeToJson)
      ContentType contentType,
      @JsonKey(name: 'duration_seconds') int? durationSeconds,
      @JsonKey(name: 'published_at') DateTime? publishedAt,
      SourceMini? source,
      int rank,
      String reason,
      @JsonKey(name: 'is_paid') bool isPaid,
      @JsonKey(name: 'is_read') bool isRead,
      @JsonKey(name: 'is_saved') bool isSaved,
      @JsonKey(name: 'is_liked') bool isLiked,
      @JsonKey(name: 'is_dismissed') bool isDismissed,
      @JsonKey(name: 'recommendation_reason')
      DigestRecommendationReason? recommendationReason});

  @override
  $SourceMiniCopyWith<$Res>? get source;
  @override
  $DigestRecommendationReasonCopyWith<$Res>? get recommendationReason;
}

/// @nodoc
class __$$DigestItemImplCopyWithImpl<$Res>
    extends _$DigestItemCopyWithImpl<$Res, _$DigestItemImpl>
    implements _$$DigestItemImplCopyWith<$Res> {
  __$$DigestItemImplCopyWithImpl(
      _$DigestItemImpl _value, $Res Function(_$DigestItemImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? contentId = null,
    Object? title = null,
    Object? url = null,
    Object? thumbnailUrl = freezed,
    Object? description = freezed,
    Object? topics = null,
    Object? contentType = null,
    Object? durationSeconds = freezed,
    Object? publishedAt = freezed,
    Object? source = freezed,
    Object? rank = null,
    Object? reason = null,
    Object? isPaid = null,
    Object? isRead = null,
    Object? isSaved = null,
    Object? isLiked = null,
    Object? isDismissed = null,
    Object? recommendationReason = freezed,
  }) {
    return _then(_$DigestItemImpl(
      contentId: null == contentId
          ? _value.contentId
          : contentId // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      url: null == url
          ? _value.url
          : url // ignore: cast_nullable_to_non_nullable
              as String,
      thumbnailUrl: freezed == thumbnailUrl
          ? _value.thumbnailUrl
          : thumbnailUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
      topics: null == topics
          ? _value._topics
          : topics // ignore: cast_nullable_to_non_nullable
              as List<String>,
      contentType: null == contentType
          ? _value.contentType
          : contentType // ignore: cast_nullable_to_non_nullable
              as ContentType,
      durationSeconds: freezed == durationSeconds
          ? _value.durationSeconds
          : durationSeconds // ignore: cast_nullable_to_non_nullable
              as int?,
      publishedAt: freezed == publishedAt
          ? _value.publishedAt
          : publishedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      source: freezed == source
          ? _value.source
          : source // ignore: cast_nullable_to_non_nullable
              as SourceMini?,
      rank: null == rank
          ? _value.rank
          : rank // ignore: cast_nullable_to_non_nullable
              as int,
      reason: null == reason
          ? _value.reason
          : reason // ignore: cast_nullable_to_non_nullable
              as String,
      isPaid: null == isPaid
          ? _value.isPaid
          : isPaid // ignore: cast_nullable_to_non_nullable
              as bool,
      isRead: null == isRead
          ? _value.isRead
          : isRead // ignore: cast_nullable_to_non_nullable
              as bool,
      isSaved: null == isSaved
          ? _value.isSaved
          : isSaved // ignore: cast_nullable_to_non_nullable
              as bool,
      isLiked: null == isLiked
          ? _value.isLiked
          : isLiked // ignore: cast_nullable_to_non_nullable
              as bool,
      isDismissed: null == isDismissed
          ? _value.isDismissed
          : isDismissed // ignore: cast_nullable_to_non_nullable
              as bool,
      recommendationReason: freezed == recommendationReason
          ? _value.recommendationReason
          : recommendationReason // ignore: cast_nullable_to_non_nullable
              as DigestRecommendationReason?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$DigestItemImpl implements _DigestItem {
  const _$DigestItemImpl(
      {@JsonKey(name: 'content_id') required this.contentId,
      this.title = 'Sans titre',
      this.url = '',
      @JsonKey(name: 'thumbnail_url') this.thumbnailUrl,
      this.description,
      final List<String> topics = const [],
      @JsonKey(
          name: 'content_type',
          fromJson: _contentTypeFromJson,
          toJson: _contentTypeToJson)
      this.contentType = ContentType.article,
      @JsonKey(name: 'duration_seconds') this.durationSeconds,
      @JsonKey(name: 'published_at') this.publishedAt,
      this.source,
      this.rank = 0,
      this.reason = '',
      @JsonKey(name: 'is_paid') this.isPaid = false,
      @JsonKey(name: 'is_read') this.isRead = false,
      @JsonKey(name: 'is_saved') this.isSaved = false,
      @JsonKey(name: 'is_liked') this.isLiked = false,
      @JsonKey(name: 'is_dismissed') this.isDismissed = false,
      @JsonKey(name: 'recommendation_reason') this.recommendationReason})
      : _topics = topics;

  factory _$DigestItemImpl.fromJson(Map<String, dynamic> json) =>
      _$$DigestItemImplFromJson(json);

  @override
  @JsonKey(name: 'content_id')
  final String contentId;
  @override
  @JsonKey()
  final String title;
  @override
  @JsonKey()
  final String url;
  @override
  @JsonKey(name: 'thumbnail_url')
  final String? thumbnailUrl;
  @override
  final String? description;
  final List<String> _topics;
  @override
  @JsonKey()
  List<String> get topics {
    if (_topics is EqualUnmodifiableListView) return _topics;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_topics);
  }

  @override
  @JsonKey(
      name: 'content_type',
      fromJson: _contentTypeFromJson,
      toJson: _contentTypeToJson)
  final ContentType contentType;
  @override
  @JsonKey(name: 'duration_seconds')
  final int? durationSeconds;
  @override
  @JsonKey(name: 'published_at')
  final DateTime? publishedAt;
  @override
  final SourceMini? source;
  @override
  @JsonKey()
  final int rank;
  @override
  @JsonKey()
  final String reason;
  @override
  @JsonKey(name: 'is_paid')
  final bool isPaid;
  @override
  @JsonKey(name: 'is_read')
  final bool isRead;
  @override
  @JsonKey(name: 'is_saved')
  final bool isSaved;
  @override
  @JsonKey(name: 'is_liked')
  final bool isLiked;
  @override
  @JsonKey(name: 'is_dismissed')
  final bool isDismissed;
  @override
  @JsonKey(name: 'recommendation_reason')
  final DigestRecommendationReason? recommendationReason;

  @override
  String toString() {
    return 'DigestItem(contentId: $contentId, title: $title, url: $url, thumbnailUrl: $thumbnailUrl, description: $description, topics: $topics, contentType: $contentType, durationSeconds: $durationSeconds, publishedAt: $publishedAt, source: $source, rank: $rank, reason: $reason, isPaid: $isPaid, isRead: $isRead, isSaved: $isSaved, isLiked: $isLiked, isDismissed: $isDismissed, recommendationReason: $recommendationReason)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DigestItemImpl &&
            (identical(other.contentId, contentId) ||
                other.contentId == contentId) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.url, url) || other.url == url) &&
            (identical(other.thumbnailUrl, thumbnailUrl) ||
                other.thumbnailUrl == thumbnailUrl) &&
            (identical(other.description, description) ||
                other.description == description) &&
            const DeepCollectionEquality().equals(other._topics, _topics) &&
            (identical(other.contentType, contentType) ||
                other.contentType == contentType) &&
            (identical(other.durationSeconds, durationSeconds) ||
                other.durationSeconds == durationSeconds) &&
            (identical(other.publishedAt, publishedAt) ||
                other.publishedAt == publishedAt) &&
            (identical(other.source, source) || other.source == source) &&
            (identical(other.rank, rank) || other.rank == rank) &&
            (identical(other.reason, reason) || other.reason == reason) &&
            (identical(other.isPaid, isPaid) || other.isPaid == isPaid) &&
            (identical(other.isRead, isRead) || other.isRead == isRead) &&
            (identical(other.isSaved, isSaved) || other.isSaved == isSaved) &&
            (identical(other.isLiked, isLiked) || other.isLiked == isLiked) &&
            (identical(other.isDismissed, isDismissed) ||
                other.isDismissed == isDismissed) &&
            (identical(other.recommendationReason, recommendationReason) ||
                other.recommendationReason == recommendationReason));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      contentId,
      title,
      url,
      thumbnailUrl,
      description,
      const DeepCollectionEquality().hash(_topics),
      contentType,
      durationSeconds,
      publishedAt,
      source,
      rank,
      reason,
      isPaid,
      isRead,
      isSaved,
      isLiked,
      isDismissed,
      recommendationReason);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$DigestItemImplCopyWith<_$DigestItemImpl> get copyWith =>
      __$$DigestItemImplCopyWithImpl<_$DigestItemImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$DigestItemImplToJson(
      this,
    );
  }
}

abstract class _DigestItem implements DigestItem {
  const factory _DigestItem(
          {@JsonKey(name: 'content_id') required final String contentId,
          final String title,
          final String url,
          @JsonKey(name: 'thumbnail_url') final String? thumbnailUrl,
          final String? description,
          final List<String> topics,
          @JsonKey(
              name: 'content_type',
              fromJson: _contentTypeFromJson,
              toJson: _contentTypeToJson)
          final ContentType contentType,
          @JsonKey(name: 'duration_seconds') final int? durationSeconds,
          @JsonKey(name: 'published_at') final DateTime? publishedAt,
          final SourceMini? source,
          final int rank,
          final String reason,
          @JsonKey(name: 'is_paid') final bool isPaid,
          @JsonKey(name: 'is_read') final bool isRead,
          @JsonKey(name: 'is_saved') final bool isSaved,
          @JsonKey(name: 'is_liked') final bool isLiked,
          @JsonKey(name: 'is_dismissed') final bool isDismissed,
          @JsonKey(name: 'recommendation_reason')
          final DigestRecommendationReason? recommendationReason}) =
      _$DigestItemImpl;

  factory _DigestItem.fromJson(Map<String, dynamic> json) =
      _$DigestItemImpl.fromJson;

  @override
  @JsonKey(name: 'content_id')
  String get contentId;
  @override
  String get title;
  @override
  String get url;
  @override
  @JsonKey(name: 'thumbnail_url')
  String? get thumbnailUrl;
  @override
  String? get description;
  @override
  List<String> get topics;
  @override
  @JsonKey(
      name: 'content_type',
      fromJson: _contentTypeFromJson,
      toJson: _contentTypeToJson)
  ContentType get contentType;
  @override
  @JsonKey(name: 'duration_seconds')
  int? get durationSeconds;
  @override
  @JsonKey(name: 'published_at')
  DateTime? get publishedAt;
  @override
  SourceMini? get source;
  @override
  int get rank;
  @override
  String get reason;
  @override
  @JsonKey(name: 'is_paid')
  bool get isPaid;
  @override
  @JsonKey(name: 'is_read')
  bool get isRead;
  @override
  @JsonKey(name: 'is_saved')
  bool get isSaved;
  @override
  @JsonKey(name: 'is_liked')
  bool get isLiked;
  @override
  @JsonKey(name: 'is_dismissed')
  bool get isDismissed;
  @override
  @JsonKey(name: 'recommendation_reason')
  DigestRecommendationReason? get recommendationReason;
  @override
  @JsonKey(ignore: true)
  _$$DigestItemImplCopyWith<_$DigestItemImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

DigestResponse _$DigestResponseFromJson(Map<String, dynamic> json) {
  return _DigestResponse.fromJson(json);
}

/// @nodoc
mixin _$DigestResponse {
  @JsonKey(name: 'digest_id')
  String get digestId => throw _privateConstructorUsedError;
  @JsonKey(name: 'user_id')
  String get userId => throw _privateConstructorUsedError;
  @JsonKey(name: 'target_date')
  DateTime get targetDate => throw _privateConstructorUsedError;
  @JsonKey(name: 'generated_at')
  DateTime get generatedAt => throw _privateConstructorUsedError;
  @JsonKey(defaultValue: 'pour_vous')
  String get mode => throw _privateConstructorUsedError;
  List<DigestItem> get items => throw _privateConstructorUsedError;
  @JsonKey(name: 'completion_threshold')
  int get completionThreshold => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_completed')
  bool get isCompleted => throw _privateConstructorUsedError;
  @JsonKey(name: 'completed_at')
  DateTime? get completedAt => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $DigestResponseCopyWith<DigestResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DigestResponseCopyWith<$Res> {
  factory $DigestResponseCopyWith(
          DigestResponse value, $Res Function(DigestResponse) then) =
      _$DigestResponseCopyWithImpl<$Res, DigestResponse>;
  @useResult
  $Res call(
      {@JsonKey(name: 'digest_id') String digestId,
      @JsonKey(name: 'user_id') String userId,
      @JsonKey(name: 'target_date') DateTime targetDate,
      @JsonKey(name: 'generated_at') DateTime generatedAt,
      @JsonKey(defaultValue: 'pour_vous') String mode,
      List<DigestItem> items,
      @JsonKey(name: 'completion_threshold') int completionThreshold,
      @JsonKey(name: 'is_completed') bool isCompleted,
      @JsonKey(name: 'completed_at') DateTime? completedAt});
}

/// @nodoc
class _$DigestResponseCopyWithImpl<$Res, $Val extends DigestResponse>
    implements $DigestResponseCopyWith<$Res> {
  _$DigestResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? digestId = null,
    Object? userId = null,
    Object? targetDate = null,
    Object? generatedAt = null,
    Object? mode = null,
    Object? items = null,
    Object? completionThreshold = null,
    Object? isCompleted = null,
    Object? completedAt = freezed,
  }) {
    return _then(_value.copyWith(
      digestId: null == digestId
          ? _value.digestId
          : digestId // ignore: cast_nullable_to_non_nullable
              as String,
      userId: null == userId
          ? _value.userId
          : userId // ignore: cast_nullable_to_non_nullable
              as String,
      targetDate: null == targetDate
          ? _value.targetDate
          : targetDate // ignore: cast_nullable_to_non_nullable
              as DateTime,
      generatedAt: null == generatedAt
          ? _value.generatedAt
          : generatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      mode: null == mode
          ? _value.mode
          : mode // ignore: cast_nullable_to_non_nullable
              as String,
      items: null == items
          ? _value.items
          : items // ignore: cast_nullable_to_non_nullable
              as List<DigestItem>,
      completionThreshold: null == completionThreshold
          ? _value.completionThreshold
          : completionThreshold // ignore: cast_nullable_to_non_nullable
              as int,
      isCompleted: null == isCompleted
          ? _value.isCompleted
          : isCompleted // ignore: cast_nullable_to_non_nullable
              as bool,
      completedAt: freezed == completedAt
          ? _value.completedAt
          : completedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$DigestResponseImplCopyWith<$Res>
    implements $DigestResponseCopyWith<$Res> {
  factory _$$DigestResponseImplCopyWith(_$DigestResponseImpl value,
          $Res Function(_$DigestResponseImpl) then) =
      __$$DigestResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'digest_id') String digestId,
      @JsonKey(name: 'user_id') String userId,
      @JsonKey(name: 'target_date') DateTime targetDate,
      @JsonKey(name: 'generated_at') DateTime generatedAt,
      @JsonKey(defaultValue: 'pour_vous') String mode,
      List<DigestItem> items,
      @JsonKey(name: 'completion_threshold') int completionThreshold,
      @JsonKey(name: 'is_completed') bool isCompleted,
      @JsonKey(name: 'completed_at') DateTime? completedAt});
}

/// @nodoc
class __$$DigestResponseImplCopyWithImpl<$Res>
    extends _$DigestResponseCopyWithImpl<$Res, _$DigestResponseImpl>
    implements _$$DigestResponseImplCopyWith<$Res> {
  __$$DigestResponseImplCopyWithImpl(
      _$DigestResponseImpl _value, $Res Function(_$DigestResponseImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? digestId = null,
    Object? userId = null,
    Object? targetDate = null,
    Object? generatedAt = null,
    Object? mode = null,
    Object? items = null,
    Object? completionThreshold = null,
    Object? isCompleted = null,
    Object? completedAt = freezed,
  }) {
    return _then(_$DigestResponseImpl(
      digestId: null == digestId
          ? _value.digestId
          : digestId // ignore: cast_nullable_to_non_nullable
              as String,
      userId: null == userId
          ? _value.userId
          : userId // ignore: cast_nullable_to_non_nullable
              as String,
      targetDate: null == targetDate
          ? _value.targetDate
          : targetDate // ignore: cast_nullable_to_non_nullable
              as DateTime,
      generatedAt: null == generatedAt
          ? _value.generatedAt
          : generatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      mode: null == mode
          ? _value.mode
          : mode // ignore: cast_nullable_to_non_nullable
              as String,
      items: null == items
          ? _value._items
          : items // ignore: cast_nullable_to_non_nullable
              as List<DigestItem>,
      completionThreshold: null == completionThreshold
          ? _value.completionThreshold
          : completionThreshold // ignore: cast_nullable_to_non_nullable
              as int,
      isCompleted: null == isCompleted
          ? _value.isCompleted
          : isCompleted // ignore: cast_nullable_to_non_nullable
              as bool,
      completedAt: freezed == completedAt
          ? _value.completedAt
          : completedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$DigestResponseImpl implements _DigestResponse {
  const _$DigestResponseImpl(
      {@JsonKey(name: 'digest_id') required this.digestId,
      @JsonKey(name: 'user_id') required this.userId,
      @JsonKey(name: 'target_date') required this.targetDate,
      @JsonKey(name: 'generated_at') required this.generatedAt,
      @JsonKey(defaultValue: 'pour_vous') this.mode = 'pour_vous',
      final List<DigestItem> items = const [],
      @JsonKey(name: 'completion_threshold') this.completionThreshold = 5,
      @JsonKey(name: 'is_completed') this.isCompleted = false,
      @JsonKey(name: 'completed_at') this.completedAt})
      : _items = items;

  factory _$DigestResponseImpl.fromJson(Map<String, dynamic> json) =>
      _$$DigestResponseImplFromJson(json);

  @override
  @JsonKey(name: 'digest_id')
  final String digestId;
  @override
  @JsonKey(name: 'user_id')
  final String userId;
  @override
  @JsonKey(name: 'target_date')
  final DateTime targetDate;
  @override
  @JsonKey(name: 'generated_at')
  final DateTime generatedAt;
  @override
  @JsonKey(defaultValue: 'pour_vous')
  final String mode;
  final List<DigestItem> _items;
  @override
  @JsonKey()
  List<DigestItem> get items {
    if (_items is EqualUnmodifiableListView) return _items;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_items);
  }

  @override
  @JsonKey(name: 'completion_threshold')
  final int completionThreshold;
  @override
  @JsonKey(name: 'is_completed')
  final bool isCompleted;
  @override
  @JsonKey(name: 'completed_at')
  final DateTime? completedAt;

  @override
  String toString() {
    return 'DigestResponse(digestId: $digestId, userId: $userId, targetDate: $targetDate, generatedAt: $generatedAt, mode: $mode, items: $items, completionThreshold: $completionThreshold, isCompleted: $isCompleted, completedAt: $completedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DigestResponseImpl &&
            (identical(other.digestId, digestId) ||
                other.digestId == digestId) &&
            (identical(other.userId, userId) || other.userId == userId) &&
            (identical(other.targetDate, targetDate) ||
                other.targetDate == targetDate) &&
            (identical(other.generatedAt, generatedAt) ||
                other.generatedAt == generatedAt) &&
            (identical(other.mode, mode) || other.mode == mode) &&
            const DeepCollectionEquality().equals(other._items, _items) &&
            (identical(other.completionThreshold, completionThreshold) ||
                other.completionThreshold == completionThreshold) &&
            (identical(other.isCompleted, isCompleted) ||
                other.isCompleted == isCompleted) &&
            (identical(other.completedAt, completedAt) ||
                other.completedAt == completedAt));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      digestId,
      userId,
      targetDate,
      generatedAt,
      mode,
      const DeepCollectionEquality().hash(_items),
      completionThreshold,
      isCompleted,
      completedAt);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$DigestResponseImplCopyWith<_$DigestResponseImpl> get copyWith =>
      __$$DigestResponseImplCopyWithImpl<_$DigestResponseImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$DigestResponseImplToJson(
      this,
    );
  }
}

abstract class _DigestResponse implements DigestResponse {
  const factory _DigestResponse(
          {@JsonKey(name: 'digest_id') required final String digestId,
          @JsonKey(name: 'user_id') required final String userId,
          @JsonKey(name: 'target_date') required final DateTime targetDate,
          @JsonKey(name: 'generated_at') required final DateTime generatedAt,
          @JsonKey(defaultValue: 'pour_vous') final String mode,
          final List<DigestItem> items,
          @JsonKey(name: 'completion_threshold') final int completionThreshold,
          @JsonKey(name: 'is_completed') final bool isCompleted,
          @JsonKey(name: 'completed_at') final DateTime? completedAt}) =
      _$DigestResponseImpl;

  factory _DigestResponse.fromJson(Map<String, dynamic> json) =
      _$DigestResponseImpl.fromJson;

  @override
  @JsonKey(name: 'digest_id')
  String get digestId;
  @override
  @JsonKey(name: 'user_id')
  String get userId;
  @override
  @JsonKey(name: 'target_date')
  DateTime get targetDate;
  @override
  @JsonKey(name: 'generated_at')
  DateTime get generatedAt;
  @override
  @JsonKey(defaultValue: 'pour_vous')
  String get mode;
  @override
  List<DigestItem> get items;
  @override
  @JsonKey(name: 'completion_threshold')
  int get completionThreshold;
  @override
  @JsonKey(name: 'is_completed')
  bool get isCompleted;
  @override
  @JsonKey(name: 'completed_at')
  DateTime? get completedAt;
  @override
  @JsonKey(ignore: true)
  _$$DigestResponseImplCopyWith<_$DigestResponseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

DigestCompletionResponse _$DigestCompletionResponseFromJson(
    Map<String, dynamic> json) {
  return _DigestCompletionResponse.fromJson(json);
}

/// @nodoc
mixin _$DigestCompletionResponse {
  bool get success => throw _privateConstructorUsedError;
  @JsonKey(name: 'digest_id')
  String get digestId => throw _privateConstructorUsedError;
  @JsonKey(name: 'completed_at')
  DateTime? get completedAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'articles_read')
  int get articlesRead => throw _privateConstructorUsedError;
  @JsonKey(name: 'articles_saved')
  int get articlesSaved => throw _privateConstructorUsedError;
  @JsonKey(name: 'articles_dismissed')
  int get articlesDismissed => throw _privateConstructorUsedError;
  @JsonKey(name: 'closure_time_seconds')
  int? get closureTimeSeconds => throw _privateConstructorUsedError;
  @JsonKey(name: 'closure_streak')
  int get closureStreak => throw _privateConstructorUsedError;
  @JsonKey(name: 'streak_message')
  String? get streakMessage => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $DigestCompletionResponseCopyWith<DigestCompletionResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DigestCompletionResponseCopyWith<$Res> {
  factory $DigestCompletionResponseCopyWith(DigestCompletionResponse value,
          $Res Function(DigestCompletionResponse) then) =
      _$DigestCompletionResponseCopyWithImpl<$Res, DigestCompletionResponse>;
  @useResult
  $Res call(
      {bool success,
      @JsonKey(name: 'digest_id') String digestId,
      @JsonKey(name: 'completed_at') DateTime? completedAt,
      @JsonKey(name: 'articles_read') int articlesRead,
      @JsonKey(name: 'articles_saved') int articlesSaved,
      @JsonKey(name: 'articles_dismissed') int articlesDismissed,
      @JsonKey(name: 'closure_time_seconds') int? closureTimeSeconds,
      @JsonKey(name: 'closure_streak') int closureStreak,
      @JsonKey(name: 'streak_message') String? streakMessage});
}

/// @nodoc
class _$DigestCompletionResponseCopyWithImpl<$Res,
        $Val extends DigestCompletionResponse>
    implements $DigestCompletionResponseCopyWith<$Res> {
  _$DigestCompletionResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? success = null,
    Object? digestId = null,
    Object? completedAt = freezed,
    Object? articlesRead = null,
    Object? articlesSaved = null,
    Object? articlesDismissed = null,
    Object? closureTimeSeconds = freezed,
    Object? closureStreak = null,
    Object? streakMessage = freezed,
  }) {
    return _then(_value.copyWith(
      success: null == success
          ? _value.success
          : success // ignore: cast_nullable_to_non_nullable
              as bool,
      digestId: null == digestId
          ? _value.digestId
          : digestId // ignore: cast_nullable_to_non_nullable
              as String,
      completedAt: freezed == completedAt
          ? _value.completedAt
          : completedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      articlesRead: null == articlesRead
          ? _value.articlesRead
          : articlesRead // ignore: cast_nullable_to_non_nullable
              as int,
      articlesSaved: null == articlesSaved
          ? _value.articlesSaved
          : articlesSaved // ignore: cast_nullable_to_non_nullable
              as int,
      articlesDismissed: null == articlesDismissed
          ? _value.articlesDismissed
          : articlesDismissed // ignore: cast_nullable_to_non_nullable
              as int,
      closureTimeSeconds: freezed == closureTimeSeconds
          ? _value.closureTimeSeconds
          : closureTimeSeconds // ignore: cast_nullable_to_non_nullable
              as int?,
      closureStreak: null == closureStreak
          ? _value.closureStreak
          : closureStreak // ignore: cast_nullable_to_non_nullable
              as int,
      streakMessage: freezed == streakMessage
          ? _value.streakMessage
          : streakMessage // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$DigestCompletionResponseImplCopyWith<$Res>
    implements $DigestCompletionResponseCopyWith<$Res> {
  factory _$$DigestCompletionResponseImplCopyWith(
          _$DigestCompletionResponseImpl value,
          $Res Function(_$DigestCompletionResponseImpl) then) =
      __$$DigestCompletionResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {bool success,
      @JsonKey(name: 'digest_id') String digestId,
      @JsonKey(name: 'completed_at') DateTime? completedAt,
      @JsonKey(name: 'articles_read') int articlesRead,
      @JsonKey(name: 'articles_saved') int articlesSaved,
      @JsonKey(name: 'articles_dismissed') int articlesDismissed,
      @JsonKey(name: 'closure_time_seconds') int? closureTimeSeconds,
      @JsonKey(name: 'closure_streak') int closureStreak,
      @JsonKey(name: 'streak_message') String? streakMessage});
}

/// @nodoc
class __$$DigestCompletionResponseImplCopyWithImpl<$Res>
    extends _$DigestCompletionResponseCopyWithImpl<$Res,
        _$DigestCompletionResponseImpl>
    implements _$$DigestCompletionResponseImplCopyWith<$Res> {
  __$$DigestCompletionResponseImplCopyWithImpl(
      _$DigestCompletionResponseImpl _value,
      $Res Function(_$DigestCompletionResponseImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? success = null,
    Object? digestId = null,
    Object? completedAt = freezed,
    Object? articlesRead = null,
    Object? articlesSaved = null,
    Object? articlesDismissed = null,
    Object? closureTimeSeconds = freezed,
    Object? closureStreak = null,
    Object? streakMessage = freezed,
  }) {
    return _then(_$DigestCompletionResponseImpl(
      success: null == success
          ? _value.success
          : success // ignore: cast_nullable_to_non_nullable
              as bool,
      digestId: null == digestId
          ? _value.digestId
          : digestId // ignore: cast_nullable_to_non_nullable
              as String,
      completedAt: freezed == completedAt
          ? _value.completedAt
          : completedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      articlesRead: null == articlesRead
          ? _value.articlesRead
          : articlesRead // ignore: cast_nullable_to_non_nullable
              as int,
      articlesSaved: null == articlesSaved
          ? _value.articlesSaved
          : articlesSaved // ignore: cast_nullable_to_non_nullable
              as int,
      articlesDismissed: null == articlesDismissed
          ? _value.articlesDismissed
          : articlesDismissed // ignore: cast_nullable_to_non_nullable
              as int,
      closureTimeSeconds: freezed == closureTimeSeconds
          ? _value.closureTimeSeconds
          : closureTimeSeconds // ignore: cast_nullable_to_non_nullable
              as int?,
      closureStreak: null == closureStreak
          ? _value.closureStreak
          : closureStreak // ignore: cast_nullable_to_non_nullable
              as int,
      streakMessage: freezed == streakMessage
          ? _value.streakMessage
          : streakMessage // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$DigestCompletionResponseImpl implements _DigestCompletionResponse {
  const _$DigestCompletionResponseImpl(
      {required this.success,
      @JsonKey(name: 'digest_id') required this.digestId,
      @JsonKey(name: 'completed_at') this.completedAt,
      @JsonKey(name: 'articles_read') this.articlesRead = 0,
      @JsonKey(name: 'articles_saved') this.articlesSaved = 0,
      @JsonKey(name: 'articles_dismissed') this.articlesDismissed = 0,
      @JsonKey(name: 'closure_time_seconds') this.closureTimeSeconds,
      @JsonKey(name: 'closure_streak') this.closureStreak = 0,
      @JsonKey(name: 'streak_message') this.streakMessage});

  factory _$DigestCompletionResponseImpl.fromJson(Map<String, dynamic> json) =>
      _$$DigestCompletionResponseImplFromJson(json);

  @override
  final bool success;
  @override
  @JsonKey(name: 'digest_id')
  final String digestId;
  @override
  @JsonKey(name: 'completed_at')
  final DateTime? completedAt;
  @override
  @JsonKey(name: 'articles_read')
  final int articlesRead;
  @override
  @JsonKey(name: 'articles_saved')
  final int articlesSaved;
  @override
  @JsonKey(name: 'articles_dismissed')
  final int articlesDismissed;
  @override
  @JsonKey(name: 'closure_time_seconds')
  final int? closureTimeSeconds;
  @override
  @JsonKey(name: 'closure_streak')
  final int closureStreak;
  @override
  @JsonKey(name: 'streak_message')
  final String? streakMessage;

  @override
  String toString() {
    return 'DigestCompletionResponse(success: $success, digestId: $digestId, completedAt: $completedAt, articlesRead: $articlesRead, articlesSaved: $articlesSaved, articlesDismissed: $articlesDismissed, closureTimeSeconds: $closureTimeSeconds, closureStreak: $closureStreak, streakMessage: $streakMessage)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DigestCompletionResponseImpl &&
            (identical(other.success, success) || other.success == success) &&
            (identical(other.digestId, digestId) ||
                other.digestId == digestId) &&
            (identical(other.completedAt, completedAt) ||
                other.completedAt == completedAt) &&
            (identical(other.articlesRead, articlesRead) ||
                other.articlesRead == articlesRead) &&
            (identical(other.articlesSaved, articlesSaved) ||
                other.articlesSaved == articlesSaved) &&
            (identical(other.articlesDismissed, articlesDismissed) ||
                other.articlesDismissed == articlesDismissed) &&
            (identical(other.closureTimeSeconds, closureTimeSeconds) ||
                other.closureTimeSeconds == closureTimeSeconds) &&
            (identical(other.closureStreak, closureStreak) ||
                other.closureStreak == closureStreak) &&
            (identical(other.streakMessage, streakMessage) ||
                other.streakMessage == streakMessage));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      success,
      digestId,
      completedAt,
      articlesRead,
      articlesSaved,
      articlesDismissed,
      closureTimeSeconds,
      closureStreak,
      streakMessage);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$DigestCompletionResponseImplCopyWith<_$DigestCompletionResponseImpl>
      get copyWith => __$$DigestCompletionResponseImplCopyWithImpl<
          _$DigestCompletionResponseImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$DigestCompletionResponseImplToJson(
      this,
    );
  }
}

abstract class _DigestCompletionResponse implements DigestCompletionResponse {
  const factory _DigestCompletionResponse(
          {required final bool success,
          @JsonKey(name: 'digest_id') required final String digestId,
          @JsonKey(name: 'completed_at') final DateTime? completedAt,
          @JsonKey(name: 'articles_read') final int articlesRead,
          @JsonKey(name: 'articles_saved') final int articlesSaved,
          @JsonKey(name: 'articles_dismissed') final int articlesDismissed,
          @JsonKey(name: 'closure_time_seconds') final int? closureTimeSeconds,
          @JsonKey(name: 'closure_streak') final int closureStreak,
          @JsonKey(name: 'streak_message') final String? streakMessage}) =
      _$DigestCompletionResponseImpl;

  factory _DigestCompletionResponse.fromJson(Map<String, dynamic> json) =
      _$DigestCompletionResponseImpl.fromJson;

  @override
  bool get success;
  @override
  @JsonKey(name: 'digest_id')
  String get digestId;
  @override
  @JsonKey(name: 'completed_at')
  DateTime? get completedAt;
  @override
  @JsonKey(name: 'articles_read')
  int get articlesRead;
  @override
  @JsonKey(name: 'articles_saved')
  int get articlesSaved;
  @override
  @JsonKey(name: 'articles_dismissed')
  int get articlesDismissed;
  @override
  @JsonKey(name: 'closure_time_seconds')
  int? get closureTimeSeconds;
  @override
  @JsonKey(name: 'closure_streak')
  int get closureStreak;
  @override
  @JsonKey(name: 'streak_message')
  String? get streakMessage;
  @override
  @JsonKey(ignore: true)
  _$$DigestCompletionResponseImplCopyWith<_$DigestCompletionResponseImpl>
      get copyWith => throw _privateConstructorUsedError;
}
