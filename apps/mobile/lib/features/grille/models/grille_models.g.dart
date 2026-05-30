// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'grille_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$GrilleEssaiImpl _$$GrilleEssaiImplFromJson(Map<String, dynamic> json) =>
    _$GrilleEssaiImpl(
      mot: json['mot'] as String,
      etats: (json['etats'] as List<dynamic>).map((e) => e as String).toList(),
    );

Map<String, dynamic> _$$GrilleEssaiImplToJson(_$GrilleEssaiImpl instance) =>
    <String, dynamic>{
      'mot': instance.mot,
      'etats': instance.etats,
    };

_$GrilleTodayResponseImpl _$$GrilleTodayResponseImplFromJson(
        Map<String, dynamic> json) =>
    _$GrilleTodayResponseImpl(
      date: json['date'] as String,
      dateAffichee: json['dateAffichee'] as String,
      dateCourt: json['dateCourt'] as String,
      numero: json['numero'] as String,
      longueur: (json['longueur'] as num).toInt(),
      essaisMax: (json['essaisMax'] as num).toInt(),
      premiereLettre: json['premiereLettre'] as String,
      indice: json['indice'] as String,
      theme: json['theme'] as String,
      statut: json['statut'] as String,
      essais: (json['essais'] as List<dynamic>)
          .map((e) => GrilleEssai.fromJson(e as Map<String, dynamic>))
          .toList(),
      nbEssais: (json['nbEssais'] as num).toInt(),
      mot: json['mot'] as String?,
      pourquoi: json['pourquoi'] as String?,
      streak: (json['streak'] as num).toInt(),
      prochainMotDansSec: (json['prochainMotDansSec'] as num).toInt(),
    );

Map<String, dynamic> _$$GrilleTodayResponseImplToJson(
        _$GrilleTodayResponseImpl instance) =>
    <String, dynamic>{
      'date': instance.date,
      'dateAffichee': instance.dateAffichee,
      'dateCourt': instance.dateCourt,
      'numero': instance.numero,
      'longueur': instance.longueur,
      'essaisMax': instance.essaisMax,
      'premiereLettre': instance.premiereLettre,
      'indice': instance.indice,
      'theme': instance.theme,
      'statut': instance.statut,
      'essais': instance.essais,
      'nbEssais': instance.nbEssais,
      'mot': instance.mot,
      'pourquoi': instance.pourquoi,
      'streak': instance.streak,
      'prochainMotDansSec': instance.prochainMotDansSec,
    };

_$GrilleGuessResponseImpl _$$GrilleGuessResponseImplFromJson(
        Map<String, dynamic> json) =>
    _$GrilleGuessResponseImpl(
      valide: json['valide'] as bool,
      raison: json['raison'] as String?,
      etats:
          (json['etats'] as List<dynamic>?)?.map((e) => e as String).toList(),
      statut: json['statut'] as String?,
      nbEssais: (json['nbEssais'] as num?)?.toInt(),
      mot: json['mot'] as String?,
      pourquoi: json['pourquoi'] as String?,
    );

Map<String, dynamic> _$$GrilleGuessResponseImplToJson(
        _$GrilleGuessResponseImpl instance) =>
    <String, dynamic>{
      'valide': instance.valide,
      'raison': instance.raison,
      'etats': instance.etats,
      'statut': instance.statut,
      'nbEssais': instance.nbEssais,
      'mot': instance.mot,
      'pourquoi': instance.pourquoi,
    };

_$GrilleDistributionItemImpl _$$GrilleDistributionItemImplFromJson(
        Map<String, dynamic> json) =>
    _$GrilleDistributionItemImpl(
      score: _scoreToString(json['score']),
      pct: (json['pct'] as num).toInt(),
    );

Map<String, dynamic> _$$GrilleDistributionItemImplToJson(
        _$GrilleDistributionItemImpl instance) =>
    <String, dynamic>{
      'score': instance.score,
      'pct': instance.pct,
    };

_$GrilleQuartierItemImpl _$$GrilleQuartierItemImplFromJson(
        Map<String, dynamic> json) =>
    _$GrilleQuartierItemImpl(
      initiales: json['initiales'] as String,
      score: _scoreToString(json['score']),
      rang: (json['rang'] as num).toInt(),
      moi: json['moi'] as bool? ?? false,
    );

Map<String, dynamic> _$$GrilleQuartierItemImplToJson(
        _$GrilleQuartierItemImpl instance) =>
    <String, dynamic>{
      'initiales': instance.initiales,
      'score': instance.score,
      'rang': instance.rang,
      'moi': instance.moi,
    };

_$GrilleLeaderboardResponseImpl _$$GrilleLeaderboardResponseImplFromJson(
        Map<String, dynamic> json) =>
    _$GrilleLeaderboardResponseImpl(
      percentile: (json['percentile'] as num).toInt(),
      joueurs: (json['joueurs'] as num).toInt(),
      monScore: _scoreToString(json['monScore']),
      distribution: (json['distribution'] as List<dynamic>)
          .map(
              (e) => GrilleDistributionItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      quartier: (json['quartier'] as List<dynamic>)
          .map((e) => GrilleQuartierItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      streak: (json['streak'] as num).toInt(),
    );

Map<String, dynamic> _$$GrilleLeaderboardResponseImplToJson(
        _$GrilleLeaderboardResponseImpl instance) =>
    <String, dynamic>{
      'percentile': instance.percentile,
      'joueurs': instance.joueurs,
      'monScore': instance.monScore,
      'distribution': instance.distribution,
      'quartier': instance.quartier,
      'streak': instance.streak,
    };
