import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/aws_bedrock_service.dart';
import 'services/tts_service.dart';

/// Dark slate background used across the app.
const Color kSlate = Color(0xFF0F172A);

/// All layouts are designed on a 1280 x 720 canvas and scaled to the real
/// display, so the UI looks the same on 720p, 1080p and 4K Fire TVs
/// regardless of the density they report.
const double kDesignWidth = 1280;
const double kDesignHeight = 720;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const CareTVApp());
}

class CareTVApp extends StatelessWidget {
  const CareTVApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AWSBedrockService>(
          create: (_) => AWSBedrockService(),
          dispose: (_, AWSBedrockService service) => service.dispose(),
        ),
        Provider<TtsService>(
          lazy: false,
          create: (_) {
            final TtsService tts = TtsService();
            unawaited(tts.init());
            return tts;
          },
          dispose: (_, TtsService service) => service.dispose(),
        ),
      ],
      child: MaterialApp(
        title: 'CareTV AI',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        builder: (BuildContext context, Widget? child) {
          return ColoredBox(
            color: kSlate,
            child: Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: kDesignWidth,
                  height: kDesignHeight,
                  child: child,
                ),
              ),
            ),
          );
        },
        home: const HomeScreen(),
      ),
    );
  }

  ThemeData _buildTheme() {
    final ThemeData base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: kSlate,
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF2DD4BF),
        secondary: Color(0xFF38BDF8),
        surface: Color(0xFF1E293B),
      ),
      splashFactory: NoSplash.splashFactory,
      focusColor: Colors.transparent,
      highlightColor: Colors.transparent,
    );
    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
    );
  }
}
