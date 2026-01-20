import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:smart_alarm_manager/data/database_helper.dart';
import 'package:smart_alarm_manager/models/reminder.dart';

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

  Future<void> _stopAlarm() async {
    // Send signal to background service to stop audio
    final service = FlutterBackgroundService();
    service.invoke('stop_alarm');

    // Close screen
    if (mounted) {
      // Assuming we pushed this route, we pop.
      // Or if checking from main, we might want to replaceRoute to Home.
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      } else {
        // Navigate back to home if we can't pop (e.g. app launched directly to here)
        Navigator.pushReplacementNamed(context, '/');
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

            // Stop Button
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: _stopAlarm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text(
                    "STOP ALARM",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
