import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Message types from server
class ServerMessage {
  final String type;
  final String? text;
  final bool? isFinal;
  final String? message;
  final Map<String, dynamic>? raw;

  ServerMessage({required this.type, this.text, this.isFinal, this.message, this.raw});

  factory ServerMessage.fromJson(Map<String, dynamic> json) {
    return ServerMessage(
      type: json['type'] as String,
      text: json['text'] as String?,
      isFinal: json['is_final'] as bool?,
      message: json['message'] as String?,
      raw: json,
    );
  }
}

/// Manages WebSocket connection to the backend server.
class WebSocketService {
  WebSocketChannel? _channel;
  bool _isConnected = false;

  // Callbacks
  Function(ServerMessage)? onMessage;
  Function(Uint8List)? onAudioData;
  Function()? onDisconnected;

  bool get isConnected => _isConnected;

  /// Connect to the backend WebSocket server.
  Future<void> connect(String serverUrl) async {
    try {
      final uri = Uri.parse(serverUrl);
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;
      _isConnected = true;

      _channel!.stream.listen(
        (data) {
          if (data is Uint8List) {
            // Binary data = audio from TTS
            onAudioData?.call(data);
          } else if (data is String) {
            // JSON message
            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              final msg = ServerMessage.fromJson(json);
              onMessage?.call(msg);
            } catch (e) {
              // Ignore malformed messages
            }
          }
        },
        onDone: () {
          _isConnected = false;
          onDisconnected?.call();
        },
        onError: (error) {
          _isConnected = false;
          onDisconnected?.call();
        },
      );
    } catch (e) {
      _isConnected = false;
      rethrow;
    }
  }

  /// Send audio bytes to server.
  void sendAudio(Uint8List audioData) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(audioData);
    }
  }

  /// Send a JSON message to server.
  void sendMessage(Map<String, dynamic> message) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(jsonEncode(message));
    }
  }

  /// Send interrupt signal.
  void sendInterrupt() {
    sendMessage({'type': 'interrupt'});
  }

  /// Send text input (for testing without mic).
  void sendTextInput(String text) {
    sendMessage({'type': 'text_input', 'text': text});
  }

  /// Request session cost summary from server.
  void sendRequestSummary() {
    sendMessage({'type': 'request_summary'});
  }

  /// Disconnect from server.
  Future<void> disconnect() async {
    _isConnected = false;
    await _channel?.sink.close();
    _channel = null;
  }
}
