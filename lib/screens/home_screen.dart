import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
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

class _HomeScreenState extends State<HomeScreen> {
  final ReminderRepository _repository = ReminderRepository();
  List<Reminder> _reminders = [];
  Position? _currentPosition;
  bool _isLoading = true;
  Timer? _timer;

  @required
  @override
  void initState() {
    super.initState();
    _checkPermissionsAndLoad();
    // Refresh location every 10 seconds to update distances
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) _getCurrentLocation();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkPermissionsAndLoad() async {
    final hasPerms = await PermissionService().checkPermissions();
    if (!hasPerms) {
      await PermissionService().requestLocationPermissions();
      await PermissionService().requestNotificationPermissions();
      await PermissionService().requestIgnoreBatteryOptimizations();

      // Permissions granted, now we can safely start the service
      await LocationService().initialize();
      // Re-initialize and start fresh with permissions
      await LocationService().initialize();
    } else {
      // Permissions already granted.
      final service = FlutterBackgroundService();
      if (!(await service.isRunning())) {
        await LocationService().initialize();
      }
    }

    _loadReminders();
    _getCurrentLocation();

    // Check for advanced reliability permissions
    _checkReliabilityPermissions();
  }

  Future<void> _checkReliabilityPermissions() async {
    // Check if we already have the permissions
    if (await Permission.ignoreBatteryOptimizations.isGranted &&
        await Permission.systemAlertWindow.isGranted) {
      return;
    }

    // Show guide if not mounted
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Optimize Experience'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('For the best alarm reliability, please enable:'),
            SizedBox(height: 12),
            Text(
              '1. Ignore Battery Optimization\n   (Prevents app from being killed in background)',
            ),
            SizedBox(height: 8),
            Text(
              '2. Display Over Other Apps\n   (Allows Alarm screen to show immediately over lock screen)',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await PermissionService().requestIgnoreBatteryOptimizations();
              await PermissionService().requestSystemAlertWindow();
            },
            child: const Text('Fix Now'),
          ),
        ],
      ),
    );
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
    final updated = reminder.copyWith(isActive: !reminder.isActive);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Reminders'),
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
                        title: Text(
                          reminder.title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (reminder.description.isNotEmpty)
                              Text(reminder.description),
                            const SizedBox(height: 4),
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
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.pushNamed(context, '/add');
          _loadReminders();
        },
        label: const Text('Add Reminder'),
        icon: const Icon(Icons.add),
      ),
    );
  }
}
