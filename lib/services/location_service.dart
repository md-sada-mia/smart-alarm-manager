import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_alarm_manager/data/reminder_repository.dart';
import 'package:smart_alarm_manager/models/reminder.dart';
import 'package:smart_alarm_manager/services/notification_service.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'dart:io';

// Top-level entry points for background service
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Re-initialize necessary services in background isolate
  DartPluginRegistrant.ensureInitialized();

  // We need a way to access DB. Repository creates new DB helper instance which is fine.
  final ReminderRepository repository = ReminderRepository();
  final NotificationService notificationService = NotificationService();

  await notificationService.init();

  // State to track triggered fences to avoid duplicates
  final Set<int> triggeredReminderIds = {};

  // State to track snoozed alarms to prevent re-triggering during snooze
  final Set<int> snoozedReminderIds = {};

  // Get continuous stream
  StreamSubscription<Position>? positionStream;

  const LocationSettings locationSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10, // Check every 10 meters
  );

  positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
    (Position position) async {
      // Check Geofences
      try {
        final reminders = await repository.getReminders();
        // Filter only active reminders
        final activeReminders = reminders.where((r) => r.isActive).toList();

        for (var reminder in activeReminders) {
          // Skip if this reminder is currently snoozed
          if (snoozedReminderIds.contains(reminder.id)) {
            continue; // Don't trigger while snoozed
          }

          // Check Days (if set)
          if (reminder.days != null && reminder.days!.isNotEmpty) {
            final now = DateTime.now();
            if (!reminder.days!.contains(now.weekday)) {
              continue; // Skip if today is not in selected days
            }
          }

          // Check Time Range (if set)
          bool timeConditionMet = true;
          if (reminder.startTime != null && reminder.endTime != null) {
            final now = DateTime.now();
            final nowMinutes = now.hour * 60 + now.minute;

            try {
              final startParts = reminder.startTime!.split(':');
              final endParts = reminder.endTime!.split(':');

              final startMinutes =
                  int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
              final endMinutes =
                  int.parse(endParts[0]) * 60 + int.parse(endParts[1]);

              if (startMinutes < endMinutes) {
                // Normal range (e.g., 09:00 to 17:00)
                timeConditionMet =
                    nowMinutes >= startMinutes && nowMinutes <= endMinutes;
              } else {
                // Spanning midnight (e.g., 22:00 to 06:00)
                timeConditionMet =
                    nowMinutes >= startMinutes || nowMinutes <= endMinutes;
              }
            } catch (e) {
              print("Error parsing time range for reminder ${reminder.id}: $e");
              timeConditionMet = true;
            }
          }

          if (!timeConditionMet) continue;

          double distance = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            reminder.latitude,
            reminder.longitude,
          );

          // Check radius with smart accuracy filtering
          if (distance <= reminder.radius) {
            // INSIDE

            // For triggering (Entering), we want decent accuracy
            // Allow accuracy up to 75% of the radius or 150m, whichever is tighter
            // This prevents triggering if accuracy is like 500m
            double maxTriggerAccuracy = (reminder.radius * 0.75).clamp(
              50.0,
              150.0,
            );
            if (position.accuracy > maxTriggerAccuracy) {
              print(
                "Skipping trigger for ${reminder.title} due to poor accuracy: ${position.accuracy}",
              );
              continue;
            }

            if (!triggeredReminderIds.contains(reminder.id)) {
              // Enter Event - Force stop any existing alarm first
              print(
                "Triggering alarm for ${reminder.title}. Clearing previous triggers.",
              );

              // Clear state of other alarms to ensure this one takes precedence
              triggeredReminderIds.clear();
              triggeredReminderIds.add(reminder.id!);

              // Notify main isolate to stop any current audio/screen
              service.invoke('stop_alarm');
              // Short delay to allow cleanup before trigger
              await Future.delayed(const Duration(milliseconds: 200));

              // Check Notification Preference
              final prefs = await SharedPreferences.getInstance();
              await prefs.reload();
              final bool showNotification =
                  prefs.getBool('push_notification_enabled') ?? true;

              if (showNotification) {
                await notificationService.showNotification(
                  id: reminder.id!,
                  title: "Arrived: ${reminder.title}",
                  body: reminder.description.isNotEmpty
                      ? reminder.description
                      : "You are within ${reminder.radius.toInt()}m",
                );
              }

              // Set State
              await prefs.setBool('is_alarm_active', true);
              await prefs.setInt('current_alarm_id', reminder.id!);

              // Notify main isolate to play alarm and show screen
              service.invoke('trigger_alarm', {'id': reminder.id});

              // Force launch app
              try {
                if (Platform.isAndroid) {
                  final intent = AndroidIntent(
                    action: 'android.intent.action.MAIN',
                    category: 'android.intent.category.LAUNCHER',
                    package: 'com.smart_alarm_manager.smart_alarm_manager',
                    componentName:
                        'com.smart_alarm_manager.smart_alarm_manager.MainActivity',
                    flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
                    arguments: {
                      'show_on_lock': true,
                      'reminder_id': reminder.id,
                    },
                  );
                  await intent.launch();
                }
              } catch (e) {
                print("Error forcing app launch: $e");
              }
            }
          } else {
            // OUTSIDE

            // For resetting (Exiting), we are much more lenient with accuracy.
            // If the map says we are 1km away but accuracy is 300m, we are still definitely outside.
            // We only keep the lock if the accuracy is so bad it overlaps with the radius.
            bool isDefinitelyOutside =
                distance > (reminder.radius + position.accuracy);

            if (isDefinitelyOutside &&
                triggeredReminderIds.contains(reminder.id)) {
              // Exit Event - Reset trigger
              print("Exiting zone for ${reminder.title}. Resetting trigger.");
              triggeredReminderIds.remove(reminder.id);
            }
          }
        }
      } catch (e) {
        print("Error in background loop: $e");
      }
    },
    onError: (e) {
      print("Location stream error: $e");
    },
  );

  service.on('stop_alarm').listen((event) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_alarm_active', false);
  });

  service.on('snooze_alarm').listen((event) async {
    if (event != null &&
        event.containsKey('reminder_id') &&
        event.containsKey('snooze_minutes')) {
      final int? reminderId = event['reminder_id'] as int?;
      final int snoozeMinutes = event['snooze_minutes'] as int;

      // Clear alarm active state
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_alarm_active', false);

      // Update reminder in database with snooze info
      if (reminderId != null) {
        try {
          final reminder = await repository.getReminder(reminderId);
          if (reminder != null) {
            final snoozeUntil = DateTime.now().add(
              Duration(minutes: snoozeMinutes),
            );
            final updated = reminder.copyWith(
              status: ReminderStatus.snoozed,
              snoozeUntil: snoozeUntil,
            );
            await repository.updateReminder(updated);
          }
        } catch (e) {
          print('Error updating snooze in database: $e');
        }
      }

      // Remove from triggered set to allow re-trigger after snooze
      if (reminderId != null) {
        triggeredReminderIds.remove(reminderId);

        // Add to snoozed set to prevent re-triggering during snooze period
        snoozedReminderIds.add(reminderId);
      }

      // Schedule a timer to re-trigger the alarm
      Timer(Duration(minutes: snoozeMinutes), () async {
        // Re-trigger the alarm after snooze duration
        await prefs.setBool('is_alarm_active', true);
        if (reminderId != null) {
          await prefs.setInt('current_alarm_id', reminderId);

          // Remove from snoozed set - now it can trigger again
          snoozedReminderIds.remove(reminderId);

          // Update reminder in database - reset to active status
          try {
            final reminder = await repository.getReminder(reminderId);
            if (reminder != null) {
              final updated = reminder.copyWith(
                status: ReminderStatus.active,
                clearSnooze: true, // Clear snoozeUntil
              );
              await repository.updateReminder(updated);
            }
          } catch (e) {
            print('Error resetting snooze in database: $e');
          }

          // Notify main isolate to play alarm and show screen
          service.invoke('trigger_alarm', {'id': reminderId});

          // Force launch app
          try {
            if (Platform.isAndroid) {
              final intent = AndroidIntent(
                action: 'android.intent.action.MAIN',
                category: 'android.intent.category.LAUNCHER',
                package: 'com.smart_alarm_manager.smart_alarm_manager',
                componentName:
                    'com.smart_alarm_manager.smart_alarm_manager.MainActivity',
                flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
                arguments: {'show_on_lock': true, 'reminder_id': reminderId},
              );
              await intent.launch();
            }
          } catch (e) {
            print("Error forcing app launch after snooze: $e");
          }
        }
      });
    }
  });

  service.on('stopService').listen((event) {
    service.stopSelf();
    positionStream?.cancel();
  });

  // Listener to reset state (e.g., on app restart)
  service.on('reset_state').listen((event) {
    print("Background service state reset: clearing triggered reminders");
    triggeredReminderIds.clear();
  });
}

class LocationService {
  static final LocationService _instance = LocationService._internal();

  factory LocationService() => _instance;

  LocationService._internal();

  Future<void> initialize() async {
    final service = FlutterBackgroundService();

    // Ensure notification channel exists in main isolate too for initial setup
    await NotificationService().init();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        // This will be executed in the background isolate
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: NotificationService.channelId,
        initialNotificationTitle: 'Smart Alarm Manager',
        initialNotificationContent: 'Monitoring location...',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    // Reset state on app launch to ensure fresh triggers
    service.invoke('reset_state');
  }
}
