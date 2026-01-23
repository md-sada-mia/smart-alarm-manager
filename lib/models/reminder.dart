// Reminder status enum
enum ReminderStatus { active, snoozed, completed, canceled }

class Reminder {
  final int? id;
  final String title;
  final String description;
  final double latitude;
  final double longitude;
  final double radius;
  final bool isActive;
  final ReminderStatus status;
  final DateTime? snoozeUntil; // When snoozed alarm will re-trigger
  final DateTime createdAt;
  final String? startTime; // "HH:mm" 24-hour format
  final String? endTime; // "HH:mm" 24-hour format
  final List<int>?
  days; // List of weekdays (1=Mon, 7=Sun). Null/Empty = Every day

  Reminder({
    this.id,
    required this.title,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.radius,
    this.isActive = true,
    this.status = ReminderStatus.active,
    this.snoozeUntil,
    required this.createdAt,
    this.startTime,
    this.endTime,
    this.days,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'radius': radius,
      'isActive': isActive ? 1 : 0,
      'status': status.name, // Store as string: 'active', 'snoozed', etc.
      'snoozeUntil': snoozeUntil?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'startTime': startTime,
      'endTime': endTime,
      'days': days?.join(','), // Store as comma-separated string "1,2,3"
    };
  }

  factory Reminder.fromMap(Map<String, dynamic> map) {
    // Parse status from string to enum
    ReminderStatus status = ReminderStatus.active;
    if (map['status'] != null) {
      try {
        status = ReminderStatus.values.firstWhere(
          (e) => e.name == map['status'],
          orElse: () => ReminderStatus.active,
        );
      } catch (e) {
        status = ReminderStatus.active;
      }
    }

    return Reminder(
      id: map['id'],
      title: map['title'],
      description: map['description'],
      latitude: map['latitude'],
      longitude: map['longitude'],
      radius: map['radius'],
      isActive: map['isActive'] == 1,
      status: status,
      snoozeUntil: map['snoozeUntil'] != null
          ? DateTime.parse(map['snoozeUntil'])
          : null,
      createdAt: DateTime.parse(map['createdAt']),
      startTime: map['startTime'],
      endTime: map['endTime'],
      days: map['days'] != null && (map['days'] as String).isNotEmpty
          ? (map['days'] as String).split(',').map((e) => int.parse(e)).toList()
          : null,
    );
  }

  Reminder copyWith({
    int? id,
    String? title,
    String? description,
    double? latitude,
    double? longitude,
    double? radius,
    bool? isActive,
    ReminderStatus? status,
    DateTime? snoozeUntil,
    bool clearSnooze = false, // Flag to clear snooze
    DateTime? createdAt,
    String? startTime,
    String? endTime,
    bool clearTimeRange = false,
    List<int>? days,
  }) {
    return Reminder(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radius: radius ?? this.radius,
      isActive: isActive ?? this.isActive,
      status: status ?? this.status,
      snoozeUntil: clearSnooze ? null : (snoozeUntil ?? this.snoozeUntil),
      createdAt: createdAt ?? this.createdAt,
      startTime: clearTimeRange ? null : (startTime ?? this.startTime),
      endTime: clearTimeRange ? null : (endTime ?? this.endTime),
      days: days ?? this.days,
    );
  }

  String get daysSummary {
    if (days == null || days!.isEmpty || days!.length == 7) return "Every Day";

    // Sort days
    final List<int> sorted = List.from(days!)..sort();

    if (days!.length == 2 && days!.contains(6) && days!.contains(7)) {
      return "Weekends";
    }
    if (days!.length == 5 && ![6, 7].any((d) => days!.contains(d))) {
      return "Weekdays";
    }

    final List<String> shortNames = [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];
    return sorted.map((d) => shortNames[d - 1]).join(", ");
  }
}
