class ChangelogEntry {
  const ChangelogEntry({required this.tag, required this.summary});

  final String tag;
  final String summary;

  factory ChangelogEntry.fromJson(Map<String, dynamic> json) {
    return ChangelogEntry(
      tag: json['tag'] as String,
      summary: json['summary'] as String,
    );
  }
}

class ChangelogRelease {
  const ChangelogRelease({
    required this.version,
    required this.date,
    required this.entries,
  });

  final String version;
  final String date;
  final List<ChangelogEntry> entries;

  factory ChangelogRelease.fromJson(Map<String, dynamic> json) {
    return ChangelogRelease(
      version: json['version'] as String,
      date: json['date'] as String,
      entries: (json['entries'] as List<dynamic>)
          .map((e) => ChangelogEntry.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}
