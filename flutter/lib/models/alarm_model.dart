// lib/models/alarm_model.dart

enum RecurrenceType { once, hourly, daily, weekly, monthly }

class Alarm {
  final int? id;
  final String label;
  final DateTime scheduledAt; // The base date+time the user picked
  final RecurrenceType recurrence;
  final bool autoDelete;
  final bool isCompleted;
  final DateTime? isCompletedAt; // Last time user toggled completed
  final int notificationId; // flutter_local_notifications id
  final int hourlyInterval; // Custom hours for hourly recurrence (1-24)

  const Alarm({
    this.id,
    required this.label,
    required this.scheduledAt,
    required this.recurrence,
    required this.autoDelete,
    this.isCompleted = false,
    this.isCompletedAt,
    required this.notificationId,
    this.hourlyInterval = 1, // Default to 1 hour
  });

  // ── Serialisation ──────────────────────────────────────────────────────────

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'label': label,
      'scheduled_at': scheduledAt.toIso8601String(),
      'recurrence': recurrence.name,
      'auto_delete': autoDelete ? 1 : 0,
      'is_completed': isCompleted ? 1 : 0,
      'is_completed_at': isCompletedAt?.toIso8601String(),
      'notification_id': notificationId,
      'hourly_interval': hourlyInterval,
    };
  }

  factory Alarm.fromMap(Map<String, dynamic> map) {
    return Alarm(
      id: map['id'] as int?,
      label: map['label'] as String,
      scheduledAt: DateTime.parse(map['scheduled_at'] as String),
      recurrence: RecurrenceType.values.firstWhere(
        (e) => e.name == map['recurrence'],
        orElse: () => RecurrenceType.once,
      ),
      autoDelete: (map['auto_delete'] as int) == 1,
      isCompleted: (map['is_completed'] as int) == 1,
      isCompletedAt: map['is_completed_at'] != null
          ? DateTime.parse(map['is_completed_at'] as String)
          : null,
      notificationId: map['notification_id'] as int,
      hourlyInterval: map['hourly_interval'] as int? ?? 1,
    );
  }

  Alarm copyWith({
    int? id,
    String? label,
    DateTime? scheduledAt,
    RecurrenceType? recurrence,
    bool? autoDelete,
    bool? isCompleted,
    DateTime? isCompletedAt,
    int? notificationId,
    int? hourlyInterval,
  }) {
    return Alarm(
      id: id ?? this.id,
      label: label ?? this.label,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      recurrence: recurrence ?? this.recurrence,
      autoDelete: autoDelete ?? this.autoDelete,
      isCompleted: isCompleted ?? this.isCompleted,
      isCompletedAt: isCompletedAt ?? this.isCompletedAt,
      notificationId: notificationId ?? this.notificationId,
      hourlyInterval: hourlyInterval ?? this.hourlyInterval,
    );
  }

  // ── Next occurrence logic ──────────────────────────────────────────────────

  /// Given [from] (usually DateTime.now()), compute when this alarm should
  /// next fire based on its recurrence type and last-completed time.
  DateTime nextOccurrence({DateTime? from}) {
    final base = from ?? DateTime.now();

    switch (recurrence) {
      case RecurrenceType.once:
        return scheduledAt;

      case RecurrenceType.hourly:
        // Every X hours from the original scheduled time
        var next = scheduledAt;
        while (!next.isAfter(base)) {
          next = next.add(Duration(hours: hourlyInterval));
        }
        return next;

      case RecurrenceType.daily:
        var next = scheduledAt;
        while (!next.isAfter(base)) {
          next = next.add(const Duration(days: 1));
        }
        return next;

      case RecurrenceType.weekly:
        var next = scheduledAt;
        while (!next.isAfter(base)) {
          next = next.add(const Duration(days: 7));
        }
        return next;

      case RecurrenceType.monthly:
        var next = scheduledAt;
        while (!next.isAfter(base)) {
          next = DateTime(
            next.year,
            next.month + 1,
            next.day,
            next.hour,
            next.minute,
          );
        }
        return next;
    }
  }

  String get recurrenceLabel {
    switch (recurrence) {
      case RecurrenceType.once:
        return 'Once';
      case RecurrenceType.hourly:
        return hourlyInterval == 1
            ? 'Every Hour'
            : 'Every $hourlyInterval Hours';
      case RecurrenceType.daily:
        return 'Every Day';
      case RecurrenceType.weekly:
        return 'Every Week';
      case RecurrenceType.monthly:
        return 'Every Month';
    }
  }
}
