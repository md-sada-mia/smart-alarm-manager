import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'screens/add_reminder_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/alarm_screen.dart';
import 'services/location_service.dart';
import 'services/audio_service.dart';
import 'services/permission_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Services
  // Only start service if permissions are already granted to avoid "zombie" state
  if (await PermissionService().checkPermissions()) {
    await LocationService().initialize();
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StreamSubscription? _serviceSubscription;

  @override
  void initState() {
    super.initState();
    _checkAlarmState();
    _listenToBackgroundService();
  }

  void _listenToBackgroundService() {
    // Listen for events from background service while app is in foreground/background
    _serviceSubscription = FlutterBackgroundService().on('trigger_alarm').listen((
      event,
    ) async {
      if (event != null && event.containsKey('id')) {
        // Bring app to foreground immediately
        try {
          const platform = MethodChannel('com.smart_alarm_manager/settings');
          await platform.invokeMethod('bringToForeground');
        } catch (e) {
          print('Error bringing app to foreground: $e');
        }

        // Play alarm sound/vibration from main isolate (method channels work here)
        await AudioService().playAlarm();

        // Navigate to alarm screen
        _navigateToAlarmScreen(event['id'] as int);
      }
    });
  }

  Future<void> _checkAlarmState() async {
    final prefs = await SharedPreferences.getInstance();
    final bool isAlarmActive = prefs.getBool('is_alarm_active') ?? false;
    final int? reminderId = prefs.getInt('current_alarm_id');

    if (isAlarmActive && reminderId != null) {
      // Small delay to ensure navigator is ready
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateToAlarmScreen(reminderId);
      });
    }
  }

  void _navigateToAlarmScreen(int reminderId) {
    if (navigatorKey.currentState != null) {
      // Check if we are already on the alarm screen to avoid duplicates
      // This is a bit tricky without route checking, but we can just pushReplacement
      // or push and let the user handle it.
      // Simplified: Just push.
      navigatorKey.currentState!.pushNamed('/alarm', arguments: reminderId);
    }
  }

  @override
  void dispose() {
    _serviceSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Alarm Manager',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
        ),
      ),
      themeMode: ThemeMode.system,
      initialRoute: '/',
      onGenerateRoute: (settings) {
        if (settings.name == '/alarm') {
          final id = settings.arguments as int?;
          return MaterialPageRoute(
            builder: (context) => AlarmScreen(reminderId: id),
          );
        }
        return null; // Let main routes checking below handle it? No, routes map takes precedence?
        // Mix of onGenerateRoute and routes can be tricky. Let's use routes for static and onGenerate for dynamic.
      },
      routes: {
        '/': (context) => const HomeScreen(),
        '/add': (context) => const AddReminderScreen(),
        '/settings': (context) => const SettingsScreen(),
        // '/alarm' handled in onGenerateRoute for arguments
      },
    );
  }
}
