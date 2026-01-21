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
    );
  }
}
