// lib/db/database_helper.dart

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import '../models/alarm_model.dart';

class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static sqflite.Database? _db;

  Future<sqflite.Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<sqflite.Database> _initDb() async {
    final dbPath = await sqflite.getDatabasesPath();
    final path = p.join(dbPath, 'alarms.db');

    return sqflite.openDatabase(
      path,
      version: 1,
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
            notification_id INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────

  Future<int> insertAlarm(Alarm alarm) async {
    final db = await database;
    return db.insert(
      'alarms',
      alarm.toMap(),
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }

  Future<List<Alarm>> getAllAlarms() async {
    final db = await database;
    final maps = await db.query('alarms', orderBy: 'scheduled_at ASC');
    return maps.map(Alarm.fromMap).toList();
  }

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

  Future<int> updateAlarm(Alarm alarm) async {
    final db = await database;
    return db.update(
      'alarms',
      alarm.toMap(),
      where: 'id = ?',
      whereArgs: [alarm.id],
    );
  }

  Future<int> deleteAlarm(int id) async {
    final db = await database;
    return db.delete('alarms', where: 'id = ?', whereArgs: [id]);
  }

  /// Returns the highest notification_id currently in use, or 0 if none.
  Future<int> maxNotificationId() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT MAX(notification_id) as max_id FROM alarms',
    );
    return (result.first['max_id'] as int?) ?? 0;
  }
}
