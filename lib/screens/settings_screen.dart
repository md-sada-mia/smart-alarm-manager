import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart'; // For PlayerState
import 'package:smart_alarm_manager/services/audio_service.dart';

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
  bool _isPreviewPlaying = false; // Track preview state locally

  @override
  void initState() {
    super.initState();
    _loadSettings();

    // Listen to player completion to reset icon
    AudioService().onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPreviewPlaying = false;
        });
      }
    });

    // We can also listen to state changes if needed, but completion is usually enough for one-shot.
    // However, if we stop manually, we also want to update.
    AudioService().onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPreviewPlaying = state == PlayerState.playing;
        });
      }
    });
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
                    title: const Text('Alarm Sound'),
                    subtitle: Text(
                      _alarmSoundPath != null
                          ? (_alarmSoundPath!.startsWith('content://')
                                ? (Uri.tryParse(
                                        _alarmSoundPath!,
                                      )?.queryParameters['title'] ??
                                      'System Info')
                                : _alarmSoundPath!
                                      .split('/')
                                      .last
                                      .replaceAll('%20', ' '))
                          : 'Select an alarm sound',
                    ),
                    leading: const Icon(Icons.music_note),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_alarmSoundPath != null)
                          IconButton(
                            icon: const Icon(
                              Icons.play_circle_fill,
                              color: Colors.deepPurple,
                            ),
                            onPressed: () => _previewSound(_alarmSoundPath!),
                          ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: _showSoundSourceDialog,
                  ),
                const Divider(),
                const ListTile(
                  title: Text('About'),
                  subtitle: Text('Smart Alarm Manager v1.2.0'),
                  leading: Icon(Icons.info),
                ),
              ],
            ),
    );
  }

  Future<void> _pickSystemRingtone() async {
    try {
      const platform = MethodChannel('com.smart_alarm_manager/settings');
      final String? path = await platform.invokeMethod('pickSystemRingtone');

      if (path != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('alarm_sound_path', path);
        setState(() {
          _alarmSoundPath = path;
        });

        // Auto-play preview
        _previewSound(path);
      }
    } catch (e) {
      print("Error picking system ringtone: $e");
    }
  }

  Future<void> _showSoundSourceDialog() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Choose/Select Alarm Sound',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.alarm),
                title: const Text('System Ringtone'),
                subtitle: const Text('Built-in Android alarm sounds'),
                onTap: () {
                  Navigator.pop(context);
                  _pickSystemRingtone();
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('Custom Audio File'),
                subtitle: const Text('Select mp3/wav from storage'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAlarmSound();
                },
              ),
              if (_alarmSoundPath != null)
                ListTile(
                  leading: const Icon(Icons.clear, color: Colors.red),
                  title: const Text('Clear Selection'),
                  onTap: () {
                    Navigator.pop(context);
                    _clearAlarmSound();
                  },
                ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Future<void> _previewSound(String path) async {
    final audioService = AudioService();
    // System Ringtone Preview using Native Channel
    if (path.startsWith('content://')) {
      const platform = MethodChannel('com.smart_alarm_manager/settings');
      try {
        if (_isPreviewPlaying) {
          await platform.invokeMethod('stopSystemRingtone');
          setState(() => _isPreviewPlaying = false);
        } else {
          await platform.invokeMethod('playSystemRingtone', {'uri': path});
          setState(() => _isPreviewPlaying = true);
          // Note: Native ringtone doesn't give us a callback when done easily.
          // We might want to auto-reset the icon after a few seconds or just let user stop it.
        }
      } catch (e) {
        print("Native preview error: $e");
      }
      return;
    }

    // Custom File Preview using AudioPlayer
    if (_isPreviewPlaying) {
      await audioService.stopPreview();
    } else {
      await audioService.playSoundPreview(path);
    }
  }
}
