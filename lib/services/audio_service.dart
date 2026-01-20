import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();

  factory AudioService() {
    return _instance;
  }

  AudioService._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  bool _isUsingNativeSound = false;
  static const platform = MethodChannel('com.smart_alarm_manager/settings');

  bool get isPlaying => _isPlaying;

  Stream<void> get onPlayerComplete => _audioPlayer.onPlayerComplete;
  Stream<PlayerState> get onPlayerStateChanged =>
      _audioPlayer.onPlayerStateChanged;

  Future<void> playAlarm() async {
    // If already playing, stop the current alarm to restart with the new one
    if (_isPlaying) {
      await stopAlarm();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs
        .reload(); // Force reload from disk to get latest settings from UI
    final bool vibrationEnabled = prefs.getBool('vibration_enabled') ?? true;
    final bool soundEnabled = prefs.getBool('sound_enabled') ?? true;
    final String? alarmSoundPath = prefs.getString('alarm_sound_path');

    _isPlaying = true;

    if (vibrationEnabled) {
      _startVibrationLoop();
    }

    if (soundEnabled) {
      if (alarmSoundPath != null) {
        try {
          if (alarmSoundPath.startsWith('content://')) {
            // System Ringtone - Use native Android RingtoneManager
            _isUsingNativeSound = true;
            await platform.invokeMethod('playAlarmSound', {
              'uri': alarmSoundPath,
            });
          } else if (File(alarmSoundPath).existsSync()) {
            // Custom File - Use audioplayers
            _isUsingNativeSound = false;
            _audioPlayer.setReleaseMode(ReleaseMode.loop);
            await _audioPlayer.play(DeviceFileSource(alarmSoundPath));
          }
        } catch (e) {
          print("Error playing sound: $e");
        }
      } else {
        // Default behavior: Use system default alarm sound
        _isUsingNativeSound = true;
        try {
          await platform.invokeMethod('playAlarmSound', {
            'uri': null, // Null triggers default sound in MainActivity
          });
        } catch (e) {
          print("Error playing default sound: $e");
        }
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

  Future<void> playSoundPreview(String path) async {
    // Stop any existing playback
    await _audioPlayer.stop();
    _audioPlayer.setReleaseMode(ReleaseMode.stop); // Don't loop for preview

    try {
      if (path.startsWith('content://')) {
        await _audioPlayer.play(UrlSource(path));
      } else if (File(path).existsSync()) {
        await _audioPlayer.play(DeviceFileSource(path));
      }
    } catch (e) {
      print("Error playing preview: $e");
    }
  }

  Future<void> stopPreview() async {
    await _audioPlayer.stop();
  }

  Future<void> stopAlarm() async {
    _isPlaying = false;

    // Stop native sound if it was being used
    if (_isUsingNativeSound) {
      try {
        await platform.invokeMethod('stopAlarmSound');
      } catch (e) {
        print("Error stopping native sound: $e");
      }
      _isUsingNativeSound = false;
    }

    // Stop audioplayer
    await _audioPlayer.stop();

    // Cancel vibration
    Vibration.cancel();
  }
}
