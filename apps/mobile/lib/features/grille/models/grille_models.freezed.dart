// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'grille_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

GrilleEssai _$GrilleEssaiFromJson(Map<String, dynamic> json) {
  return _GrilleEssai.fromJson(json);
}

/// @nodoc
mixin _$GrilleEssai {
  String get mot => throw _privateConstructorUsedError;
  List<String> get etats => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $GrilleEssaiCopyWith<GrilleEssai> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $GrilleEssaiCopyWith<$Res> {
  factory $GrilleEssaiCopyWith(
          GrilleEssai value, $Res Function(GrilleEssai) then) =
      _$GrilleEssaiCopyWithImpl<$Res, GrilleEssai>;
  @useResult
  $Res call({String mot, List<String> etats});
}

/// @nodoc
class _$GrilleEssaiCopyWithImpl<$Res, $Val extends GrilleEssai>
    implements $GrilleEssaiCopyWith<$Res> {
  _$GrilleEssaiCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? mot = null,
    Object? etats = null,
  }) {
    return _then(_value.copyWith(
      mot: null == mot
          ? _value.mot
          : mot // ignore: cast_nullable_to_non_nullable
              as String,
      etats: null == etats
          ? _value.etats
          : etats // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$GrilleEssaiImplCopyWith<$Res>
    implements $GrilleEssaiCopyWith<$Res> {
  factory _$$GrilleEssaiImplCopyWith(
          _$GrilleEssaiImpl value, $Res Function(_$GrilleEssaiImpl) then) =
      __$$GrilleEssaiImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String mot, List<String> etats});
}

/// @nodoc
class __$$GrilleEssaiImplCopyWithImpl<$Res>
    extends _$GrilleEssaiCopyWithImpl<$Res, _$GrilleEssaiImpl>
    implements _$$GrilleEssaiImplCopyWith<$Res> {
  __$$GrilleEssaiImplCopyWithImpl(
      _$GrilleEssaiImpl _value, $Res Function(_$GrilleEssaiImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? mot = null,
    Object? etats = null,
  }) {
    return _then(_$GrilleEssaiImpl(
      mot: null == mot
          ? _value.mot
          : mot // ignore: cast_nullable_to_non_nullable
              as String,
      etats: null == etats
          ? _value._etats
          : etats // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$GrilleEssaiImpl implements _GrilleEssai {
  const _$GrilleEssaiImpl(
      {required this.mot, required final List<String> etats})
      : _etats = etats;

  factory _$GrilleEssaiImpl.fromJson(Map<String, dynamic> json) =>
      _$$GrilleEssaiImplFromJson(json);

  @override
  final String mot;
  final List<String> _etats;
  @override
  List<String> get etats {
    if (_etats is EqualUnmodifiableListView) return _etats;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_etats);
  }

  @override
  String toString() {
    return 'GrilleEssai(mot: $mot, etats: $etats)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$GrilleEssaiImpl &&
            (identical(other.mot, mot) || other.mot == mot) &&
            const DeepCollectionEquality().equals(other._etats, _etats));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType, mot, const DeepCollectionEquality().hash(_etats));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$GrilleEssaiImplCopyWith<_$GrilleEssaiImpl> get copyWith =>
      __$$GrilleEssaiImplCopyWithImpl<_$GrilleEssaiImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$GrilleEssaiImplToJson(
      this,
    );
  }
}

abstract class _GrilleEssai implements GrilleEssai {
  const factory _GrilleEssai(
      {required final String mot,
      required final List<String> etats}) = _$GrilleEssaiImpl;

  factory _GrilleEssai.fromJson(Map<String, dynamic> json) =
      _$GrilleEssaiImpl.fromJson;

  @override
  String get mot;
  @override
  List<String> get etats;
  @override
  @JsonKey(ignore: true)
  _$$GrilleEssaiImplCopyWith<_$GrilleEssaiImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

GrilleTodayResponse _$GrilleTodayResponseFromJson(Map<String, dynamic> json) {
  return _GrilleTodayResponse.fromJson(json);
}

/// @nodoc
mixin _$GrilleTodayResponse {
  String get date => throw _privateConstructorUsedError;
  String get dateAffichee => throw _privateConstructorUsedError;
  String get dateCourt => throw _privateConstructorUsedError;
  String get numero => throw _privateConstructorUsedError;
  int get longueur => throw _privateConstructorUsedError;
  int get essaisMax => throw _privateConstructorUsedError;
  String get premiereLettre => throw _privateConstructorUsedError;
  String get indice => throw _privateConstructorUsedError;
  String get theme => throw _privateConstructorUsedError;
  String get statut => throw _privateConstructorUsedError;
  List<GrilleEssai> get essais => throw _privateConstructorUsedError;
  int get nbEssais => throw _privateConstructorUsedError;
  String? get mot => throw _privateConstructorUsedError;
  String? get pourquoi => throw _privateConstructorUsedError;
  int get streak => throw _privateConstructorUsedError;
  int get prochainMotDansSec => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $GrilleTodayResponseCopyWith<GrilleTodayResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $GrilleTodayResponseCopyWith<$Res> {
  factory $GrilleTodayResponseCopyWith(
          GrilleTodayResponse value, $Res Function(GrilleTodayResponse) then) =
      _$GrilleTodayResponseCopyWithImpl<$Res, GrilleTodayResponse>;
  @useResult
  $Res call(
      {String date,
      String dateAffichee,
      String dateCourt,
      String numero,
      int longueur,
      int essaisMax,
      String premiereLettre,
      String indice,
      String theme,
      String statut,
      List<GrilleEssai> essais,
      int nbEssais,
      String? mot,
      String? pourquoi,
      int streak,
      int prochainMotDansSec});
}

/// @nodoc
class _$GrilleTodayResponseCopyWithImpl<$Res, $Val extends GrilleTodayResponse>
    implements $GrilleTodayResponseCopyWith<$Res> {
  _$GrilleTodayResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? date = null,
    Object? dateAffichee = null,
    Object? dateCourt = null,
    Object? numero = null,
    Object? longueur = null,
    Object? essaisMax = null,
    Object? premiereLettre = null,
    Object? indice = null,
    Object? theme = null,
    Object? statut = null,
    Object? essais = null,
    Object? nbEssais = null,
    Object? mot = freezed,
    Object? pourquoi = freezed,
    Object? streak = null,
    Object? prochainMotDansSec = null,
  }) {
    return _then(_value.copyWith(
      date: null == date
          ? _value.date
          : date // ignore: cast_nullable_to_non_nullable
              as String,
      dateAffichee: null == dateAffichee
          ? _value.dateAffichee
          : dateAffichee // ignore: cast_nullable_to_non_nullable
              as String,
      dateCourt: null == dateCourt
          ? _value.dateCourt
          : dateCourt // ignore: cast_nullable_to_non_nullable
              as String,
      numero: null == numero
          ? _value.numero
          : numero // ignore: cast_nullable_to_non_nullable
              as String,
      longueur: null == longueur
          ? _value.longueur
          : longueur // ignore: cast_nullable_to_non_nullable
              as int,
      essaisMax: null == essaisMax
          ? _value.essaisMax
          : essaisMax // ignore: cast_nullable_to_non_nullable
              as int,
      premiereLettre: null == premiereLettre
          ? _value.premiereLettre
          : premiereLettre // ignore: cast_nullable_to_non_nullable
              as String,
      indice: null == indice
          ? _value.indice
          : indice // ignore: cast_nullable_to_non_nullable
              as String,
      theme: null == theme
          ? _value.theme
          : theme // ignore: cast_nullable_to_non_nullable
              as String,
      statut: null == statut
          ? _value.statut
          : statut // ignore: cast_nullable_to_non_nullable
              as String,
      essais: null == essais
          ? _value.essais
          : essais // ignore: cast_nullable_to_non_nullable
              as List<GrilleEssai>,
      nbEssais: null == nbEssais
          ? _value.nbEssais
          : nbEssais // ignore: cast_nullable_to_non_nullable
              as int,
      mot: freezed == mot
          ? _value.mot
          : mot // ignore: cast_nullable_to_non_nullable
              as String?,
      pourquoi: freezed == pourquoi
          ? _value.pourquoi
          : pourquoi // ignore: cast_nullable_to_non_nullable
              as String?,
      streak: null == streak
          ? _value.streak
          : streak // ignore: cast_nullable_to_non_nullable
              as int,
      prochainMotDansSec: null == prochainMotDansSec
          ? _value.prochainMotDansSec
          : prochainMotDansSec // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$GrilleTodayResponseImplCopyWith<$Res>
    implements $GrilleTodayResponseCopyWith<$Res> {
  factory _$$GrilleTodayResponseImplCopyWith(_$GrilleTodayResponseImpl value,
          $Res Function(_$GrilleTodayResponseImpl) then) =
      __$$GrilleTodayResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String date,
      String dateAffichee,
      String dateCourt,
      String numero,
      int longueur,
      int essaisMax,
      String premiereLettre,
      String indice,
      String theme,
      String statut,
      List<GrilleEssai> essais,
      int nbEssais,
      String? mot,
      String? pourquoi,
      int streak,
      int prochainMotDansSec});
}

/// @nodoc
class __$$GrilleTodayResponseImplCopyWithImpl<$Res>
    extends _$GrilleTodayResponseCopyWithImpl<$Res, _$GrilleTodayResponseImpl>
    implements _$$GrilleTodayResponseImplCopyWith<$Res> {
  __$$GrilleTodayResponseImplCopyWithImpl(_$GrilleTodayResponseImpl _value,
      $Res Function(_$GrilleTodayResponseImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? date = null,
    Object? dateAffichee = null,
    Object? dateCourt = null,
    Object? numero = null,
    Object? longueur = null,
    Object? essaisMax = null,
    Object? premiereLettre = null,
    Object? indice = null,
    Object? theme = null,
    Object? statut = null,
    Object? essais = null,
    Object? nbEssais = null,
    Object? mot = freezed,
    Object? pourquoi = freezed,
    Object? streak = null,
    Object? prochainMotDansSec = null,
  }) {
    return _then(_$GrilleTodayResponseImpl(
      date: null == date
          ? _value.date
          : date // ignore: cast_nullable_to_non_nullable
              as String,
      dateAffichee: null == dateAffichee
          ? _value.dateAffichee
          : dateAffichee // ignore: cast_nullable_to_non_nullable
              as String,
      dateCourt: null == dateCourt
          ? _value.dateCourt
          : dateCourt // ignore: cast_nullable_to_non_nullable
              as String,
      numero: null == numero
          ? _value.numero
          : numero // ignore: cast_nullable_to_non_nullable
              as String,
      longueur: null == longueur
          ? _value.longueur
          : longueur // ignore: cast_nullable_to_non_nullable
              as int,
      essaisMax: null == essaisMax
          ? _value.essaisMax
          : essaisMax // ignore: cast_nullable_to_non_nullable
              as int,
      premiereLettre: null == premiereLettre
          ? _value.premiereLettre
          : premiereLettre // ignore: cast_nullable_to_non_nullable
              as String,
      indice: null == indice
          ? _value.indice
          : indice // ignore: cast_nullable_to_non_nullable
              as String,
      theme: null == theme
          ? _value.theme
          : theme // ignore: cast_nullable_to_non_nullable
              as String,
      statut: null == statut
          ? _value.statut
          : statut // ignore: cast_nullable_to_non_nullable
              as String,
      essais: null == essais
          ? _value._essais
          : essais // ignore: cast_nullable_to_non_nullable
              as List<GrilleEssai>,
      nbEssais: null == nbEssais
          ? _value.nbEssais
          : nbEssais // ignore: cast_nullable_to_non_nullable
              as int,
      mot: freezed == mot
          ? _value.mot
          : mot // ignore: cast_nullable_to_non_nullable
              as String?,
      pourquoi: freezed == pourquoi
          ? _value.pourquoi
          : pourquoi // ignore: cast_nullable_to_non_nullable
              as String?,
      streak: null == streak
          ? _value.streak
          : streak // ignore: cast_nullable_to_non_nullable
              as int,
      prochainMotDansSec: null == prochainMotDansSec
          ? _value.prochainMotDansSec
          : prochainMotDansSec // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$GrilleTodayResponseImpl extends _GrilleTodayResponse {
  const _$GrilleTodayResponseImpl(
      {required this.date,
      required this.dateAffichee,
      required this.dateCourt,
      required this.numero,
      required this.longueur,
      required this.essaisMax,
      required this.premiereLettre,
      required this.indice,
      required this.theme,
      required this.statut,
      required final List<GrilleEssai> essais,
      required this.nbEssais,
      this.mot,
      this.pourquoi,
      required this.streak,
      required this.prochainMotDansSec})
      : _essais = essais,
        super._();

  factory _$GrilleTodayResponseImpl.fromJson(Map<String, dynamic> json) =>
      _$$GrilleTodayResponseImplFromJson(json);

  @override
  final String date;
  @override
  final String dateAffichee;
  @override
  final String dateCourt;
  @override
  final String numero;
  @override
  final int longueur;
  @override
  final int essaisMax;
  @override
  final String premiereLettre;
  @override
  final String indice;
  @override
  final String theme;
  @override
  final String statut;
  final List<GrilleEssai> _essais;
  @override
  List<GrilleEssai> get essais {
    if (_essais is EqualUnmodifiableListView) return _essais;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_essais);
  }

  @override
  final int nbEssais;
  @override
  final String? mot;
  @override
  final String? pourquoi;
  @override
  final int streak;
  @override
  final int prochainMotDansSec;

  @override
  String toString() {
    return 'GrilleTodayResponse(date: $date, dateAffichee: $dateAffichee, dateCourt: $dateCourt, numero: $numero, longueur: $longueur, essaisMax: $essaisMax, premiereLettre: $premiereLettre, indice: $indice, theme: $theme, statut: $statut, essais: $essais, nbEssais: $nbEssais, mot: $mot, pourquoi: $pourquoi, streak: $streak, prochainMotDansSec: $prochainMotDansSec)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$GrilleTodayResponseImpl &&
            (identical(other.date, date) || other.date == date) &&
            (identical(other.dateAffichee, dateAffichee) ||
                other.dateAffichee == dateAffichee) &&
            (identical(other.dateCourt, dateCourt) ||
                other.dateCourt == dateCourt) &&
            (identical(other.numero, numero) || other.numero == numero) &&
            (identical(other.longueur, longueur) ||
                other.longueur == longueur) &&
            (identical(other.essaisMax, essaisMax) ||
                other.essaisMax == essaisMax) &&
            (identical(other.premiereLettre, premiereLettre) ||
                other.premiereLettre == premiereLettre) &&
            (identical(other.indice, indice) || other.indice == indice) &&
            (identical(other.theme, theme) || other.theme == theme) &&
            (identical(other.statut, statut) || other.statut == statut) &&
            const DeepCollectionEquality().equals(other._essais, _essais) &&
            (identical(other.nbEssais, nbEssais) ||
                other.nbEssais == nbEssais) &&
            (identical(other.mot, mot) || other.mot == mot) &&
            (identical(other.pourquoi, pourquoi) ||
                other.pourquoi == pourquoi) &&
            (identical(other.streak, streak) || other.streak == streak) &&
            (identical(other.prochainMotDansSec, prochainMotDansSec) ||
                other.prochainMotDansSec == prochainMotDansSec));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      date,
      dateAffichee,
      dateCourt,
      numero,
      longueur,
      essaisMax,
      premiereLettre,
      indice,
      theme,
      statut,
      const DeepCollectionEquality().hash(_essais),
      nbEssais,
      mot,
      pourquoi,
      streak,
      prochainMotDansSec);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$GrilleTodayResponseImplCopyWith<_$GrilleTodayResponseImpl> get copyWith =>
      __$$GrilleTodayResponseImplCopyWithImpl<_$GrilleTodayResponseImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$GrilleTodayResponseImplToJson(
      this,
    );
  }
}

abstract class _GrilleTodayResponse extends GrilleTodayResponse {
  const factory _GrilleTodayResponse(
      {required final String date,
      required final String dateAffichee,
      required final String dateCourt,
      required final String numero,
      required final int longueur,
      required final int essaisMax,
      required final String premiereLettre,
      required final String indice,
      required final String theme,
      required final String statut,
      required final List<GrilleEssai> essais,
      required final int nbEssais,
      final String? mot,
      final String? pourquoi,
      required final int streak,
      required final int prochainMotDansSec}) = _$GrilleTodayResponseImpl;
  const _GrilleTodayResponse._() : super._();

  factory _GrilleTodayResponse.fromJson(Map<String, dynamic> json) =
      _$GrilleTodayResponseImpl.fromJson;

  @override
  String get date;
  @override
  String get dateAffichee;
  @override
  String get dateCourt;
  @override
  String get numero;
  @override
  int get longueur;
  @override
  int get essaisMax;
  @override
  String get premiereLettre;
  @override
  String get indice;
  @override
  String get theme;
  @override
  String get statut;
  @override
  List<GrilleEssai> get essais;
  @override
  int get nbEssais;
  @override
  String? get mot;
  @override
  String? get pourquoi;
  @override
  int get streak;
  @override
  int get prochainMotDansSec;
  @override
  @JsonKey(ignore: true)
  _$$GrilleTodayResponseImplCopyWith<_$GrilleTodayResponseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

GrilleGuessResponse _$GrilleGuessResponseFromJson(Map<String, dynamic> json) {
  return _GrilleGuessResponse.fromJson(json);
}

/// @nodoc
mixin _$GrilleGuessResponse {
  bool get valide => throw _privateConstructorUsedError;
  String? get raison => throw _privateConstructorUsedError;
  List<String>? get etats => throw _privateConstructorUsedError;
  String? get statut => throw _privateConstructorUsedError;
  int? get nbEssais => throw _privateConstructorUsedError;
  String? get mot => throw _privateConstructorUsedError;
  String? get pourquoi => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $GrilleGuessResponseCopyWith<GrilleGuessResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $GrilleGuessResponseCopyWith<$Res> {
  factory $GrilleGuessResponseCopyWith(
          GrilleGuessResponse value, $Res Function(GrilleGuessResponse) then) =
      _$GrilleGuessResponseCopyWithImpl<$Res, GrilleGuessResponse>;
  @useResult
  $Res call(
      {bool valide,
      String? raison,
      List<String>? etats,
      String? statut,
      int? nbEssais,
      String? mot,
      String? pourquoi});
}

/// @nodoc
class _$GrilleGuessResponseCopyWithImpl<$Res, $Val extends GrilleGuessResponse>
    implements $GrilleGuessResponseCopyWith<$Res> {
  _$GrilleGuessResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? valide = null,
    Object? raison = freezed,
    Object? etats = freezed,
    Object? statut = freezed,
    Object? nbEssais = freezed,
    Object? mot = freezed,
    Object? pourquoi = freezed,
  }) {
    return _then(_value.copyWith(
      valide: null == valide
          ? _value.valide
          : valide // ignore: cast_nullable_to_non_nullable
              as bool,
      raison: freezed == raison
          ? _value.raison
          : raison // ignore: cast_nullable_to_non_nullable
              as String?,
      etats: freezed == etats
          ? _value.etats
          : etats // ignore: cast_nullable_to_non_nullable
              as List<String>?,
      statut: freezed == statut
          ? _value.statut
          : statut // ignore: cast_nullable_to_non_nullable
              as String?,
      nbEssais: freezed == nbEssais
          ? _value.nbEssais
          : nbEssais // ignore: cast_nullable_to_non_nullable
              as int?,
      mot: freezed == mot
          ? _value.mot
          : mot // ignore: cast_nullable_to_non_nullable
              as String?,
      pourquoi: freezed == pourquoi
          ? _value.pourquoi
          : pourquoi // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$GrilleGuessResponseImplCopyWith<$Res>
    implements $GrilleGuessResponseCopyWith<$Res> {
  factory _$$GrilleGuessResponseImplCopyWith(_$GrilleGuessResponseImpl value,
          $Res Function(_$GrilleGuessResponseImpl) then) =
      __$$GrilleGuessResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {bool valide,
      String? raison,
      List<String>? etats,
      String? statut,
      int? nbEssais,
      String? mot,
      String? pourquoi});
}

/// @nodoc
class __$$GrilleGuessResponseImplCopyWithImpl<$Res>
    extends _$GrilleGuessResponseCopyWithImpl<$Res, _$GrilleGuessResponseImpl>
    implements _$$GrilleGuessResponseImplCopyWith<$Res> {
  __$$GrilleGuessResponseImplCopyWithImpl(_$GrilleGuessResponseImpl _value,
      $Res Function(_$GrilleGuessResponseImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? valide = null,
    Object? raison = freezed,
    Object? etats = freezed,
    Object? statut = freezed,
    Object? nbEssais = freezed,
    Object? mot = freezed,
    Object? pourquoi = freezed,
  }) {
    return _then(_$GrilleGuessResponseImpl(
      valide: null == valide
          ? _value.valide
          : valide // ignore: cast_nullable_to_non_nullable
              as bool,
      raison: freezed == raison
          ? _value.raison
          : raison // ignore: cast_nullable_to_non_nullable
              as String?,
      etats: freezed == etats
          ? _value._etats
          : etats // ignore: cast_nullable_to_non_nullable
              as List<String>?,
      statut: freezed == statut
          ? _value.statut
          : statut // ignore: cast_nullable_to_non_nullable
              as String?,
      nbEssais: freezed == nbEssais
          ? _value.nbEssais
          : nbEssais // ignore: cast_nullable_to_non_nullable
              as int?,
      mot: freezed == mot
          ? _value.mot
          : mot // ignore: cast_nullable_to_non_nullable
              as String?,
      pourquoi: freezed == pourquoi
          ? _value.pourquoi
          : pourquoi // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$GrilleGuessResponseImpl extends _GrilleGuessResponse {
  const _$GrilleGuessResponseImpl(
      {required this.valide,
      this.raison,
      final List<String>? etats,
      this.statut,
      this.nbEssais,
      this.mot,
      this.pourquoi})
      : _etats = etats,
        super._();

  factory _$GrilleGuessResponseImpl.fromJson(Map<String, dynamic> json) =>
      _$$GrilleGuessResponseImplFromJson(json);

  @override
  final bool valide;
  @override
  final String? raison;
  final List<String>? _etats;
  @override
  List<String>? get etats {
    final value = _etats;
    if (value == null) return null;
    if (_etats is EqualUnmodifiableListView) return _etats;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

  @override
  final String? statut;
  @override
  final int? nbEssais;
  @override
  final String? mot;
  @override
  final String? pourquoi;

  @override
  String toString() {
    return 'GrilleGuessResponse(valide: $valide, raison: $raison, etats: $etats, statut: $statut, nbEssais: $nbEssais, mot: $mot, pourquoi: $pourquoi)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$GrilleGuessResponseImpl &&
            (identical(other.valide, valide) || other.valide == valide) &&
            (identical(other.raison, raison) || other.raison == raison) &&
            const DeepCollectionEquality().equals(other._etats, _etats) &&
            (identical(other.statut, statut) || other.statut == statut) &&
            (identical(other.nbEssais, nbEssais) ||
                other.nbEssais == nbEssais) &&
            (identical(other.mot, mot) || other.mot == mot) &&
            (identical(other.pourquoi, pourquoi) ||
                other.pourquoi == pourquoi));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      valide,
      raison,
      const DeepCollectionEquality().hash(_etats),
      statut,
      nbEssais,
      mot,
      pourquoi);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$GrilleGuessResponseImplCopyWith<_$GrilleGuessResponseImpl> get copyWith =>
      __$$GrilleGuessResponseImplCopyWithImpl<_$GrilleGuessResponseImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$GrilleGuessResponseImplToJson(
      this,
    );
  }
}

abstract class _GrilleGuessResponse extends GrilleGuessResponse {
  const factory _GrilleGuessResponse(
      {required final bool valide,
      final String? raison,
      final List<String>? etats,
      final String? statut,
      final int? nbEssais,
      final String? mot,
      final String? pourquoi}) = _$GrilleGuessResponseImpl;
  const _GrilleGuessResponse._() : super._();

  factory _GrilleGuessResponse.fromJson(Map<String, dynamic> json) =
      _$GrilleGuessResponseImpl.fromJson;

  @override
  bool get valide;
  @override
  String? get raison;
  @override
  List<String>? get etats;
  @override
  String? get statut;
  @override
  int? get nbEssais;
  @override
  String? get mot;
  @override
  String? get pourquoi;
  @override
  @JsonKey(ignore: true)
  _$$GrilleGuessResponseImplCopyWith<_$GrilleGuessResponseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

GrilleDistributionItem _$GrilleDistributionItemFromJson(
    Map<String, dynamic> json) {
  return _GrilleDistributionItem.fromJson(json);
}

/// @nodoc
mixin _$GrilleDistributionItem {
  @JsonKey(fromJson: _scoreToString)
  String get score => throw _privateConstructorUsedError;
  int get pct => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $GrilleDistributionItemCopyWith<GrilleDistributionItem> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $GrilleDistributionItemCopyWith<$Res> {
  factory $GrilleDistributionItemCopyWith(GrilleDistributionItem value,
          $Res Function(GrilleDistributionItem) then) =
      _$GrilleDistributionItemCopyWithImpl<$Res, GrilleDistributionItem>;
  @useResult
  $Res call({@JsonKey(fromJson: _scoreToString) String score, int pct});
}

/// @nodoc
class _$GrilleDistributionItemCopyWithImpl<$Res,
        $Val extends GrilleDistributionItem>
    implements $GrilleDistributionItemCopyWith<$Res> {
  _$GrilleDistributionItemCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? score = null,
    Object? pct = null,
  }) {
    return _then(_value.copyWith(
      score: null == score
          ? _value.score
          : score // ignore: cast_nullable_to_non_nullable
              as String,
      pct: null == pct
          ? _value.pct
          : pct // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$GrilleDistributionItemImplCopyWith<$Res>
    implements $GrilleDistributionItemCopyWith<$Res> {
  factory _$$GrilleDistributionItemImplCopyWith(
          _$GrilleDistributionItemImpl value,
          $Res Function(_$GrilleDistributionItemImpl) then) =
      __$$GrilleDistributionItemImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({@JsonKey(fromJson: _scoreToString) String score, int pct});
}

/// @nodoc
class __$$GrilleDistributionItemImplCopyWithImpl<$Res>
    extends _$GrilleDistributionItemCopyWithImpl<$Res,
        _$GrilleDistributionItemImpl>
    implements _$$GrilleDistributionItemImplCopyWith<$Res> {
  __$$GrilleDistributionItemImplCopyWithImpl(
      _$GrilleDistributionItemImpl _value,
      $Res Function(_$GrilleDistributionItemImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? score = null,
    Object? pct = null,
  }) {
    return _then(_$GrilleDistributionItemImpl(
      score: null == score
          ? _value.score
          : score // ignore: cast_nullable_to_non_nullable
              as String,
      pct: null == pct
          ? _value.pct
          : pct // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$GrilleDistributionItemImpl extends _GrilleDistributionItem {
  const _$GrilleDistributionItemImpl(
      {@JsonKey(fromJson: _scoreToString) required this.score,
      required this.pct})
      : super._();

  factory _$GrilleDistributionItemImpl.fromJson(Map<String, dynamic> json) =>
      _$$GrilleDistributionItemImplFromJson(json);

  @override
  @JsonKey(fromJson: _scoreToString)
  final String score;
  @override
  final int pct;

  @override
  String toString() {
    return 'GrilleDistributionItem(score: $score, pct: $pct)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$GrilleDistributionItemImpl &&
            (identical(other.score, score) || other.score == score) &&
            (identical(other.pct, pct) || other.pct == pct));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, score, pct);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$GrilleDistributionItemImplCopyWith<_$GrilleDistributionItemImpl>
      get copyWith => __$$GrilleDistributionItemImplCopyWithImpl<
          _$GrilleDistributionItemImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$GrilleDistributionItemImplToJson(
      this,
    );
  }
}

abstract class _GrilleDistributionItem extends GrilleDistributionItem {
  const factory _GrilleDistributionItem(
      {@JsonKey(fromJson: _scoreToString) required final String score,
      required final int pct}) = _$GrilleDistributionItemImpl;
  const _GrilleDistributionItem._() : super._();

  factory _GrilleDistributionItem.fromJson(Map<String, dynamic> json) =
      _$GrilleDistributionItemImpl.fromJson;

  @override
  @JsonKey(fromJson: _scoreToString)
  String get score;
  @override
  int get pct;
  @override
  @JsonKey(ignore: true)
  _$$GrilleDistributionItemImplCopyWith<_$GrilleDistributionItemImpl>
      get copyWith => throw _privateConstructorUsedError;
}

GrilleQuartierItem _$GrilleQuartierItemFromJson(Map<String, dynamic> json) {
  return _GrilleQuartierItem.fromJson(json);
}

/// @nodoc
mixin _$GrilleQuartierItem {
  String get initiales => throw _privateConstructorUsedError;
  @JsonKey(fromJson: _scoreToString)
  String get score => throw _privateConstructorUsedError;
  int get rang => throw _privateConstructorUsedError;
  bool get moi => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $GrilleQuartierItemCopyWith<GrilleQuartierItem> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $GrilleQuartierItemCopyWith<$Res> {
  factory $GrilleQuartierItemCopyWith(
          GrilleQuartierItem value, $Res Function(GrilleQuartierItem) then) =
      _$GrilleQuartierItemCopyWithImpl<$Res, GrilleQuartierItem>;
  @useResult
  $Res call(
      {String initiales,
      @JsonKey(fromJson: _scoreToString) String score,
      int rang,
      bool moi});
}

/// @nodoc
class _$GrilleQuartierItemCopyWithImpl<$Res, $Val extends GrilleQuartierItem>
    implements $GrilleQuartierItemCopyWith<$Res> {
  _$GrilleQuartierItemCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? initiales = null,
    Object? score = null,
    Object? rang = null,
    Object? moi = null,
  }) {
    return _then(_value.copyWith(
      initiales: null == initiales
          ? _value.initiales
          : initiales // ignore: cast_nullable_to_non_nullable
              as String,
      score: null == score
          ? _value.score
          : score // ignore: cast_nullable_to_non_nullable
              as String,
      rang: null == rang
          ? _value.rang
          : rang // ignore: cast_nullable_to_non_nullable
              as int,
      moi: null == moi
          ? _value.moi
          : moi // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$GrilleQuartierItemImplCopyWith<$Res>
    implements $GrilleQuartierItemCopyWith<$Res> {
  factory _$$GrilleQuartierItemImplCopyWith(_$GrilleQuartierItemImpl value,
          $Res Function(_$GrilleQuartierItemImpl) then) =
      __$$GrilleQuartierItemImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String initiales,
      @JsonKey(fromJson: _scoreToString) String score,
      int rang,
      bool moi});
}

/// @nodoc
class __$$GrilleQuartierItemImplCopyWithImpl<$Res>
    extends _$GrilleQuartierItemCopyWithImpl<$Res, _$GrilleQuartierItemImpl>
    implements _$$GrilleQuartierItemImplCopyWith<$Res> {
  __$$GrilleQuartierItemImplCopyWithImpl(_$GrilleQuartierItemImpl _value,
      $Res Function(_$GrilleQuartierItemImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? initiales = null,
    Object? score = null,
    Object? rang = null,
    Object? moi = null,
  }) {
    return _then(_$GrilleQuartierItemImpl(
      initiales: null == initiales
          ? _value.initiales
          : initiales // ignore: cast_nullable_to_non_nullable
              as String,
      score: null == score
          ? _value.score
          : score // ignore: cast_nullable_to_non_nullable
              as String,
      rang: null == rang
          ? _value.rang
          : rang // ignore: cast_nullable_to_non_nullable
              as int,
      moi: null == moi
          ? _value.moi
          : moi // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$GrilleQuartierItemImpl extends _GrilleQuartierItem {
  const _$GrilleQuartierItemImpl(
      {required this.initiales,
      @JsonKey(fromJson: _scoreToString) required this.score,
      required this.rang,
      this.moi = false})
      : super._();

  factory _$GrilleQuartierItemImpl.fromJson(Map<String, dynamic> json) =>
      _$$GrilleQuartierItemImplFromJson(json);

  @override
  final String initiales;
  @override
  @JsonKey(fromJson: _scoreToString)
  final String score;
  @override
  final int rang;
  @override
  @JsonKey()
  final bool moi;

  @override
  String toString() {
    return 'GrilleQuartierItem(initiales: $initiales, score: $score, rang: $rang, moi: $moi)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$GrilleQuartierItemImpl &&
            (identical(other.initiales, initiales) ||
                other.initiales == initiales) &&
            (identical(other.score, score) || other.score == score) &&
            (identical(other.rang, rang) || other.rang == rang) &&
            (identical(other.moi, moi) || other.moi == moi));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, initiales, score, rang, moi);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$GrilleQuartierItemImplCopyWith<_$GrilleQuartierItemImpl> get copyWith =>
      __$$GrilleQuartierItemImplCopyWithImpl<_$GrilleQuartierItemImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$GrilleQuartierItemImplToJson(
      this,
    );
  }
}

abstract class _GrilleQuartierItem extends GrilleQuartierItem {
  const factory _GrilleQuartierItem(
      {required final String initiales,
      @JsonKey(fromJson: _scoreToString) required final String score,
      required final int rang,
      final bool moi}) = _$GrilleQuartierItemImpl;
  const _GrilleQuartierItem._() : super._();

  factory _GrilleQuartierItem.fromJson(Map<String, dynamic> json) =
      _$GrilleQuartierItemImpl.fromJson;

  @override
  String get initiales;
  @override
  @JsonKey(fromJson: _scoreToString)
  String get score;
  @override
  int get rang;
  @override
  bool get moi;
  @override
  @JsonKey(ignore: true)
  _$$GrilleQuartierItemImplCopyWith<_$GrilleQuartierItemImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

GrilleLeaderboardResponse _$GrilleLeaderboardResponseFromJson(
    Map<String, dynamic> json) {
  return _GrilleLeaderboardResponse.fromJson(json);
}

/// @nodoc
mixin _$GrilleLeaderboardResponse {
  int get percentile => throw _privateConstructorUsedError;
  int get joueurs => throw _privateConstructorUsedError;
  @JsonKey(fromJson: _scoreToString)
  String get monScore => throw _privateConstructorUsedError;
  List<GrilleDistributionItem> get distribution =>
      throw _privateConstructorUsedError;
  List<GrilleQuartierItem> get quartier => throw _privateConstructorUsedError;
  int get streak => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $GrilleLeaderboardResponseCopyWith<GrilleLeaderboardResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $GrilleLeaderboardResponseCopyWith<$Res> {
  factory $GrilleLeaderboardResponseCopyWith(GrilleLeaderboardResponse value,
          $Res Function(GrilleLeaderboardResponse) then) =
      _$GrilleLeaderboardResponseCopyWithImpl<$Res, GrilleLeaderboardResponse>;
  @useResult
  $Res call(
      {int percentile,
      int joueurs,
      @JsonKey(fromJson: _scoreToString) String monScore,
      List<GrilleDistributionItem> distribution,
      List<GrilleQuartierItem> quartier,
      int streak});
}

/// @nodoc
class _$GrilleLeaderboardResponseCopyWithImpl<$Res,
        $Val extends GrilleLeaderboardResponse>
    implements $GrilleLeaderboardResponseCopyWith<$Res> {
  _$GrilleLeaderboardResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? percentile = null,
    Object? joueurs = null,
    Object? monScore = null,
    Object? distribution = null,
    Object? quartier = null,
    Object? streak = null,
  }) {
    return _then(_value.copyWith(
      percentile: null == percentile
          ? _value.percentile
          : percentile // ignore: cast_nullable_to_non_nullable
              as int,
      joueurs: null == joueurs
          ? _value.joueurs
          : joueurs // ignore: cast_nullable_to_non_nullable
              as int,
      monScore: null == monScore
          ? _value.monScore
          : monScore // ignore: cast_nullable_to_non_nullable
              as String,
      distribution: null == distribution
          ? _value.distribution
          : distribution // ignore: cast_nullable_to_non_nullable
              as List<GrilleDistributionItem>,
      quartier: null == quartier
          ? _value.quartier
          : quartier // ignore: cast_nullable_to_non_nullable
              as List<GrilleQuartierItem>,
      streak: null == streak
          ? _value.streak
          : streak // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$GrilleLeaderboardResponseImplCopyWith<$Res>
    implements $GrilleLeaderboardResponseCopyWith<$Res> {
  factory _$$GrilleLeaderboardResponseImplCopyWith(
          _$GrilleLeaderboardResponseImpl value,
          $Res Function(_$GrilleLeaderboardResponseImpl) then) =
      __$$GrilleLeaderboardResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {int percentile,
      int joueurs,
      @JsonKey(fromJson: _scoreToString) String monScore,
      List<GrilleDistributionItem> distribution,
      List<GrilleQuartierItem> quartier,
      int streak});
}

/// @nodoc
class __$$GrilleLeaderboardResponseImplCopyWithImpl<$Res>
    extends _$GrilleLeaderboardResponseCopyWithImpl<$Res,
        _$GrilleLeaderboardResponseImpl>
    implements _$$GrilleLeaderboardResponseImplCopyWith<$Res> {
  __$$GrilleLeaderboardResponseImplCopyWithImpl(
      _$GrilleLeaderboardResponseImpl _value,
      $Res Function(_$GrilleLeaderboardResponseImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? percentile = null,
    Object? joueurs = null,
    Object? monScore = null,
    Object? distribution = null,
    Object? quartier = null,
    Object? streak = null,
  }) {
    return _then(_$GrilleLeaderboardResponseImpl(
      percentile: null == percentile
          ? _value.percentile
          : percentile // ignore: cast_nullable_to_non_nullable
              as int,
      joueurs: null == joueurs
          ? _value.joueurs
          : joueurs // ignore: cast_nullable_to_non_nullable
              as int,
      monScore: null == monScore
          ? _value.monScore
          : monScore // ignore: cast_nullable_to_non_nullable
              as String,
      distribution: null == distribution
          ? _value._distribution
          : distribution // ignore: cast_nullable_to_non_nullable
              as List<GrilleDistributionItem>,
      quartier: null == quartier
          ? _value._quartier
          : quartier // ignore: cast_nullable_to_non_nullable
              as List<GrilleQuartierItem>,
      streak: null == streak
          ? _value.streak
          : streak // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$GrilleLeaderboardResponseImpl extends _GrilleLeaderboardResponse {
  const _$GrilleLeaderboardResponseImpl(
      {required this.percentile,
      required this.joueurs,
      @JsonKey(fromJson: _scoreToString) required this.monScore,
      required final List<GrilleDistributionItem> distribution,
      required final List<GrilleQuartierItem> quartier,
      required this.streak})
      : _distribution = distribution,
        _quartier = quartier,
        super._();

  factory _$GrilleLeaderboardResponseImpl.fromJson(Map<String, dynamic> json) =>
      _$$GrilleLeaderboardResponseImplFromJson(json);

  @override
  final int percentile;
  @override
  final int joueurs;
  @override
  @JsonKey(fromJson: _scoreToString)
  final String monScore;
  final List<GrilleDistributionItem> _distribution;
  @override
  List<GrilleDistributionItem> get distribution {
    if (_distribution is EqualUnmodifiableListView) return _distribution;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_distribution);
  }

  final List<GrilleQuartierItem> _quartier;
  @override
  List<GrilleQuartierItem> get quartier {
    if (_quartier is EqualUnmodifiableListView) return _quartier;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_quartier);
  }

  @override
  final int streak;

  @override
  String toString() {
    return 'GrilleLeaderboardResponse(percentile: $percentile, joueurs: $joueurs, monScore: $monScore, distribution: $distribution, quartier: $quartier, streak: $streak)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$GrilleLeaderboardResponseImpl &&
            (identical(other.percentile, percentile) ||
                other.percentile == percentile) &&
            (identical(other.joueurs, joueurs) || other.joueurs == joueurs) &&
            (identical(other.monScore, monScore) ||
                other.monScore == monScore) &&
            const DeepCollectionEquality()
                .equals(other._distribution, _distribution) &&
            const DeepCollectionEquality().equals(other._quartier, _quartier) &&
            (identical(other.streak, streak) || other.streak == streak));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      percentile,
      joueurs,
      monScore,
      const DeepCollectionEquality().hash(_distribution),
      const DeepCollectionEquality().hash(_quartier),
      streak);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$GrilleLeaderboardResponseImplCopyWith<_$GrilleLeaderboardResponseImpl>
      get copyWith => __$$GrilleLeaderboardResponseImplCopyWithImpl<
          _$GrilleLeaderboardResponseImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$GrilleLeaderboardResponseImplToJson(
      this,
    );
  }
}

abstract class _GrilleLeaderboardResponse extends GrilleLeaderboardResponse {
  const factory _GrilleLeaderboardResponse(
      {required final int percentile,
      required final int joueurs,
      @JsonKey(fromJson: _scoreToString) required final String monScore,
      required final List<GrilleDistributionItem> distribution,
      required final List<GrilleQuartierItem> quartier,
      required final int streak}) = _$GrilleLeaderboardResponseImpl;
  const _GrilleLeaderboardResponse._() : super._();

  factory _GrilleLeaderboardResponse.fromJson(Map<String, dynamic> json) =
      _$GrilleLeaderboardResponseImpl.fromJson;

  @override
  int get percentile;
  @override
  int get joueurs;
  @override
  @JsonKey(fromJson: _scoreToString)
  String get monScore;
  @override
  List<GrilleDistributionItem> get distribution;
  @override
  List<GrilleQuartierItem> get quartier;
  @override
  int get streak;
  @override
  @JsonKey(ignore: true)
  _$$GrilleLeaderboardResponseImplCopyWith<_$GrilleLeaderboardResponseImpl>
      get copyWith => throw _privateConstructorUsedError;
}
