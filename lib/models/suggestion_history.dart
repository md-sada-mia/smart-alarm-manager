class SuggestionHistory {
  final int? id;
  final String title;
  final double latitude;
  final double longitude;
  final int usageCount;
  final DateTime lastUsedAt;

  SuggestionHistory({
    this.id,
    required this.title,
    required this.latitude,
    required this.longitude,
    this.usageCount = 1,
    required this.lastUsedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'latitude': latitude,
      'longitude': longitude,
      'usageCount': usageCount,
      'lastUsedAt': lastUsedAt.toIso8601String(),
    };
  }

  factory SuggestionHistory.fromMap(Map<String, dynamic> map) {
    return SuggestionHistory(
      id: map['id'],
      title: map['title'],
      latitude: map['latitude'],
      longitude: map['longitude'],
      usageCount: map['usageCount'],
      lastUsedAt: DateTime.parse(map['lastUsedAt']),
    );
  }
}
