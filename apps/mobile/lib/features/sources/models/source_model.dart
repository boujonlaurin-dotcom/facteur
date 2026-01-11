enum SourceType {
  article,
  podcast,
  video,
  youtube,
}

class Source {
  final String id;
  final String name;
  final String? url;
  final SourceType type;
  final String? theme;
  final String? description;
  final String? logoUrl;
  final bool isCurated;
  final bool isCustom;
  final bool isTrusted;

  Source({
    required this.id,
    required this.name,
    this.url,
    required this.type,
    this.theme,
    this.description,
    this.logoUrl,
    this.isCurated = false,
    this.isCustom = false,
    this.isTrusted = false,
  });

  Source copyWith({
    String? id,
    String? name,
    String? url,
    SourceType? type,
    String? theme,
    String? description,
    String? logoUrl,
    bool? isCurated,
    bool? isCustom,
    bool? isTrusted,
  }) {
    return Source(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      type: type ?? this.type,
      theme: theme ?? this.theme,
      description: description ?? this.description,
      logoUrl: logoUrl ?? this.logoUrl,
      isCurated: isCurated ?? this.isCurated,
      isCustom: isCustom ?? this.isCustom,
      isTrusted: isTrusted ?? this.isTrusted,
    );
  }

  factory Source.fromJson(Map<String, dynamic> json) {
    return Source(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String?,
      type: SourceType.values.firstWhere(
        (e) => e.name == (json['type'] as String).toLowerCase(),
        orElse: () => SourceType.article,
      ),
      theme: json['theme'] as String?,
      description: json['description'] as String?,
      logoUrl: json['logo_url'] as String?,
      isCurated: json['is_curated'] as bool? ?? false,
      isCustom: json['is_custom'] as bool? ?? false,
      isTrusted: json['is_trusted'] as bool? ?? false,
    );
  }
}
