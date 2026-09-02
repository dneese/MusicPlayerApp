import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_service/audio_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/audio_handler.dart';
import 'screens/player_screen.dart';
import 'utils/theme_manager.dart';
import 'utils/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await ThemeManager.init();

  // Always render the UI first so a startup failure can't produce a black screen.
  runApp(const MyApp());

  await _initAudio();
}

Future<void> _initAudio() async {
  await requestStoragePermission();

  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.yourapp.music.player',
      androidNotificationChannelName: 'Music Player',
      androidNotificationOngoing: true,
      notificationColor: Colors.purple,
    );
  } catch (e) {
    startupError = 'Audio init error: $e';
    return;
  }

  try {
    await AudioService.init(
      builder: () => AudioPlayerHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.yourapp.music.player',
        androidNotificationChannelName: 'Music Player',
        androidStopForegroundOnPause: true,
        notificationColor: Colors.purple,
      ),
    );
    audioReady = true;
  } catch (e) {
    startupError = 'Audio service error: $e';
  }
}

Future<void> requestStoragePermission() async {
  try {
    var status = await Permission.storage.request();
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }
  } catch (e) {
    startupError = 'Permission error: $e';
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: ThemeManager.themeNotifier,
      builder: (context, themeMode, child) {
        return MaterialApp(
          title: 'Music Player Pro',
          debugShowCheckedModeBanner: false,
          theme: ThemeManager.lightTheme,
          darkTheme: ThemeManager.darkTheme,
          themeMode: themeMode,
          home: const PlayerScreen(),
        );
      },
    );
  }
}
