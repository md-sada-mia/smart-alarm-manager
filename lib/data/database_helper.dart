import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/reminder.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'smart_alarm_manager.db');
    return await openDatabase(
      path,
      version: 2, // Incremented version for migration
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE reminders(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        description TEXT,
        latitude REAL,
        longitude REAL,
        radius REAL,
        isActive INTEGER,
        status TEXT DEFAULT 'active',
        snoozeUntil TEXT,
        createdAt TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add new columns for existing databases
      await db.execute(
        'ALTER TABLE reminders ADD COLUMN status TEXT DEFAULT "active"',
      );
      await db.execute('ALTER TABLE reminders ADD COLUMN snoozeUntil TEXT');
    }
  }

  Future<int> insertReminder(Reminder reminder) async {
    Database db = await database;
    return await db.insert('reminders', reminder.toMap());
  }

  Future<List<Reminder>> getReminders() async {
    Database db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'reminders',
      orderBy: 'createdAt DESC',
    );
    return List.generate(maps.length, (i) {
      return Reminder.fromMap(maps[i]);
    });
  }

  Future<int> updateReminder(Reminder reminder) async {
    Database db = await database;
    return await db.update(
      'reminders',
      reminder.toMap(),
      where: 'id = ?',
      whereArgs: [reminder.id],
    );
  }

  Future<int> deleteReminder(int id) async {
    Database db = await database;
    return await db.delete('reminders', where: 'id = ?', whereArgs: [id]);
  }

  Future<Reminder?> getReminder(int id) async {
    Database db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'reminders',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return Reminder.fromMap(maps.first);
    }
    return null;
  }
}
