import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:smart_alarm_manager/data/reminder_repository.dart';
import 'package:smart_alarm_manager/models/reminder.dart';
import 'package:smart_alarm_manager/services/permission_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:smart_alarm_manager/services/location_service.dart';
import 'package:smart_alarm_manager/widgets/permission_guide_card.dart';

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
  bool _showGuidelines = false; // Changed to false default
  bool _isCheckingPermissions = true; // New state for initial check
  Timer? _timer;
  Completer<void>? _resumeCompleter;
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Remove auto-trigger. User must tap "Start App" to begin permission flow.
    _checkInitialPermissions();
    // Refresh location every 10 seconds to update distances
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted && !_showGuidelines && !_isCheckingPermissions)
        _getCurrentLocation();
    });
  }

  Future<void> _checkInitialPermissions() async {
    // If permissions already granted, skip guidelines
    final hasPerms = await PermissionService().checkPermissions();
    final batteryOptimized =
        await Permission.ignoreBatteryOptimizations.isGranted;
    final overlayGranted = await Permission.systemAlertWindow.isGranted;

    if (hasPerms && batteryOptimized && overlayGranted) {
      if (mounted) {
        setState(() {
          _showGuidelines = false;
          _isCheckingPermissions = false;
        });
        _initializeResumedApp();
      }
    } else {
      // Show guide
      if (mounted) {
        setState(() {
          _showGuidelines = true;
          _isLoading = false;
          _isCheckingPermissions = false;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resumeCompleter?.complete(); // Clean up
    _timer?.cancel();
    _pageController.dispose();
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

  Future<void> _startPermissionFlow() async {
    // 1. Location & Notifications
    final hasPerms = await PermissionService().checkPermissions();
    if (!hasPerms) {
      await PermissionService().requestLocationPermissions();
      await PermissionService().requestNotificationPermissions();
    }

    // 2. Reliability (Battery & Overlay)
    await _checkReliabilityPermissions();

    // 3. Initialize App
    if (mounted) {
      setState(() => _showGuidelines = false);
      await _initializeResumedApp();
    }
  }

  Future<void> _initializeResumedApp() async {
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

      // 1. Handle Battery Optimization
      if (!batteryOptimized) {
        await PermissionService().requestIgnoreBatteryOptimizations();
        await Future.delayed(const Duration(milliseconds: 500));
        batteryOptimized =
            await Permission.ignoreBatteryOptimizations.isGranted;
      }

      // 2. Handle Overlay
      if (!overlayGranted) {
        await PermissionService().requestSystemAlertWindow();
        await _waitForResume();
        await Future.delayed(const Duration(seconds: 1));
        overlayGranted = await Permission.systemAlertWindow.isGranted;
      }

      // If user cancels, we break loop or show small alert?
      // To strictly enforce, we loop. To be gentle, we check once more.
      if (!batteryOptimized || !overlayGranted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text("Permissions Missing"),
            content: const Text(
              "These permissions are required. Please try again.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Retry"),
              ),
            ],
          ),
        );
      }
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

  Widget _buildWelcomeGuide() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                "Setup Guide",
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (int page) {
                  setState(() => _currentPage = page);
                },
                children: [
                  _VerticalSwipeDetector(
                    onSwipeUp: () {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: const PermissionGuideCard(
                      title: "Required Location Permission",
                      description:
                          "Select 'Allow all the time' to enable background tracking.",
                      icon: Icons.location_on,
                      iconColor: Colors.red,
                      imagePath:
                          'assets/images/location-allow-all-the-time.png',
                    ),
                  ),
                  _VerticalSwipeDetector(
                    onSwipeUp: () {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                    onSwipeDown: () {
                      _pageController.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: const PermissionGuideCard(
                      title: "Find App in List",
                      description:
                          "Locate 'Smart Alarm Manager' in the 'Display over other apps' list.",
                      icon: Icons.list_alt,
                      iconColor: Colors.purple,
                      imagePath: 'assets/images/over-the-app-list.png',
                    ),
                  ),
                  _VerticalSwipeDetector(
                    onSwipeDown: () {
                      _pageController.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: const PermissionGuideCard(
                      title: "Enable Display Overlay",
                      description:
                          "Toggle the switch to ON to allow alarm screen to appear.",
                      icon: Icons.toggle_on,
                      iconColor: Colors.green,
                      imagePath: 'assets/images/over-the-app-switch.png',
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                3,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentPage == index
                        ? Colors.blue
                        : Colors.grey.shade300,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: _startPermissionFlow,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text("Start App & Grant Permissions"),
                  style: FilledButton.styleFrom(
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingPermissions) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_showGuidelines) {
      return _buildWelcomeGuide();
    }

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
            const Text('Smart Alarm Manager'),
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

class _VerticalSwipeDetector extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSwipeUp;
  final VoidCallback? onSwipeDown;

  const _VerticalSwipeDetector({
    required this.child,
    this.onSwipeUp,
    this.onSwipeDown,
  });

  @override
  State<_VerticalSwipeDetector> createState() => _VerticalSwipeDetectorState();
}

class _VerticalSwipeDetectorState extends State<_VerticalSwipeDetector> {
  double _dragDistance = 0.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragStart: (details) {
        _dragDistance = 0.0;
      },
      onVerticalDragUpdate: (details) {
        _dragDistance += details.delta.dy;
      },
      onVerticalDragEnd: (details) {
        // Trigger if swiped far enough (50 logical pixels) OR flung fast enough
        const double distanceThreshold = 50.0;
        const double velocityThreshold = 300.0;

        if (_dragDistance < -distanceThreshold ||
            details.primaryVelocity! < -velocityThreshold) {
          widget.onSwipeUp?.call();
        } else if (_dragDistance > distanceThreshold ||
            details.primaryVelocity! > velocityThreshold) {
          widget.onSwipeDown?.call();
        }
      },
      child: widget.child,
    );
  }
}
