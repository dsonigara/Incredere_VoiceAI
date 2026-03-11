import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/audio_service.dart';
import '../services/websocket_service.dart';
import '../services/cost_history_service.dart';

class VoiceChatScreen extends StatefulWidget {
  final String voiceKey;

  const VoiceChatScreen({super.key, this.voiceKey = 'aria'});

  @override
  State<VoiceChatScreen> createState() => _VoiceChatScreenState();
}

class _VoiceChatScreenState extends State<VoiceChatScreen>
    with TickerProviderStateMixin {
  final AudioService _audioService = AudioService();
  final WebSocketService _wsService = WebSocketService();

  // State
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isRecording = false;
  bool _isAiThinking = false;
  bool _isAiSpeaking = false;

  String _currentTranscript = '';
  String _aiResponse = '';
  final List<_ChatMessage> _messages = [];
  StreamSubscription<Uint8List>? _audioStreamSub;

  // Server URL
  late final String _serverUrl;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _serverUrl = 'ws://192.168.1.3:8000/ws/voice/${widget.voiceKey}';
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
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
        setState(() {
          _isConnected = false;
          _isRecording = false;
        });
      };

      await _wsService.connect(_serverUrl);
      setState(() {
        _isConnected = true;
        _isConnecting = false;
      });

      // Auto-start recording immediately after connecting
      await _startRecording();
    } catch (e) {
      setState(() => _isConnecting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _handleServerMessage(ServerMessage msg) {
    switch (msg.type) {
      case 'transcript':
        setState(() {
          _currentTranscript = msg.text ?? '';
          if (msg.isFinal == true && msg.text != null) {
            // Don't add individual final transcripts — wait for full utterance
          }
        });
        break;

      case 'ai_thinking':
        setState(() {
          // Add user message from accumulated transcript
          if (_currentTranscript.isNotEmpty) {
            _messages.add(_ChatMessage(
              text: _currentTranscript,
              isUser: true,
            ));
            _currentTranscript = '';
          }
          _isAiThinking = true;
          _isAiSpeaking = false;
        });
        break;

      case 'ai_text':
        setState(() {
          _aiResponse = msg.text ?? '';
          _isAiThinking = false;
          _isAiSpeaking = true;
          _messages.add(_ChatMessage(
            text: _aiResponse,
            isUser: false,
          ));
        });
        break;

      case 'audio_done':
        setState(() => _isAiSpeaking = false);
        // Play the buffered audio, then restart mic
        _audioService.playBufferedAudio().then((_) {
          _ensureRecording();
        });
        break;

      case 'stop_audio':
        _audioService.stopPlayback();
        setState(() => _isAiSpeaking = false);
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
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${msg.message}'),
              backgroundColor: Colors.red,
            ),
          );
        }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Mic error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    await _audioStreamSub?.cancel();
    _audioStreamSub = null;
    await _audioService.stopRecording();
    setState(() => _isRecording = false);
  }

  /// Re-start recording if it was interrupted by audio playback.
  Future<void> _ensureRecording() async {
    if (!_isConnected) return;
    // Stop old stream cleanly first
    await _audioStreamSub?.cancel();
    _audioStreamSub = null;
    if (_audioService.isRecording) {
      await _audioService.stopRecording();
    }
    setState(() => _isRecording = false);
    // Start fresh
    await _startRecording();
  }

  Future<void> _toggleMute() async {
    if (!_isConnected) return;

    if (_isRecording) {
      await _stopRecording();
    } else {
      // If AI is speaking, interrupt it
      if (_isAiSpeaking || _audioService.isPlaying) {
        _wsService.sendInterrupt();
        await _audioService.stopPlayback();
        setState(() => _isAiSpeaking = false);
      }
      await _startRecording();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A1A),
        elevation: 0,
        title: const Text(
          'Incredere VoiceAI',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        actions: [
          // Connection indicator
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(
              Icons.circle,
              size: 12,
              color: _isConnected ? Colors.greenAccent : Colors.red,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Chat messages
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    reverse: true,
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg =
                          _messages[_messages.length - 1 - index];
                      return _buildMessageBubble(msg);
                    },
                  ),
          ),

          // Live transcript
          if (_currentTranscript.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 8),
              child: Text(
                _currentTranscript,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),

          // Status indicator
          if (_isAiThinking)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Thinking...',
                style: TextStyle(
                  color: Colors.blueAccent,
                  fontSize: 14,
                ),
              ),
            ),

          // Bottom controls
          _buildBottomControls(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.mic_none_rounded,
            size: 80,
            color: Colors.white.withOpacity(0.15),
          ),
          const SizedBox(height: 16),
          Text(
            _isConnected
                ? 'Tap the mic to start talking'
                : 'Tap Connect to begin',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(_ChatMessage msg) {
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: msg.isUser
              ? const Color(0xFF2563EB)
              : const Color(0xFF1E1E3A),
          borderRadius: BorderRadius.circular(20).copyWith(
            bottomRight:
                msg.isUser ? const Radius.circular(4) : null,
            bottomLeft:
                !msg.isUser ? const Radius.circular(4) : null,
          ),
        ),
        child: Text(
          msg.text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F2A),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: SafeArea(
        child: !_isConnected
            ? // Connect button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isConnecting ? null : _connect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isConnecting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Connect',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              )
            : // Mic button
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Disconnect button
                  IconButton(
                    onPressed: () async {
                      await _stopRecording();
                      // Request cost summary before disconnecting
                      if (_wsService.isConnected) {
                        _wsService.sendRequestSummary();
                        await Future.delayed(const Duration(milliseconds: 500));
                      }
                      await _wsService.disconnect();
                      setState(() {
                        _isConnected = false;
                        _isRecording = false;
                        _isAiSpeaking = false;
                        _isAiThinking = false;
                      });
                    },
                    icon: const Icon(Icons.call_end_rounded),
                    color: Colors.red,
                    iconSize: 28,
                  ),

                  const SizedBox(width: 24),

                  // Main mic button (mute/unmute)
                  GestureDetector(
                    onTap: _toggleMute,
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        final scale = _isRecording
                            ? 1.0 + (_pulseController.value * 0.15)
                            : 1.0;
                        return Transform.scale(
                          scale: scale,
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isRecording
                                  ? Colors.red
                                  : const Color(0xFF2563EB),
                              boxShadow: _isRecording
                                  ? [
                                      BoxShadow(
                                        color: Colors.red
                                            .withOpacity(0.4),
                                        blurRadius: 20,
                                        spreadRadius: 5,
                                      )
                                    ]
                                  : [],
                            ),
                            child: Icon(
                              _isRecording
                                  ? Icons.stop_rounded
                                  : Icons.mic_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(width: 24),

                  // Text input button (for testing)
                  IconButton(
                    onPressed: () => _showTextInput(),
                    icon: const Icon(Icons.keyboard_rounded),
                    color: Colors.white.withOpacity(0.5),
                    iconSize: 28,
                  ),
                ],
              ),
      ),
    );
  }

  void _showTextInput() {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E3A),
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle:
                      TextStyle(color: Colors.white.withOpacity(0.4)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: const Color(0xFF0A0A1A),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isNotEmpty) {
                  _wsService.sendTextInput(text);
                  setState(() {
                    _messages.add(_ChatMessage(text: text, isUser: true));
                    _currentTranscript = '';
                  });
                  Navigator.pop(ctx);
                }
              },
              icon: const Icon(Icons.send_rounded),
              color: const Color(0xFF2563EB),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;

  _ChatMessage({required this.text, required this.isUser});
}
