import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';

/// Learned algorithm profile: weights per theme/subtopic + source affinities.
class AlgorithmProfile {
  final Map<String, double> interestWeights;
  final Map<String, double> subtopicWeights;
  final Map<String, double> sourceAffinities;

  const AlgorithmProfile({
    required this.interestWeights,
    required this.subtopicWeights,
    required this.sourceAffinities,
  });

  factory AlgorithmProfile.fromJson(Map<String, dynamic> json) {
    return AlgorithmProfile(
      interestWeights: _toDoubleMap(json['interest_weights']),
      subtopicWeights: _toDoubleMap(json['subtopic_weights']),
      sourceAffinities: _toDoubleMap(json['source_affinities']),
    );
  }

  static Map<String, double> _toDoubleMap(dynamic raw) {
    if (raw == null) return {};
    return (raw as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, (v as num).toDouble()));
  }

  /// Normalize a learned weight (0.1-3.0) to usageWeight (0.0-1.0).
  double normalizeWeight(double weight) =>
      ((weight - 0.1) / 2.9).clamp(0.0, 1.0);
}

/// Fetches the user's algorithm profile from the backend.
final algorithmProfileProvider = FutureProvider<AlgorithmProfile>((ref) async {
  final client = ref.watch(apiClientProvider);
  final data = await client.get('users/algorithm-profile');
  return AlgorithmProfile.fromJson(data as Map<String, dynamic>);
});
