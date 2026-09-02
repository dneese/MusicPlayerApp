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

  // Initialize background audio with a firm internal timeout; on ANY failure we
  // still get an in-process handler so the UI can always play. This guarantees
  // the "Плеер ещё запускается" state can never occur.
  try {
    await _initAudioService().timeout(const Duration(seconds: 10));
  } catch (_) {
    // Last-resort fallback if the whole future aborted before yielding a handler.
    if (handlerNotifier.value == null) {
      final fallback = AudioPlayerHandler();
      AudioPlayerHandler.instance = fallback;
      handlerNotifier.value = fallback;
    }
  }

  runApp(const MyApp());
}

Future<void> _initAudioService() async {
  AudioPlayerHandler? handler;
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
    handler = (await AudioService.init(
      builder: () => AudioPlayerHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.yourapp.music.player',
        androidNotificationChannelName: 'Music Player',
        androidStopForegroundOnPause: true,
        androidNotificationOngoing: true,
        notificationColor: Color(0xFF7C4DFF),
      ),
    )) as AudioPlayerHandler;
  } catch (e) {
    debugPrint('Audio service init error: $e');
  }

  // Always ensure a handler exists (service-backed or in-process fallback).
  final h = handler ?? AudioPlayerHandler();
  AudioPlayerHandler.instance = h;
  handlerNotifier.value = h;
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