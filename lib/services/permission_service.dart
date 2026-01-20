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
    var status = await Permission.ignoreBatteryOptimizations.status;
    if (status.isDenied) {
      status = await Permission.ignoreBatteryOptimizations.request();
    }
    return status.isGranted;
  }

  Future<bool> requestSystemAlertWindow() async {
    var status = await Permission.systemAlertWindow.status;
    if (status.isDenied) {
      status = await Permission.systemAlertWindow.request();
    }
    return status.isGranted;
  }

  Future<bool> checkPermissions() async {
    return await Permission.locationAlways.isGranted &&
        await Permission.notification.isGranted;
  }
}
