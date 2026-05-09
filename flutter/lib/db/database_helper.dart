import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import '../models/alarm_model.dart';

/// Provides centralized SQLite database management for the alarm application.
///
/// This class acts as the primary persistence layer of the app and is
/// responsible for:
/// - Initializing and opening the local SQLite database
/// - Creating the alarms table schema during first launch
/// - Managing all CRUD operations for alarm records
/// - Converting raw database rows into strongly typed [Alarm] models
/// - Providing singleton-based database access across the application
/// - Maintaining notification ID tracking for local notifications
///
/// Architecture Role:
/// ------------------
/// [DatabaseHelper] functions as the low-level data access layer between
/// the application's business logic and the local SQLite storage.
///
/// The class follows a singleton pattern to ensure:
/// - Only one database connection exists throughout app lifecycle
/// - Database access remains synchronized and efficient
/// - Resource consumption is minimized
///
/// Database Lifecycle Flow:
/// ------------------------
/// 1. App requests database access through [database]
/// 2. Lazy initialization checks if database instance exists
/// 3. If not initialized:
///    - Device database directory is resolved
///    - `alarms.db` file is created/opened
///    - Table schema is generated using `onCreate`
/// 4. Shared database instance is cached in memory
/// 5. Future operations reuse the same connection
///
/// Table Responsibilities:
/// -----------------------
/// The `alarms` table stores:
/// - Alarm metadata
/// - Scheduling information
/// - Recurrence configuration
/// - Notification identifiers
/// - Completion state tracking
/// - Auto-delete preferences
/// - Hourly interval scheduling data
///
/// State Management Role:
/// ----------------------
/// Although this class itself does not manage UI state, it acts as the
/// persistent data source for:
/// - Providers
/// - Controllers
/// - Services
/// - ViewModels
/// - State management solutions (Provider/BLoC/Riverpod/etc.)
///
/// Async Behavior:
/// ---------------
/// All database operations are asynchronous because:
/// - SQLite I/O operations are non-blocking
/// - Disk access can be expensive
/// - UI thread responsiveness must be preserved
///
/// Local Storage Usage:
/// --------------------
/// Uses SQLite through the `sqflite` package for structured local persistence.
/// Database file location is resolved dynamically using:
/// [sqflite.getDatabasesPath].
///
/// Thread Safety:
/// --------------
/// Since sqflite internally serializes database access, concurrent operations
/// remain safe for normal Flutter application usage.
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static sqflite.Database? _db;

  Future<sqflite.Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  /// Initializes and opens the local SQLite database.
  ///
  /// Responsibilities:
  /// -----------------
  /// - Resolves device database storage path
  /// - Creates/open the `alarms.db` database file
  /// - Defines schema creation logic
  /// - Configures database versioning
  ///
  /// Database Schema:
  /// ----------------
  /// The `alarms` table contains:
  /// - Unique alarm identifier
  /// - Alarm label/title
  /// - Scheduled execution timestamp
  /// - Recurrence configuration
  /// - Completion tracking
  /// - Notification linkage IDs
  /// - Hourly repetition interval data
  ///
  /// Lifecycle:
  /// ----------
  /// `onCreate` executes only during the first database creation.
  ///
  /// Future Enhancements:
  /// --------------------
  /// Future versions may introduce:
  /// - Database migrations
  /// - Additional indexes
  /// - Foreign key relationships
  /// - Schema evolution using `onUpgrade`
  Future<sqflite.Database> _initDb() async {
    final dbPath = await sqflite.getDatabasesPath();
    final path = p.join(dbPath, 'alarms.db');

    return sqflite.openDatabase(
      path,
      version: 1,

      /// Creates the initial alarms table schema.
      ///
      /// Executed only when the database does not already exist.
      ///
      /// Table Design Notes:
      /// -------------------
      /// - Boolean values are stored as INTEGER (0/1)
      /// - Date values are stored as TEXT for serialization simplicity
      /// - `notification_id` links alarms to local notifications
      /// - `hourly_interval` supports recurring hourly reminders
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE alarms (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            label           TEXT    NOT NULL,
            scheduled_at    TEXT    NOT NULL,
            recurrence      TEXT    NOT NULL,
            auto_delete     INTEGER NOT NULL DEFAULT 0,
            is_completed    INTEGER NOT NULL DEFAULT 0,
            is_completed_at TEXT,
            notification_id INTEGER NOT NULL,
            hourly_interval INTEGER NOT NULL DEFAULT 1
          )
        ''');
      },
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // CRUD OPERATIONS
  // ───────────────────────────────────────────────────────────────────────────

  /// Inserts a new alarm record into the database.
  ///
  /// Responsibilities:
  /// -----------------
  /// - Serializes [Alarm] model into database-compatible map
  /// - Persists alarm configuration locally
  /// - Replaces existing row if conflict occurs
  ///
  /// Conflict Strategy:
  /// ------------------
  /// Uses [ConflictAlgorithm.replace] to overwrite records when
  /// duplicate primary keys exist.
  ///
  /// Returns:
  /// --------
  /// - Inserted row ID
  ///
  /// Common Usage:
  /// -------------
  /// Called when:
  /// - User creates a new alarm
  /// - Alarm is duplicated
  /// - Alarm is restored/imported
  Future<int> insertAlarm(Alarm alarm) async {
    final db = await database;
    return db.insert(
      'alarms',
      alarm.toMap(),
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }

  /// Retrieves all stored alarms ordered by scheduled time.
  ///
  /// Data Flow:
  /// ----------
  /// SQLite rows → Map conversion → [Alarm] model transformation
  ///
  /// Sorting:
  /// --------
  /// Results are ordered ascending by `scheduled_at` to ensure:
  /// - Upcoming alarms appear first
  /// - UI rendering remains chronologically organized
  ///
  /// Returns:
  /// --------
  /// - List of fully mapped [Alarm] objects
  ///
  /// Common Consumers:
  /// -----------------
  /// - Home screen
  /// - Alarm listing UI
  /// - Scheduling services
  /// - Notification restoration logic
  Future<List<Alarm>> getAllAlarms() async {
    final db = await database;
    final maps = await db.query('alarms', orderBy: 'scheduled_at ASC');
    return maps.map(Alarm.fromMap).toList();
  }

  /// Retrieves a single alarm using its unique database ID.
  ///
  /// Workflow:
  /// ---------
  /// - Executes filtered query using alarm ID
  /// - Limits result to a single row
  /// - Converts database map into [Alarm] model
  ///
  /// Returns:
  /// --------
  /// - [Alarm] object if found
  /// - `null` if alarm does not exist
  ///
  /// Common Usage:
  /// -------------
  /// - Alarm detail screens
  /// - Notification tap handling
  /// - Editing existing alarms
  /// - Background scheduling recovery
  Future<Alarm?> getAlarmById(int id) async {
    final db = await database;
    final maps = await db.query(
      'alarms',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Alarm.fromMap(maps.first);
  }

  /// Updates an existing alarm record.
  ///
  /// Responsibilities:
  /// -----------------
  /// - Persists modified alarm configuration
  /// - Updates recurrence and scheduling data
  /// - Saves completion state changes
  /// - Synchronizes notification-related metadata
  ///
  /// Matching Strategy:
  /// ------------------
  /// Uses the alarm's unique `id` field to identify the target row.
  ///
  /// Returns:
  /// --------
  /// - Number of affected rows
  ///
  /// Typically Called When:
  /// ----------------------
  /// - User edits an alarm
  /// - Alarm completion state changes
  /// - Recurrence settings are modified
  /// - Notification IDs are refreshed
  Future<int> updateAlarm(Alarm alarm) async {
    final db = await database;
    return db.update(
      'alarms',
      alarm.toMap(),
      where: 'id = ?',
      whereArgs: [alarm.id],
    );
  }

  /// Permanently deletes an alarm from local storage.
  ///
  /// Responsibilities:
  /// -----------------
  /// - Removes alarm row from SQLite database
  /// - Prevents future retrieval or scheduling
  ///
  /// Important:
  /// ----------
  /// In production systems, associated notification cancellation should
  /// typically occur before database deletion to avoid orphaned reminders.
  ///
  /// Returns:
  /// --------
  /// - Number of deleted rows
  ///
  /// Common Triggers:
  /// ----------------
  /// - User manually deletes alarm
  /// - Auto-delete after completion
  /// - Cleanup operations
  Future<int> deleteAlarm(int id) async {
    final db = await database;
    return db.delete('alarms', where: 'id = ?', whereArgs: [id]);
  }

  /// Retrieves the highest notification ID currently stored.
  ///
  /// Purpose:
  /// --------
  /// Notification systems typically require unique integer identifiers.
  /// This method helps generate the next safe notification ID.
  ///
  /// Workflow:
  /// ---------
  /// - Executes aggregate SQL query using MAX()
  /// - Extracts highest notification ID
  /// - Returns fallback value if database is empty
  ///
  /// Returns:
  /// --------
  /// - Highest existing notification ID
  /// - `0` if no alarms exist
  ///
  /// Common Usage:
  /// -------------
  /// - Before scheduling new notifications
  /// - Notification restoration systems
  /// - Preventing notification ID collisions
  Future<int> maxNotificationId() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT MAX(notification_id) as max_id FROM alarms',
    );
    return (result.first['max_id'] as int?) ?? 0;
  }
}
