import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/audio_handler.dart';
import 'screens/player_screen.dart';
import 'utils/theme_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await ThemeManager.init();

  // Playback uses a plain in-process just_audio player (see AudioPlayerHandler).
  // It needs no background service, so it ALWAYS works the moment the UI
  // attaches, and tap-to-play can never fail with an uninitialized handler.
  final handler = AudioPlayerHandler();
  AudioPlayerHandler.instance = handler;
  handlerNotifier.value = handler;

  try {
    await Permission.storage.request();
  } catch (_) {}

  runApp(const MyApp());
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