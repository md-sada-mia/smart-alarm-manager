import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/reminder.dart';
import '../models/suggestion_history.dart';

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
      version: 3, // Incremented version for suggestion_history
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

    await db.execute('''
      CREATE TABLE suggestion_history(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        latitude REAL,
        longitude REAL,
        usageCount INTEGER DEFAULT 1,
        lastUsedAt TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE reminders ADD COLUMN status TEXT DEFAULT "active"',
      );
      await db.execute('ALTER TABLE reminders ADD COLUMN snoozeUntil TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE suggestion_history(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT,
          latitude REAL,
          longitude REAL,
          usageCount INTEGER DEFAULT 1,
          lastUsedAt TEXT
        )
      ''');
    }
  }

  // --- Reminder Operations ---

  Future<int> insertReminder(Reminder reminder) async {
    Database db = await database;
    // Auto-save suggestion when inserting reminder
    await saveSuggestion(reminder.title, reminder.latitude, reminder.longitude);
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

  // --- Suggestion History Operations ---

  Future<void> saveSuggestion(String title, double lat, double lng) async {
    Database db = await database;
    final normalizedTitle = title.trim();

    // Check if exact location exists first (most precise match)
    final List<Map<String, dynamic>> locMatches = await db.query(
      'suggestion_history',
      where: 'ABS(latitude - ?) < 0.0001 AND ABS(longitude - ?) < 0.0001',
      whereArgs: [lat, lng],
    );

    if (locMatches.isNotEmpty) {
      // Update existing location entry
      final existing = SuggestionHistory.fromMap(locMatches.first);
      await db.update(
        'suggestion_history',
        {
          'usageCount': existing.usageCount + 1,
          'lastUsedAt': DateTime.now().toIso8601String(),
          'title': normalizedTitle, // Update title to most recent usage
        },
        where: 'id = ?',
        whereArgs: [existing.id],
      );
    } else {
      // Insert new entry
      await db.insert('suggestion_history', {
        'title': normalizedTitle,
        'latitude': lat,
        'longitude': lng,
        'usageCount': 1,
        'lastUsedAt': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<List<String>> getTitleSuggestions(String query) async {
    Database db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'suggestion_history',
      columns: ['title'],
      where: 'title LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'usageCount DESC, lastUsedAt DESC',
      limit: 5,
    );
    return maps
        .map((e) => e['title'] as String)
        .toSet()
        .toList(); // Unique titles
  }

  Future<List<SuggestionHistory>> getLocationSuggestions() async {
    Database db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'suggestion_history',
      orderBy: 'usageCount DESC, lastUsedAt DESC',
      limit: 10,
    );
    return List.generate(
      maps.length,
      (i) => SuggestionHistory.fromMap(maps[i]),
    );
  }

  Future<List<SuggestionHistory>> getAllHistory() async {
    Database db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'suggestion_history',
      orderBy: 'usageCount DESC, lastUsedAt DESC',
    );
    return List.generate(
      maps.length,
      (i) => SuggestionHistory.fromMap(maps[i]),
    );
  }
}
