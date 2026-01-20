import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_alarm_manager/data/reminder_repository.dart';
import 'package:smart_alarm_manager/services/notification_service.dart';
import 'package:smart_alarm_manager/services/audio_service.dart';

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

  // Get continuous stream
  StreamSubscription<Position>? positionStream;

  const LocationSettings locationSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10, // Check every 10 meters
  );

  positionStream =
      Geolocator.getPositionStream(locationSettings: locationSettings).listen(
        (Position position) async {
          // if (service is AndroidServiceInstance) {
          //   if (await service.isForegroundService()) {
          //     service.setForegroundNotificationInfo(
          //       title: "Smart Alarm Manager",
          //       content:
          //           "Tracking Location: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}",
          //     );
          //   }
          // }

          // Check Geofences
          try {
            final reminders = await repository.getReminders();
            // Filter only active reminders
            final activeReminders = reminders.where((r) => r.isActive).toList();

            for (var reminder in activeReminders) {
              double distance = Geolocator.distanceBetween(
                position.latitude,
                position.longitude,
                reminder.latitude,
                reminder.longitude,
              );

              // Check radius
              if (distance <= reminder.radius) {
                // Inside
                if (!triggeredReminderIds.contains(reminder.id)) {
                  final AudioService audioService = AudioService();

                  // SKIP if already playing an alarm
                  if (audioService.isPlaying) {
                    continue;
                  }

                  // Enter Event
                  triggeredReminderIds.add(reminder.id!);

                  // Check Notification Preference
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.reload(); // Force reload from disk
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

                  // Trigger Audio/Vibration
                  // AudioService is singleton, already checked above
                  await audioService.playAlarm();

                  // Set State
                  await prefs.setBool('is_alarm_active', true);
                  await prefs.setInt('current_alarm_id', reminder.id!);

                  service.invoke('trigger_alarm', {'id': reminder.id});
                }
              } else {
                // Outside
                if (triggeredReminderIds.contains(reminder.id)) {
                  // Exit Event - Reset trigger
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
    await AudioService().stopAlarm();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_alarm_active', false);
  });

  service.on('stopService').listen((event) {
    service.stopSelf();
    positionStream?.cancel();
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
  }
}
