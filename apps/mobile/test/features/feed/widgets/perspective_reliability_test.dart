import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/feed/repositories/feed_repository.dart'
    show PerspectiveData;
import 'package:facteur/features/feed/widgets/perspectives_bottom_sheet.dart';

void main() {
  Map<String, dynamic> base({String? reliability}) => {
        'title': 'Titre',
        'url': 'https://ex.com/a',
        'source_name': 'Le Monde',
        'source_domain': 'lemonde.fr',
        'bias_stance': 'center',
        if (reliability != null) 'reliability_score': reliability,
      };

  group('Perspective.fromJson reliability_score', () {
    test('parse high/low/mixed', () {
      expect(Perspective.fromJson(base(reliability: 'high')).reliabilityScore,
          'high');
      expect(Perspective.fromJson(base(reliability: 'low')).reliabilityScore,
          'low');
      expect(Perspective.fromJson(base(reliability: 'mixed')).reliabilityScore,
          'mixed');
    });

    test('normalise la casse', () {
      expect(Perspective.fromJson(base(reliability: 'HIGH')).reliabilityScore,
          'high');
    });

    test('défaut unknown quand absent', () {
      expect(Perspective.fromJson(base()).reliabilityScore, 'unknown');
    });
  });

  group('PerspectiveData.fromJson reliability_score', () {
    test('parse + défaut unknown', () {
      expect(
        PerspectiveData.fromJson(base(reliability: 'low')).reliabilityScore,
        'low',
      );
      expect(PerspectiveData.fromJson(base()).reliabilityScore, 'unknown');
    });
  });
}
