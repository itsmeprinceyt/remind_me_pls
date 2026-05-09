/// Defines the supported recurrence patterns available for alarm scheduling.
///
/// This enum acts as the core recurrence configuration layer for the
/// application's reminder scheduling system.
///
/// Responsibilities:
/// -----------------
/// - Determines how alarm repetition is calculated
/// - Controls recurring notification scheduling behavior
/// - Drives next-occurrence computation logic
/// - Provides recurrence metadata for UI rendering
/// - Enables persistence-safe recurrence serialization
///
/// Architecture Role:
/// ------------------
/// [RecurrenceType] is a foundational domain-level construct shared across:
/// - Alarm models
/// - Notification scheduling services
/// - UI recurrence selectors
/// - Database persistence layer
/// - Background reminder restoration systems
///
/// Persistence Behavior:
/// ---------------------
/// Enum values are serialized using `.name` and stored in SQLite.
/// Example:
/// - `RecurrenceType.daily` → `"daily"`
///
/// Scheduling Semantics:
/// ---------------------
/// - once:
///     Single execution alarm
///
/// - hourly:
///     Repeats every custom X-hour interval
///
/// - daily:
///     Repeats every calendar day
///
/// - weekly:
///     Repeats every 7 days
///
/// - monthly:
///     Repeats monthly while preserving time components
///
/// Important Notes:
/// ----------------
/// Since recurrence values are persisted to local storage,
/// renaming enum values may break backward compatibility unless
/// migration logic is implemented.
enum RecurrenceType { once, hourly, daily, weekly, monthly }

/// Represents a complete alarm domain model used throughout the application.
///
/// This model acts as the primary business entity for the reminder system and
/// encapsulates:
/// - Alarm scheduling metadata
/// - Recurrence configuration
/// - Notification linkage information
/// - Completion tracking state
/// - Database serialization behavior
/// - Alarm duplication/update workflows
/// - Future occurrence calculation logic
///
/// Architecture Role:
/// ------------------
/// [Alarm] serves as the central data contract shared between:
/// - SQLite persistence layer
/// - Notification scheduling services
/// - UI rendering widgets
/// - State management providers/controllers
/// - Background restoration systems
/// - Alarm editing workflows
///
/// Data Flow:
/// ----------
/// User Input
///     ↓
/// Alarm Creation
///     ↓
/// Serialization (`toMap`)
///     ↓
/// SQLite Persistence
///     ↓
/// Retrieval (`fromMap`)
///     ↓
/// Notification Scheduling
///     ↓
/// UI Rendering
///
/// State Management Role:
/// ----------------------
/// This model is immutable, meaning state changes occur through:
/// - Creating new instances
/// - Using [copyWith]
/// - Replacing previous state references
///
/// This architecture improves:
/// - Predictability
/// - State synchronization
/// - Debugging reliability
/// - Provider/BLoC compatibility
///
/// Notification System Integration:
/// --------------------------------
/// Each alarm maintains a unique [notificationId] used by
/// `flutter_local_notifications`.
///
/// This linkage enables:
/// - Notification cancellation
/// - Rescheduling
/// - Background restoration
/// - Notification tap handling
///
/// Recurrence Workflow:
/// --------------------
/// Recurring alarms dynamically compute future execution times using:
/// - Original scheduled timestamp
/// - Current system time
/// - Recurrence configuration
/// - Hourly interval settings
///
/// Persistence Strategy:
/// ---------------------
/// The model supports bidirectional serialization:
///
/// - [toMap]:
///     Converts model → SQLite-compatible map
///
/// - [fromMap]:
///     Converts SQLite row → strongly typed model
///
/// Local Storage Behavior:
/// -----------------------
/// Stored using SQLite via the `sqflite` package.
///
/// Date Handling:
/// --------------
/// Dates are persisted as ISO8601 strings for:
/// - Timezone-safe serialization
/// - Consistent parsing
/// - Database portability
///
/// Lifecycle Usage:
/// ----------------
/// Alarm objects are commonly created during:
/// - Alarm creation flows
/// - Database restoration
/// - Notification recovery
/// - Alarm editing operations
/// - Recurring schedule recalculations
///
/// Error Handling Considerations:
/// ------------------------------
/// Parsing operations assume valid persisted data.
/// Production-grade implementations may additionally include:
/// - Safe parsing fallbacks
/// - Corruption recovery
/// - Validation layers
/// - Null safety guards
///
/// Immutability Benefits:
/// ----------------------
/// Since all fields are final:
/// - State mutations become predictable
/// - UI rebuilds remain consistent
/// - Race conditions are minimized
/// - Concurrent async workflows become safer
class Alarm {
  final int? id;
  final String label;
  final DateTime scheduledAt;
  final RecurrenceType recurrence;
  final bool autoDelete;
  final bool isCompleted;
  final DateTime? isCompletedAt;
  final int notificationId;
  final int hourlyInterval;

  const Alarm({
    this.id,
    required this.label,
    required this.scheduledAt,
    required this.recurrence,
    required this.autoDelete,
    this.isCompleted = false,
    this.isCompletedAt,
    required this.notificationId,
    this.hourlyInterval = 1,
  });

  // ───────────────────────────────────────────────────────────────────────────
  // SERIALIZATION
  // ───────────────────────────────────────────────────────────────────────────

  /// Converts the alarm model into a SQLite-compatible map structure.
  ///
  /// Responsibilities:
  /// -----------------
  /// - Serializes complex Dart types
  /// - Converts booleans into SQLite integer format
  /// - Converts DateTime objects into ISO8601 strings
  /// - Produces database-ready payloads
  ///
  /// Data Conversion Rules:
  /// ----------------------
  /// - bool → INTEGER (0/1)
  /// - DateTime → ISO8601 String
  /// - enum → String name
  ///
  /// Common Consumers:
  /// -----------------
  /// - Database insert operations
  /// - Database update operations
  /// - Backup/export systems
  ///
  /// Returns:
  /// --------
  /// - Map<String, dynamic> suitable for SQLite persistence
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

  /// Creates an [Alarm] instance from a SQLite database row.
  ///
  /// Responsibilities:
  /// -----------------
  /// - Parses persisted database values
  /// - Restores DateTime objects
  /// - Reconstructs recurrence enums
  /// - Converts SQLite integers back into booleans
  ///
  /// Recovery Behavior:
  /// ------------------
  /// If recurrence parsing fails, fallback defaults to:
  /// [RecurrenceType.once]
  ///
  /// Data Flow:
  /// ----------
  /// SQLite Row
  ///     ↓
  /// Raw Map
  ///     ↓
  /// Strongly Typed Alarm Model
  ///
  /// Parameters:
  /// -----------
  /// - [map]:
  ///     Raw database row retrieved from SQLite
  ///
  /// Returns:
  /// --------
  /// - Fully reconstructed [Alarm] instance
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

  /// Creates a modified copy of the current alarm instance.
  ///
  /// Purpose:
  /// --------
  /// Supports immutable state updates without mutating the original object.
  ///
  /// Architecture Benefits:
  /// ----------------------
  /// - Predictable state transitions
  /// - Safer async workflows
  /// - Better Provider/BLoC compatibility
  /// - Easier debugging
  ///
  /// Common Usage:
  /// -------------
  /// ```dart
  /// final updated = alarm.copyWith(
  ///   isCompleted: true,
  /// );
  /// ```
  ///
  /// Parameters:
  /// -----------
  /// Any non-null parameter replaces the existing field value.
  ///
  /// Returns:
  /// --------
  /// - New immutable [Alarm] instance
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

  // ───────────────────────────────────────────────────────────────────────────
  // RECURRENCE ENGINE
  // ───────────────────────────────────────────────────────────────────────────

  /// Calculates the next valid execution time for the alarm.
  ///
  /// This method acts as the core recurrence engine of the application.
  ///
  /// Responsibilities:
  /// -----------------
  /// - Computes future reminder occurrences
  /// - Applies recurrence rules dynamically
  /// - Ensures returned timestamps are always future-oriented
  /// - Supports hourly, daily, weekly, and monthly repetition
  ///
  /// Workflow:
  /// ---------
  /// 1. Determine reference time
  /// 2. Evaluate recurrence type
  /// 3. Increment scheduled time until future occurrence is found
  /// 4. Return next valid execution timestamp
  ///
  /// Parameters:
  /// -----------
  /// - [from]:
  ///     Optional reference time used for recurrence calculation.
  ///
  ///     Defaults to:
  ///     `DateTime.now()`
  ///
  /// Common Consumers:
  /// -----------------
  /// - Notification scheduling services
  /// - Background alarm restoration
  /// - UI countdown systems
  /// - Alarm preview rendering
  ///
  /// Performance Notes:
  /// ------------------
  /// Loop-based recurrence calculation is lightweight for typical
  /// reminder usage patterns.
  ///
  /// Returns:
  /// --------
  /// - Future [DateTime] representing next alarm occurrence
  ///
  /// Important:
  /// ----------
  /// Monthly recurrence preserves:
  /// - Day
  /// - Hour
  /// - Minute
  ///
  /// while incrementing the calendar month.
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

  /// Human-readable recurrence label used by the UI layer.
  ///
  /// Responsibilities:
  /// -----------------
  /// - Converts recurrence configuration into display-friendly text
  /// - Supports dynamic hourly interval labeling
  /// - Provides consistent recurrence terminology across screens
  ///
  /// UI Usage:
  /// ---------
  /// Commonly displayed in:
  /// - Alarm list items
  /// - Reminder details
  /// - Notification previews
  /// - Scheduling summary widgets
  ///
  /// Examples:
  /// ---------
  /// - "Once"
  /// - "Every Hour"
  /// - "Every 3 Hours"
  /// - "Every Day"
  ///
  /// Returns:
  /// --------
  /// - Localized-ready human-readable recurrence string
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
