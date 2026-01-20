import '../models/reminder.dart';
import 'database_helper.dart';

class ReminderRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<int> addReminder(Reminder reminder) {
    return _dbHelper.insertReminder(reminder);
  }

  Future<List<Reminder>> getReminders() {
    return _dbHelper.getReminders();
  }

  Future<int> updateReminder(Reminder reminder) {
    return _dbHelper.updateReminder(reminder);
  }

  Future<int> deleteReminder(int id) {
    return _dbHelper.deleteReminder(id);
  }

  Future<Reminder?> getReminder(int id) {
    return _dbHelper.getReminder(id);
  }
}
