import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_service/audio_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/audio_handler.dart';
import 'screens/player_screen.dart';
import 'utils/theme_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await ThemeManager.init();

  // Initialize the background audio service before showing UI so background
  // playback works and the handler is ready. Use a timeout so a hang can never
  // leave the user on a black screen.
  try {
    await _initAudioService().timeout(const Duration(seconds: 10));
  } catch (_) {
    // Continue to UI even if background service failed.
  }

  runApp(const MyApp());
}

Future<void> _initAudioService() async {
  try {
    await Permission.storage.request();
  } catch (_) {}

  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.yourapp.music.player',
      androidNotificationChannelName: 'Music Player',
      androidNotificationOngoing: true,
      notificationColor: const Color(0xFF7C4DFF),
    );
    final handler = await AudioService.init(
      builder: () => AudioPlayerHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.yourapp.music.player',
        androidNotificationChannelName: 'Music Player',
        androidStopForegroundOnPause: true,
        androidNotificationOngoing: true,
        notificationColor: Color(0xFF7C4DFF),
      ),
    );
    AudioPlayerHandler.instance = handler as AudioPlayerHandler;
    handlerNotifier.value = AudioPlayerHandler.instance;
  } catch (e) {
    debugPrint('Audio service init error: $e');
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