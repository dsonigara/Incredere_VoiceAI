import 'package:flutter/material.dart';
import 'voice_chat_screen.dart';
import 'voice_only_screen.dart';
import 'cost_history_screen.dart';

class VoiceOption {
  final String key;
  final String name;
  final String gender;
  final String description;
  final IconData icon;
  final Color color;

  const VoiceOption({
    required this.key,
    required this.name,
    required this.gender,
    required this.description,
    required this.icon,
    required this.color,
  });
}

class VoiceSelectScreen extends StatelessWidget {
  const VoiceSelectScreen({super.key});

  static const voices = [
    VoiceOption(
      key: 'aria',
      name: 'Aria',
      gender: 'Female',
      description: 'Warm, natural & conversational',
      icon: Icons.face_3_rounded,
      color: Color(0xFF8B5CF6),
    ),
    VoiceOption(
      key: 'max',
      name: 'Max',
      gender: 'Male',
      description: 'Friendly, clear & engaging',
      icon: Icons.face_rounded,
      color: Color(0xFF2563EB),
    ),
  ];

  void _showModeChoice(BuildContext context, VoiceOption voice) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Talk with ${voice.name}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose conversation mode',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),

            // Voice Only mode
            _ModeCard(
              icon: Icons.graphic_eq_rounded,
              title: 'Voice Mode',
              subtitle: 'Just talk — like a real conversation',
              color: voice.color,
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VoiceOnlyScreen(
                      voiceKey: voice.key,
                      voiceName: voice.name,
                      voiceColor: voice.color,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // Chat mode
            _ModeCard(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Chat Mode',
              subtitle: 'Voice with text transcript',
              color: voice.color,
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VoiceChatScreen(voiceKey: voice.key),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const CostHistoryScreen()),
                  ),
                  icon: const Icon(Icons.receipt_long_rounded),
                  color: Colors.white.withValues(alpha: 0.5),
                  tooltip: 'Cost History',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Incredere VoiceAI',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose your AI voice companion',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 60),
              ...voices.map((voice) => Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: _VoiceCard(
                  voice: voice,
                  onTap: () => _showModeChoice(context, voice),
                ),
              )),
              const Spacer(),
              Text(
                'Powered by Incredere Services',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.15),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white.withValues(alpha: 0.3),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceCard extends StatelessWidget {
  final VoiceOption voice;
  final VoidCallback onTap;

  const _VoiceCard({required this.voice, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              voice.color.withValues(alpha: 0.2),
              voice.color.withValues(alpha: 0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: voice.color.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: voice.color.withValues(alpha: 0.2),
              ),
              child: Icon(voice.icon, color: voice.color, size: 36),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    voice.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    voice.gender,
                    style: TextStyle(
                      color: voice.color,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    voice.description,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white.withValues(alpha: 0.3),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
