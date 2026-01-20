import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _vibrationEnabled = true;
  bool _soundEnabled = true;
  bool _pushNotificationEnabled = true;
  String? _alarmSoundPath;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _vibrationEnabled = prefs.getBool('vibration_enabled') ?? true;
      _soundEnabled = prefs.getBool('sound_enabled') ?? true;
      _pushNotificationEnabled =
          prefs.getBool('push_notification_enabled') ?? true;
      _alarmSoundPath = prefs.getString('alarm_sound_path');
      _isLoading = false;
    });
  }

  Future<void> _toggleVibration(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vibration_enabled', value);
    setState(() => _vibrationEnabled = value);
  }

  Future<void> _toggleSound(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sound_enabled', value);
    setState(() => _soundEnabled = value);
  }

  Future<void> _togglePushNotification(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('push_notification_enabled', value);
    setState(() => _pushNotificationEnabled = value);
  }

  Future<void> _pickAlarmSound() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
    );

    if (result != null) {
      String? path = result.files.single.path;
      if (path != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('alarm_sound_path', path);
        setState(() {
          _alarmSoundPath = path;
        });
      }
    }
  }

  Future<void> _clearAlarmSound() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('alarm_sound_path');
    setState(() {
      _alarmSoundPath = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                SwitchListTile(
                  title: const Text('Push Notifications'),
                  subtitle: const Text('Show visual notification when arrived'),
                  value: _pushNotificationEnabled,
                  onChanged: _togglePushNotification,
                  secondary: const Icon(Icons.notifications_active),
                ),
                SwitchListTile(
                  title: const Text('Vibration'),
                  subtitle: const Text('Vibrate when entering a geofence'),
                  value: _vibrationEnabled,
                  onChanged: _toggleVibration,
                  secondary: const Icon(Icons.vibration),
                ),
                SwitchListTile(
                  title: const Text('Alarm Sound'),
                  subtitle: const Text('Play sound when entering a geofence'),
                  value: _soundEnabled,
                  onChanged: _toggleSound,
                  secondary: const Icon(Icons.volume_up),
                ),
                if (_soundEnabled)
                  ListTile(
                    title: const Text('Custom Alarm Tone'),
                    subtitle: Text(
                      _alarmSoundPath != null
                          ? _alarmSoundPath!.split('/').last
                          : 'Default (System Notification Sound)',
                    ),
                    leading: const Icon(Icons.music_note),
                    trailing: _alarmSoundPath != null
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: _clearAlarmSound,
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: _pickAlarmSound,
                  ),
                const Divider(),
                const ListTile(
                  title: Text('About'),
                  subtitle: Text('Smart Alarm Manager v1.1.0'),
                  leading: Icon(Icons.info),
                ),
              ],
            ),
    );
  }
}
