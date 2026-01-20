import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();

  factory AudioService() {
    return _instance;
  }

  AudioService._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;

  bool get isPlaying => _isPlaying;

  Future<void> playAlarm() async {
    if (_isPlaying) return;

    final prefs = await SharedPreferences.getInstance();
    final bool vibrationEnabled = prefs.getBool('vibration_enabled') ?? true;
    final bool soundEnabled = prefs.getBool('sound_enabled') ?? true;
    final String? alarmSoundPath = prefs.getString('alarm_sound_path');

    _isPlaying = true;

    if (vibrationEnabled) {
      _startVibrationLoop();
    }

    if (soundEnabled) {
      _audioPlayer.setReleaseMode(ReleaseMode.loop);

      if (alarmSoundPath != null) {
        try {
          if (alarmSoundPath.startsWith('content://')) {
            // System Ringtone
            await _audioPlayer.play(UrlSource(alarmSoundPath));
          } else if (File(alarmSoundPath).existsSync()) {
            // Custom File
            await _audioPlayer.play(DeviceFileSource(alarmSoundPath));
          }
        } catch (e) {
          print("Error playing sound: $e");
        }
      } else {
        // Default behavior: We might want to play a bundled asset or just log.
        // Since we don't have assets configured yet, we rely on the notification sound
        // if push notification is enabled.
        // If push is disabled but sound is enabled, user gets vibration only unless we bundle a sound.
        print("Alarm Sound Triggered (Default/Simulated)");
      }
    }
  }

  void _startVibrationLoop() async {
    if (await Vibration.hasVibrator() ?? false) {
      while (_isPlaying) {
        Vibration.vibrate(
          pattern: [500, 1000, 500, 1000],
          intensities: [1, 255, 1, 255],
        );
        await Future.delayed(const Duration(seconds: 4));
        if (!_isPlaying) break;
      }
    }
  }

  Future<void> stopAlarm() async {
    _isPlaying = false;
    await _audioPlayer.stop();
    Vibration.cancel();
  }
}
