import 'digest_models.dart';

/// Response from GET /api/digest/both — contains both normal and serein
/// digest variants plus the user's current serein preference.
class DualDigestResponse {
  final DigestResponse? normal;
  final DigestResponse? serein;
  final bool sereinEnabled;

  DualDigestResponse({
    this.normal,
    this.serein,
    required this.sereinEnabled,
  });

  factory DualDigestResponse.fromJson(Map<String, dynamic> json) {
    return DualDigestResponse(
      normal: json['normal'] != null
          ? DigestResponse.fromJson(json['normal'] as Map<String, dynamic>)
          : null,
      serein: json['serein'] != null
          ? DigestResponse.fromJson(json['serein'] as Map<String, dynamic>)
          : null,
      sereinEnabled: json['serein_enabled'] as bool? ?? false,
    );
  }
}
