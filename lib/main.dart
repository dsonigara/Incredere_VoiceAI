import 'package:flutter/material.dart';
import 'screens/voice_select_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IncredereVoiceAIApp());
}

class IncredereVoiceAIApp extends StatelessWidget {
  const IncredereVoiceAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Incredere VoiceAI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF2563EB),
        scaffoldBackgroundColor: const Color(0xFF0A0A1A),
      ),
      home: const VoiceSelectScreen(),
    );
  }
}
