import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/audio_service.dart';
import '../services/websocket_service.dart';
import '../services/cost_history_service.dart';

class VoiceOnlyScreen extends StatefulWidget {
  final String voiceKey;
  final String voiceName;
  final Color voiceColor;

  const VoiceOnlyScreen({
    super.key,
    required this.voiceKey,
    required this.voiceName,
    required this.voiceColor,
  });

  @override
  State<VoiceOnlyScreen> createState() => _VoiceOnlyScreenState();
}

class _VoiceOnlyScreenState extends State<VoiceOnlyScreen>
    with TickerProviderStateMixin {
  final AudioService _audioService = AudioService();
  final WebSocketService _wsService = WebSocketService();

  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isRecording = false;
  bool _isAiThinking = false;
  bool _isAiSpeaking = false;
  String _statusText = 'Tap to connect';
  String _lastTranscript = '';

  late final String _serverUrl;
  late AnimationController _orbController;
  late AnimationController _waveController;
  StreamSubscription<Uint8List>? _audioStreamSub;

  @override
  void initState() {
    super.initState();
    _serverUrl = 'ws://192.168.1.3:8000/ws/voice/${widget.voiceKey}';
    _orbController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _orbController.dispose();
    _waveController.dispose();
    _audioStreamSub?.cancel();
    _audioService.dispose();
    _wsService.disconnect();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() => _isConnecting = true);

    try {
      _wsService.onMessage = _handleServerMessage;
      _wsService.onAudioData = _handleAudioData;
      _wsService.onDisconnected = () {
        if (mounted) {
          setState(() {
            _isConnected = false;
            _isRecording = false;
            _statusText = 'Disconnected — tap to reconnect';
          });
        }
      };

      await _wsService.connect(_serverUrl);
      setState(() {
        _isConnected = true;
        _isConnecting = false;
        _statusText = 'Listening...';
      });

      await _startRecording();
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _statusText = 'Connection failed — tap to retry';
      });
    }
  }

  void _handleServerMessage(ServerMessage msg) {
    switch (msg.type) {
      case 'transcript':
        if (msg.isFinal == true && msg.text != null) {
          setState(() {
            _lastTranscript = msg.text!;
            _statusText = '"${msg.text}"';
          });
        }
        break;

      case 'ai_thinking':
        setState(() {
          _isAiThinking = true;
          _isAiSpeaking = false;
          _statusText = 'Thinking...';
        });
        break;

      case 'ai_text':
        setState(() {
          _isAiThinking = false;
          _isAiSpeaking = true;
          _statusText = '${widget.voiceName} is speaking...';
        });
        break;

      case 'audio_done':
        setState(() => _isAiSpeaking = false);
        _audioService.playBufferedAudio().then((_) {
          if (mounted) {
            setState(() => _statusText = 'Listening...');
          }
          _ensureRecording();
        });
        break;

      case 'stop_audio':
        _audioService.stopPlayback();
        setState(() {
          _isAiSpeaking = false;
          _statusText = 'Listening...';
        });
        break;

      case 'session_summary':
        if (msg.raw != null) {
          final session = SessionCostData.fromServerMessage(msg.raw!);
          CostHistoryService.addSession(session);
        }
        break;

      case 'error':
        setState(() {
          _isAiThinking = false;
          _isAiSpeaking = false;
          _statusText = 'Error — try again';
        });
        break;
    }
  }

  void _handleAudioData(Uint8List data) {
    _audioService.addAudioChunk(data);
  }

  Future<void> _startRecording() async {
    if (_isRecording) return;
    try {
      final stream = await _audioService.startRecording();
      _audioStreamSub = stream.listen((audioData) {
        _wsService.sendAudio(audioData);
      });
      setState(() => _isRecording = true);
    } catch (e) {
      // Silently fail — will retry
    }
  }

  Future<void> _stopRecording() async {
    await _audioStreamSub?.cancel();
    _audioStreamSub = null;
    await _audioService.stopRecording();
    setState(() => _isRecording = false);
  }

  Future<void> _ensureRecording() async {
    if (!_isConnected) return;
    await _audioStreamSub?.cancel();
    _audioStreamSub = null;
    if (_audioService.isRecording) {
      await _audioService.stopRecording();
    }
    setState(() => _isRecording = false);
    await _startRecording();
  }

  Future<void> _disconnect() async {
    await _stopRecording();
    await _audioService.stopPlayback();
    // Request cost summary before disconnecting
    if (_wsService.isConnected) {
      _wsService.sendRequestSummary();
      // Give server a moment to respond
      await Future.delayed(const Duration(milliseconds: 500));
    }
    await _wsService.disconnect();
    setState(() {
      _isConnected = false;
      _isAiSpeaking = false;
      _isAiThinking = false;
      _statusText = 'Tap to connect';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      _disconnect();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  const Spacer(),
                  Text(
                    widget.voiceName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  // Connection indicator
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Icon(
                      Icons.circle,
                      size: 10,
                      color: _isConnected ? Colors.greenAccent : Colors.red,
                    ),
                  ),
                ],
              ),
            ),

            // Main area — orb
            Expanded(
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    if (!_isConnected && !_isConnecting) {
                      _connect();
                    }
                  },
                  child: _buildOrb(),
                ),
              ),
            ),

            // Status text
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _statusText,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 15,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            const SizedBox(height: 32),

            // Bottom controls
            if (_isConnected)
              Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Mute button
                    _ControlButton(
                      icon: _isRecording
                          ? Icons.mic_rounded
                          : Icons.mic_off_rounded,
                      color: _isRecording
                          ? widget.voiceColor
                          : Colors.white.withValues(alpha: 0.3),
                      onTap: () async {
                        if (_isRecording) {
                          await _stopRecording();
                          setState(() => _statusText = 'Muted');
                        } else {
                          await _startRecording();
                          setState(() => _statusText = 'Listening...');
                        }
                      },
                    ),
                    const SizedBox(width: 40),
                    // End call
                    _ControlButton(
                      icon: Icons.call_end_rounded,
                      color: Colors.red,
                      onTap: () async {
                        await _disconnect();
                        if (mounted) Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              )
            else
              const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildOrb() {
    return AnimatedBuilder(
      animation: Listenable.merge([_orbController, _waveController]),
      builder: (context, child) {
        final orbSize = _getOrbSize();
        final glowRadius = _getGlowRadius();
        final color = widget.voiceColor;

        return SizedBox(
          width: 250,
          height: 250,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer glow rings (when speaking/listening)
              if (_isRecording || _isAiSpeaking)
                ...List.generate(3, (i) {
                  final delay = i * 0.3;
                  final progress =
                      ((_waveController.value + delay) % 1.0);
                  final scale = 1.0 + progress * 0.6;
                  final opacity = (1.0 - progress) * 0.15;
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: orbSize,
                      height: orbSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color.withValues(alpha: opacity),
                          width: 2,
                        ),
                      ),
                    ),
                  );
                }),

              // Main orb glow
              Container(
                width: orbSize + glowRadius,
                height: orbSize + glowRadius,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: glowRadius,
                      spreadRadius: glowRadius * 0.3,
                    ),
                  ],
                ),
              ),

              // Main orb
              Container(
                width: orbSize,
                height: orbSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      color.withValues(alpha: 0.9),
                      color.withValues(alpha: 0.5),
                      color.withValues(alpha: 0.2),
                    ],
                    stops: const [0.0, 0.6, 1.0],
                  ),
                ),
              ),

              // Inner highlight
              Container(
                width: orbSize * 0.5,
                height: orbSize * 0.5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.3),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),

              // Connecting spinner
              if (_isConnecting)
                SizedBox(
                  width: orbSize * 0.4,
                  height: orbSize * 0.4,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),

              // Not connected icon
              if (!_isConnected && !_isConnecting)
                Icon(
                  Icons.touch_app_rounded,
                  color: Colors.white.withValues(alpha: 0.7),
                  size: 40,
                ),

              // Thinking dots
              if (_isAiThinking)
                const _ThinkingDots(),
            ],
          ),
        );
      },
    );
  }

  double _getOrbSize() {
    if (_isAiSpeaking) {
      return 120 + sin(_orbController.value * 2 * pi) * 10;
    }
    if (_isRecording) {
      return 110 + sin(_orbController.value * 2 * pi) * 5;
    }
    if (_isAiThinking) {
      return 105 + sin(_orbController.value * 3 * pi) * 8;
    }
    return 100;
  }

  double _getGlowRadius() {
    if (_isAiSpeaking) return 40 + sin(_orbController.value * 2 * pi) * 15;
    if (_isRecording) return 20 + sin(_orbController.value * 2 * pi) * 8;
    if (_isAiThinking) return 25;
    return 10;
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.2),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Icon(icon, color: color, size: 28),
      ),
    );
  }
}

class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.2;
            final progress = ((_controller.value + delay) % 1.0);
            final opacity = 0.3 + sin(progress * pi) * 0.7;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: opacity),
              ),
            );
          }),
        );
      },
    );
  }
}
