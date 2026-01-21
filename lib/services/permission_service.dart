import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
// import 'package:android_intent_plus/flag.dart'; // Not needed for flags here
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  Future<bool> requestLocationPermissions() async {
    // Request foreground location
    var status = await Permission.locationWhenInUse.request();
    if (status.isGranted) {
      // Request background location
      // Note: On Android 10+, this might require separate request or user selection
      var bgStatus = await Permission.locationAlways.request();
      if (bgStatus.isGranted) {
        return true;
      }
    }
    return false;
  }

  Future<bool> requestNotificationPermissions() async {
    // Android 13+ requires notification permission
    var status = await Permission.notification.request();
    return status.isGranted;
  }

  Future<bool> requestExactAlarmPermission() async {
    // Android 12+ requires exact alarm permission for scheduling
    var status = await Permission.scheduleExactAlarm.status;
    if (status.isDenied) {
      status = await Permission.scheduleExactAlarm.request();
    }
    return status.isGranted;
  }

  Future<bool> requestIgnoreBatteryOptimizations() async {
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }
    return await Permission.ignoreBatteryOptimizations.isGranted;
  }

  Future<bool> requestSystemAlertWindow() async {
    // Try to open specific app settings first for better UX
    if (await Permission.systemAlertWindow.isDenied) {
      if (Platform.isAndroid) {
        final intent = AndroidIntent(
          action: 'android.settings.action.MANAGE_OVERLAY_PERMISSION',
          data: 'package:com.smart_alarm_manager.smart_alarm_manager',
        );
        await intent.launch();
        // Wait for user to return
        await Future.delayed(const Duration(seconds: 1));
      } else {
        await Permission.systemAlertWindow.request();
      }
    }
    return await Permission.systemAlertWindow.isGranted;
  }

  Future<bool> checkPermissions() async {
    return await Permission.locationAlways.isGranted &&
        await Permission.notification.isGranted;
  }
}
