import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_alarm_manager/data/database_helper.dart';
import 'package:smart_alarm_manager/models/reminder.dart';
import 'package:smart_alarm_manager/services/audio_service.dart';

class AlarmScreen extends StatefulWidget {
  final int? reminderId;

  const AlarmScreen({super.key, this.reminderId});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen>
    with SingleTickerProviderStateMixin {
  Reminder? _reminder;
  late AnimationController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Ensure alarm plays even if opened via Full Screen Intent (where main.dart might miss the event)
    AudioService().playAlarm();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _loadReminder();
  }

  Future<void> _loadReminder() async {
    if (widget.reminderId != null) {
      final dbHelper = DatabaseHelper();
      final reminders = await dbHelper
          .getReminders(); // Assuming getById isn't exposed yet, filtering list
      try {
        final reminder = reminders.firstWhere((r) => r.id == widget.reminderId);
        setState(() {
          _reminder = reminder;
          _isLoading = false;
        });
      } catch (e) {
        // Not found
        setState(() => _isLoading = false);
      }
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _doneAlarm() async {
    // Stop audio/vibration from main isolate (method channels work here)
    await AudioService().stopAlarm();

    // Update reminder status to completed in database
    if (widget.reminderId != null) {
      try {
        final dbHelper = DatabaseHelper();
        final reminders = await dbHelper.getReminders();
        final reminder = reminders.firstWhere((r) => r.id == widget.reminderId);
        final updated = reminder.copyWith(
          status: ReminderStatus.completed,
          isActive: false, // Turn off geofence check
        );
        await dbHelper.updateReminder(updated);
      } catch (e) {
        print('Error marking reminder as done: $e');
      }
    }

    // Send signal to background service to update state
    final service = FlutterBackgroundService();
    service.invoke('stop_alarm');

    // Close screen
    if (mounted) {
      SystemNavigator.pop();
    }
  }

  Future<void> _cancelAlarm() async {
    // Stop audio/vibration from main isolate (method channels work here)
    await AudioService().stopAlarm();

    // Update reminder status to canceled in database
    if (widget.reminderId != null) {
      try {
        final dbHelper = DatabaseHelper();
        final reminders = await dbHelper.getReminders();
        final reminder = reminders.firstWhere((r) => r.id == widget.reminderId);
        final updated = reminder.copyWith(
          status: ReminderStatus.canceled,
          isActive: false, // Turn off geofence check
        );
        await dbHelper.updateReminder(updated);
      } catch (e) {
        print('Error marking reminder as canceled: $e');
      }
    }

    // Send signal to background service to update state
    final service = FlutterBackgroundService();
    service.invoke('stop_alarm');

    // Close screen
    if (mounted) {
      SystemNavigator.pop();
    }
  }

  Future<void> _snoozeAlarm() async {
    // Get snooze duration from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final snoozeDuration = prefs.getInt('snooze_duration') ?? 5;

    // Stop current alarm sound
    await AudioService().stopAlarm();

    // Send signal to background service
    final service = FlutterBackgroundService();
    service.invoke('snooze_alarm', {
      'reminder_id': widget.reminderId,
      'snooze_minutes': snoozeDuration,
    });

    // Show confirmation
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Alarm snoozed for $snoozeDuration minutes'),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.green,
        ),
      );

      // Close screen after brief delay to show snackbar
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        SystemNavigator.pop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            // Radar Animation
            Stack(
              alignment: Alignment.center,
              children: [
                ScaleTransition(
                  scale: Tween(begin: 0.8, end: 1.5).animate(
                    CurvedAnimation(parent: _controller, curve: Curves.easeOut),
                  ),
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red.withOpacity(0.3),
                    ),
                  ),
                ),
                ScaleTransition(
                  scale: Tween(begin: 0.8, end: 1.2).animate(
                    CurvedAnimation(parent: _controller, curve: Curves.easeOut),
                  ),
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red.withOpacity(0.5),
                    ),
                  ),
                ),
                Container(
                  width: 100,
                  height: 100,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.red,
                  ),
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.white,
                    size: 50,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 50),

            // Text Info
            if (_isLoading)
              const CircularProgressIndicator(color: Colors.white)
            else ...[
              Text(
                "ARRIVED AT",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  letterSpacing: 2,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Text(
                  _reminder?.title ?? "Destination",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (_reminder?.description.isNotEmpty == true) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40.0),
                  child: Text(
                    _reminder!.description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 18),
                  ),
                ),
              ],
            ],

            const Spacer(),

            // Snooze and Stop Buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                children: [
                  // Large Snooze Button
                  SizedBox(
                    width: double.infinity,
                    height: 70,
                    child: ElevatedButton.icon(
                      onPressed: _snoozeAlarm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(35),
                        ),
                        elevation: 8,
                      ),
                      icon: const Icon(Icons.snooze, size: 32),
                      label: const Text(
                        "SNOOZE",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Done Button with 3-dot Menu
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Done Button
                      SizedBox(
                        width: 180,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: _doneAlarm,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green.shade300,
                            side: BorderSide(
                              color: Colors.green.shade300,
                              width: 2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                          ),
                          icon: const Icon(
                            Icons.check_circle_outline,
                            size: 20,
                          ),
                          label: const Text(
                            "Done",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // 3-dot Menu
                      Container(
                        height: 50,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white30),
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: PopupMenuButton<String>(
                          icon: const Icon(
                            Icons.more_vert,
                            color: Colors.white,
                          ),
                          color: Colors.grey[900],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          onSelected: (value) {
                            if (value == 'cancel') {
                              _cancelAlarm();
                            }
                          },
                          itemBuilder: (BuildContext context) => [
                            PopupMenuItem<String>(
                              value: 'cancel',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.cancel_outlined,
                                    color: Colors.red.shade300,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Cancel Reminder',
                                    style: TextStyle(
                                      color: Colors.red.shade300,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
