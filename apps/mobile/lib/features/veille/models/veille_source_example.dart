import 'package:flutter/foundation.dart';

@immutable
class VeilleSourceExample {
  final String title;
  final String url;
  final DateTime? publishedAt;
  final String excerpt;

  const VeilleSourceExample({
    required this.title,
    required this.url,
    required this.publishedAt,
    required this.excerpt,
  });

  factory VeilleSourceExample.fromJson(Map<String, dynamic> json) {
    return VeilleSourceExample(
      title: json['title'] as String,
      url: json['url'] as String,
      publishedAt: json['published_at'] != null
          ? DateTime.parse(json['published_at'] as String)
          : null,
      excerpt: (json['excerpt'] as String?) ?? '',
    );
  }
}
