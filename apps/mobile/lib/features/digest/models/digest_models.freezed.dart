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

SourceMini _$SourceMiniFromJson(Map<String, dynamic> json) {
  return _SourceMini.fromJson(json);
}

/// @nodoc
mixin _$SourceMini {
  String get name => throw _privateConstructorUsedError;
  String? get logoUrl => throw _privateConstructorUsedError;
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
  $Res call({String name, String? logoUrl, String? theme});
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
    Object? name = null,
    Object? logoUrl = freezed,
    Object? theme = freezed,
  }) {
    return _then(_value.copyWith(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      logoUrl: freezed == logoUrl
          ? _value.logoUrl
          : logoUrl // ignore: cast_nullable_to_non_nullable
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
  $Res call({String name, String? logoUrl, String? theme});
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
    Object? name = null,
    Object? logoUrl = freezed,
    Object? theme = freezed,
  }) {
    return _then(_$SourceMiniImpl(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      logoUrl: freezed == logoUrl
          ? _value.logoUrl
          : logoUrl // ignore: cast_nullable_to_non_nullable
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
  const _$SourceMiniImpl({required this.name, this.logoUrl, this.theme});

  factory _$SourceMiniImpl.fromJson(Map<String, dynamic> json) =>
      _$$SourceMiniImplFromJson(json);

  @override
  final String name;
  @override
  final String? logoUrl;
  @override
  final String? theme;

  @override
  String toString() {
    return 'SourceMini(name: $name, logoUrl: $logoUrl, theme: $theme)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SourceMiniImpl &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.logoUrl, logoUrl) || other.logoUrl == logoUrl) &&
            (identical(other.theme, theme) || other.theme == theme));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, name, logoUrl, theme);

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
      {required final String name,
      final String? logoUrl,
      final String? theme}) = _$SourceMiniImpl;

  factory _SourceMini.fromJson(Map<String, dynamic> json) =
      _$SourceMiniImpl.fromJson;

  @override
  String get name;
  @override
  String? get logoUrl;
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
  String get contentId => throw _privateConstructorUsedError;
  String get title => throw _privateConstructorUsedError;
  String get url => throw _privateConstructorUsedError;
  String? get thumbnailUrl => throw _privateConstructorUsedError;
  String? get description => throw _privateConstructorUsedError;
  @JsonKey(fromJson: _contentTypeFromJson, toJson: _contentTypeToJson)
  ContentType get contentType => throw _privateConstructorUsedError;
  int? get durationSeconds => throw _privateConstructorUsedError;
  DateTime get publishedAt => throw _privateConstructorUsedError;
  SourceMini get source => throw _privateConstructorUsedError;
  int get rank => throw _privateConstructorUsedError;
  String get reason => throw _privateConstructorUsedError;
  bool get isRead => throw _privateConstructorUsedError;
  bool get isSaved => throw _privateConstructorUsedError;
  bool get isDismissed => throw _privateConstructorUsedError;

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
      {String contentId,
      String title,
      String url,
      String? thumbnailUrl,
      String? description,
      @JsonKey(fromJson: _contentTypeFromJson, toJson: _contentTypeToJson)
      ContentType contentType,
      int? durationSeconds,
      DateTime publishedAt,
      SourceMini source,
      int rank,
      String reason,
      bool isRead,
      bool isSaved,
      bool isDismissed});

  $SourceMiniCopyWith<$Res> get source;
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
    Object? contentType = null,
    Object? durationSeconds = freezed,
    Object? publishedAt = null,
    Object? source = null,
    Object? rank = null,
    Object? reason = null,
    Object? isRead = null,
    Object? isSaved = null,
    Object? isDismissed = null,
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
      contentType: null == contentType
          ? _value.contentType
          : contentType // ignore: cast_nullable_to_non_nullable
              as ContentType,
      durationSeconds: freezed == durationSeconds
          ? _value.durationSeconds
          : durationSeconds // ignore: cast_nullable_to_non_nullable
              as int?,
      publishedAt: null == publishedAt
          ? _value.publishedAt
          : publishedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      source: null == source
          ? _value.source
          : source // ignore: cast_nullable_to_non_nullable
              as SourceMini,
      rank: null == rank
          ? _value.rank
          : rank // ignore: cast_nullable_to_non_nullable
              as int,
      reason: null == reason
          ? _value.reason
          : reason // ignore: cast_nullable_to_non_nullable
              as String,
      isRead: null == isRead
          ? _value.isRead
          : isRead // ignore: cast_nullable_to_non_nullable
              as bool,
      isSaved: null == isSaved
          ? _value.isSaved
          : isSaved // ignore: cast_nullable_to_non_nullable
              as bool,
      isDismissed: null == isDismissed
          ? _value.isDismissed
          : isDismissed // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }

  @override
  @pragma('vm:prefer-inline')
  $SourceMiniCopyWith<$Res> get source {
    return $SourceMiniCopyWith<$Res>(_value.source, (value) {
      return _then(_value.copyWith(source: value) as $Val);
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
      {String contentId,
      String title,
      String url,
      String? thumbnailUrl,
      String? description,
      @JsonKey(fromJson: _contentTypeFromJson, toJson: _contentTypeToJson)
      ContentType contentType,
      int? durationSeconds,
      DateTime publishedAt,
      SourceMini source,
      int rank,
      String reason,
      bool isRead,
      bool isSaved,
      bool isDismissed});

  @override
  $SourceMiniCopyWith<$Res> get source;
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
    Object? contentType = null,
    Object? durationSeconds = freezed,
    Object? publishedAt = null,
    Object? source = null,
    Object? rank = null,
    Object? reason = null,
    Object? isRead = null,
    Object? isSaved = null,
    Object? isDismissed = null,
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
      contentType: null == contentType
          ? _value.contentType
          : contentType // ignore: cast_nullable_to_non_nullable
              as ContentType,
      durationSeconds: freezed == durationSeconds
          ? _value.durationSeconds
          : durationSeconds // ignore: cast_nullable_to_non_nullable
              as int?,
      publishedAt: null == publishedAt
          ? _value.publishedAt
          : publishedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      source: null == source
          ? _value.source
          : source // ignore: cast_nullable_to_non_nullable
              as SourceMini,
      rank: null == rank
          ? _value.rank
          : rank // ignore: cast_nullable_to_non_nullable
              as int,
      reason: null == reason
          ? _value.reason
          : reason // ignore: cast_nullable_to_non_nullable
              as String,
      isRead: null == isRead
          ? _value.isRead
          : isRead // ignore: cast_nullable_to_non_nullable
              as bool,
      isSaved: null == isSaved
          ? _value.isSaved
          : isSaved // ignore: cast_nullable_to_non_nullable
              as bool,
      isDismissed: null == isDismissed
          ? _value.isDismissed
          : isDismissed // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$DigestItemImpl implements _DigestItem {
  const _$DigestItemImpl(
      {required this.contentId,
      required this.title,
      required this.url,
      this.thumbnailUrl,
      this.description,
      @JsonKey(fromJson: _contentTypeFromJson, toJson: _contentTypeToJson)
      required this.contentType,
      this.durationSeconds,
      required this.publishedAt,
      required this.source,
      required this.rank,
      required this.reason,
      this.isRead = false,
      this.isSaved = false,
      this.isDismissed = false});

  factory _$DigestItemImpl.fromJson(Map<String, dynamic> json) =>
      _$$DigestItemImplFromJson(json);

  @override
  final String contentId;
  @override
  final String title;
  @override
  final String url;
  @override
  final String? thumbnailUrl;
  @override
  final String? description;
  @override
  @JsonKey(fromJson: _contentTypeFromJson, toJson: _contentTypeToJson)
  final ContentType contentType;
  @override
  final int? durationSeconds;
  @override
  final DateTime publishedAt;
  @override
  final SourceMini source;
  @override
  final int rank;
  @override
  final String reason;
  @override
  @JsonKey()
  final bool isRead;
  @override
  @JsonKey()
  final bool isSaved;
  @override
  @JsonKey()
  final bool isDismissed;

  @override
  String toString() {
    return 'DigestItem(contentId: $contentId, title: $title, url: $url, thumbnailUrl: $thumbnailUrl, description: $description, contentType: $contentType, durationSeconds: $durationSeconds, publishedAt: $publishedAt, source: $source, rank: $rank, reason: $reason, isRead: $isRead, isSaved: $isSaved, isDismissed: $isDismissed)';
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
            (identical(other.contentType, contentType) ||
                other.contentType == contentType) &&
            (identical(other.durationSeconds, durationSeconds) ||
                other.durationSeconds == durationSeconds) &&
            (identical(other.publishedAt, publishedAt) ||
                other.publishedAt == publishedAt) &&
            (identical(other.source, source) || other.source == source) &&
            (identical(other.rank, rank) || other.rank == rank) &&
            (identical(other.reason, reason) || other.reason == reason) &&
            (identical(other.isRead, isRead) || other.isRead == isRead) &&
            (identical(other.isSaved, isSaved) || other.isSaved == isSaved) &&
            (identical(other.isDismissed, isDismissed) ||
                other.isDismissed == isDismissed));
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
      contentType,
      durationSeconds,
      publishedAt,
      source,
      rank,
      reason,
      isRead,
      isSaved,
      isDismissed);

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
      {required final String contentId,
      required final String title,
      required final String url,
      final String? thumbnailUrl,
      final String? description,
      @JsonKey(fromJson: _contentTypeFromJson, toJson: _contentTypeToJson)
      required final ContentType contentType,
      final int? durationSeconds,
      required final DateTime publishedAt,
      required final SourceMini source,
      required final int rank,
      required final String reason,
      final bool isRead,
      final bool isSaved,
      final bool isDismissed}) = _$DigestItemImpl;

  factory _DigestItem.fromJson(Map<String, dynamic> json) =
      _$DigestItemImpl.fromJson;

  @override
  String get contentId;
  @override
  String get title;
  @override
  String get url;
  @override
  String? get thumbnailUrl;
  @override
  String? get description;
  @override
  @JsonKey(fromJson: _contentTypeFromJson, toJson: _contentTypeToJson)
  ContentType get contentType;
  @override
  int? get durationSeconds;
  @override
  DateTime get publishedAt;
  @override
  SourceMini get source;
  @override
  int get rank;
  @override
  String get reason;
  @override
  bool get isRead;
  @override
  bool get isSaved;
  @override
  bool get isDismissed;
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
  String get digestId => throw _privateConstructorUsedError;
  String get userId => throw _privateConstructorUsedError;
  DateTime get targetDate => throw _privateConstructorUsedError;
  DateTime get generatedAt => throw _privateConstructorUsedError;
  List<DigestItem> get items => throw _privateConstructorUsedError;
  bool get isCompleted => throw _privateConstructorUsedError;
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
      {String digestId,
      String userId,
      DateTime targetDate,
      DateTime generatedAt,
      List<DigestItem> items,
      bool isCompleted,
      DateTime? completedAt});
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
    Object? items = null,
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
      items: null == items
          ? _value.items
          : items // ignore: cast_nullable_to_non_nullable
              as List<DigestItem>,
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
      {String digestId,
      String userId,
      DateTime targetDate,
      DateTime generatedAt,
      List<DigestItem> items,
      bool isCompleted,
      DateTime? completedAt});
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
    Object? items = null,
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
      items: null == items
          ? _value._items
          : items // ignore: cast_nullable_to_non_nullable
              as List<DigestItem>,
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
      {required this.digestId,
      required this.userId,
      required this.targetDate,
      required this.generatedAt,
      required final List<DigestItem> items,
      this.isCompleted = false,
      this.completedAt})
      : _items = items;

  factory _$DigestResponseImpl.fromJson(Map<String, dynamic> json) =>
      _$$DigestResponseImplFromJson(json);

  @override
  final String digestId;
  @override
  final String userId;
  @override
  final DateTime targetDate;
  @override
  final DateTime generatedAt;
  final List<DigestItem> _items;
  @override
  List<DigestItem> get items {
    if (_items is EqualUnmodifiableListView) return _items;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_items);
  }

  @override
  @JsonKey()
  final bool isCompleted;
  @override
  final DateTime? completedAt;

  @override
  String toString() {
    return 'DigestResponse(digestId: $digestId, userId: $userId, targetDate: $targetDate, generatedAt: $generatedAt, items: $items, isCompleted: $isCompleted, completedAt: $completedAt)';
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
            const DeepCollectionEquality().equals(other._items, _items) &&
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
      const DeepCollectionEquality().hash(_items),
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
      {required final String digestId,
      required final String userId,
      required final DateTime targetDate,
      required final DateTime generatedAt,
      required final List<DigestItem> items,
      final bool isCompleted,
      final DateTime? completedAt}) = _$DigestResponseImpl;

  factory _DigestResponse.fromJson(Map<String, dynamic> json) =
      _$DigestResponseImpl.fromJson;

  @override
  String get digestId;
  @override
  String get userId;
  @override
  DateTime get targetDate;
  @override
  DateTime get generatedAt;
  @override
  List<DigestItem> get items;
  @override
  bool get isCompleted;
  @override
  DateTime? get completedAt;
  @override
  @JsonKey(ignore: true)
  _$$DigestResponseImplCopyWith<_$DigestResponseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
