import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:smart_alarm_manager/data/reminder_repository.dart';
import 'package:smart_alarm_manager/models/reminder.dart';
import 'package:smart_alarm_manager/services/permission_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:smart_alarm_manager/services/location_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final ReminderRepository _repository = ReminderRepository();
  List<Reminder> _reminders = [];
  Position? _currentPosition;
  bool _isLoading = true;
  Timer? _timer;
  Completer<void>? _resumeCompleter;

  @required
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPermissionsAndLoad();
    });
    // Refresh location every 10 seconds to update distances
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) _getCurrentLocation();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resumeCompleter?.complete(); // Clean up
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumeCompleter?.complete();
      _resumeCompleter = null;
    }
  }

  Future<void> _waitForResume() async {
    _resumeCompleter = Completer<void>();
    // Wait for resume - no timeout for Settings interactions
    // If user never returns, the app staying in background is fine.
    await _resumeCompleter!.future;
  }

  Future<void> _checkPermissionsAndLoad() async {
    final hasPerms = await PermissionService().checkPermissions();
    if (!hasPerms) {
      await PermissionService().requestLocationPermissions();
      await PermissionService().requestNotificationPermissions();

      // Initial standard checks
    }

    // Now start blocking check for reliability
    // This MUST happen before we fully initialize logic that depends on it
    await _checkReliabilityPermissions();

    // Permissions granted (or passed blocking check), now we can safely start the service
    await LocationService().initialize();

    _loadReminders();
    _getCurrentLocation();
  }

  Future<void> _checkReliabilityPermissions() async {
    if (!mounted) return;

    // Check permissions initially
    bool batteryOptimized =
        await Permission.ignoreBatteryOptimizations.isGranted;
    bool overlayGranted = await Permission.systemAlertWindow.isGranted;

    while (!batteryOptimized || !overlayGranted) {
      if (!mounted) return;

      // Show dialog explaining requirements
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Permission Required'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Please allow the following permissions to ensure alarms work reliably:',
                ),
                const SizedBox(height: 12),
                if (!batteryOptimized)
                  const ListTile(
                    leading: Icon(Icons.battery_alert, color: Colors.orange),
                    title: Text('Ignore Battery Optimization'),
                    subtitle: Text('Prevents app from sleeping in background'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                if (!overlayGranted)
                  const ListTile(
                    leading: Icon(Icons.layers, color: Colors.blue),
                    title: Text('Display Over Other Apps'),
                    subtitle: Text(
                      'Required to show alarm screen from background',
                    ),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      );

      // 1. Handle Battery Optimization (In-app dialog usually)
      if (!batteryOptimized) {
        await PermissionService().requestIgnoreBatteryOptimizations();
        // Short delay to allow status update
        await Future.delayed(const Duration(milliseconds: 500));
        batteryOptimized =
            await Permission.ignoreBatteryOptimizations.isGranted;
      }

      // 2. Handle Overlay (Settings Screen)
      // Only proceed if battery involved interaction didn't crash us or we are ready
      if (!overlayGranted) {
        // If we just handled battery, user might be fatigued, but we must persist
        await PermissionService().requestSystemAlertWindow();
        // For Overlay, we definitely need to wait for resume as it goes to Settings
        await _waitForResume();

        // Wait extra time for system to propagate verification logic
        await Future.delayed(const Duration(seconds: 1));
        overlayGranted = await Permission.systemAlertWindow.isGranted;
      }

      // Loop continues if either is still false
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
      }
    } catch (e) {
      print("Error getting location: $e");
    }
  }

  Future<void> _loadReminders() async {
    setState(() => _isLoading = true);
    final reminders = await _repository.getReminders();
    if (mounted) {
      setState(() {
        _reminders = reminders;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteReminder(int id) async {
    await _repository.deleteReminder(id);
    _loadReminders();
  }

  Future<void> _toggleActive(Reminder reminder) async {
    final bool newActiveState = !reminder.isActive;
    final updated = reminder.copyWith(
      isActive: newActiveState,
      // If manually enabled, reset status to active
      status: newActiveState ? ReminderStatus.active : reminder.status,
      clearSnooze: newActiveState, // Clear snooze if re-enabling
    );
    await _repository.updateReminder(updated);
    _loadReminders();
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return "${meters.toInt()} m";
    } else {
      return "${(meters / 1000).toStringAsFixed(1)} km";
    }
  }

  Future<Map<String, dynamic>?> _getSnoozeInfo(Reminder reminder) async {
    // Check if reminder is in snoozed status
    if (reminder.status == ReminderStatus.snoozed &&
        reminder.snoozeUntil != null) {
      final now = DateTime.now();

      if (reminder.snoozeUntil!.isAfter(now)) {
        // Still snoozed
        final remaining = reminder.snoozeUntil!.difference(now);
        return {'isSnoozed': true, 'remaining': remaining};
      } else {
        // Expired, update database to reset status
        try {
          final updated = reminder.copyWith(
            status: ReminderStatus.active,
            clearSnooze: true,
          );
          await _repository.updateReminder(updated);
        } catch (e) {
          print('Error resetting expired snooze: $e');
        }
      }
    }

    return null;
  }

  String _formatSnoozeDuration(Duration duration) {
    if (duration.inMinutes > 0) {
      return "Snoozed ${duration.inMinutes}m ${duration.inSeconds % 60}s";
    } else {
      return "Snoozed ${duration.inSeconds}s";
    }
  }

  Color _getStatusColor(Reminder reminder) {
    if (!reminder.isActive) {
      if (reminder.status == ReminderStatus.completed) return Colors.green;
      if (reminder.status == ReminderStatus.canceled) return Colors.red;
      return Colors.grey;
    }

    switch (reminder.status) {
      case ReminderStatus.active:
        return Colors.blue;
      case ReminderStatus.snoozed:
        return Colors.orange;
      case ReminderStatus.completed:
        return Colors.green;
      case ReminderStatus.canceled:
        return Colors.red;
    }
  }

  String _getStatusLabel(Reminder reminder) {
    if (!reminder.isActive) {
      if (reminder.status == ReminderStatus.completed) return 'Done';
      if (reminder.status == ReminderStatus.canceled) return 'Canceled';
      return 'Inactive';
    }

    switch (reminder.status) {
      case ReminderStatus.active:
        return 'Active';
      case ReminderStatus.snoozed:
        return 'Snoozed';
      case ReminderStatus.completed:
        return 'Done';
      case ReminderStatus.canceled:
        return 'Canceled';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipOval(
              child: Image.asset(
                'assets/images/logo.png',
                height: 32,
                width: 32,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Smart Reminders'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _reminders.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.location_off_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "No reminders yet",
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Tap + to add a location reminder",
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadReminders,
              child: ListView.builder(
                itemCount: _reminders.length,
                padding: const EdgeInsets.all(16),
                itemBuilder: (context, index) {
                  final reminder = _reminders[index];
                  double? distance;
                  bool isInside = false;

                  if (_currentPosition != null) {
                    distance = Geolocator.distanceBetween(
                      _currentPosition!.latitude,
                      _currentPosition!.longitude,
                      reminder.latitude,
                      reminder.longitude,
                    );
                    isInside = distance <= reminder.radius;
                  }

                  return Dismissible(
                    key: Key(reminder.id.toString()),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (direction) {
                      _deleteReminder(reminder.id!);
                    },
                    child: Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isInside
                              ? Colors.green.withOpacity(0.2)
                              : Theme.of(context).colorScheme.primaryContainer,
                          child: Icon(
                            isInside ? Icons.my_location : Icons.location_on,
                            color: isInside
                                ? Colors.green
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(
                              reminder.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _getStatusColor(
                                  reminder,
                                ).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: _getStatusColor(reminder),
                                  width: 0.5,
                                ),
                              ),
                              child: Text(
                                _getStatusLabel(reminder),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: _getStatusColor(reminder),
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (reminder.description.isNotEmpty)
                              Text(reminder.description),
                            const SizedBox(height: 4),
                            FutureBuilder<Map<String, dynamic>?>(
                              future: _getSnoozeInfo(reminder),
                              builder: (context, snapshot) {
                                final snoozeInfo = snapshot.data;
                                final isSnoozed =
                                    snoozeInfo?['isSnoozed'] == true;

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (isSnoozed) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: Colors.orange,
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.snooze,
                                              size: 16,
                                              color: Colors.orange,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              _formatSnoozeDuration(
                                                snoozeInfo!['remaining']
                                                    as Duration,
                                              ),
                                              style: const TextStyle(
                                                color: Colors.orange,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                    ],
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.near_me,
                                          size: 14,
                                          color: Colors.grey[600],
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            distance != null
                                                ? "${_formatDistance(distance)} away"
                                                : "Calculated...",
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Icon(
                                          Icons.radar,
                                          size: 14,
                                          color: Colors.grey[600],
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          "Radius: ${reminder.radius.toInt()}m",
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                        trailing: Switch(
                          value: reminder.isActive,
                          onChanged: (val) => _toggleActive(reminder),
                        ),
                        isThreeLine: true,
                      ),
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.pushNamed(context, '/add');
          _loadReminders();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
