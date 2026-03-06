import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

/// Handles microphone recording (PCM 16-bit, 16kHz mono) and audio playback (PCM 24kHz).
class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  // Buffer for incoming TTS audio (PCM s16le, 24kHz)
  final List<int> _audioBuffer = [];
  bool _isPlaying = false;
  bool _isRecording = false;
  StreamSubscription? _playerStateSub;
  int _wavCounter = 0;

  bool get isPlaying => _isPlaying;
  bool get isRecording => _isRecording;

  /// Start recording from microphone — returns a stream of PCM audio chunks.
  Future<Stream<Uint8List>> startRecording() async {
    if (_isRecording) {
      // Already recording, just return a dummy — caller should reuse existing stream
      throw Exception('Already recording');
    }

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw Exception('Microphone permission not granted');
    }

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 256000,
      ),
    );

    _isRecording = true;
    return stream;
  }

  /// Stop recording.
  Future<void> stopRecording() async {
    if (!_isRecording) return;
    _isRecording = false;
    await _recorder.stop();
  }

  /// Add TTS audio chunk to playback buffer.
  void addAudioChunk(Uint8List chunk) {
    _audioBuffer.addAll(chunk);
  }

  /// Play all buffered audio.
  Future<void> playBufferedAudio() async {
    if (_audioBuffer.isEmpty) return;

    _isPlaying = true;

    try {
      final tempDir = await getTemporaryDirectory();
      _wavCounter++;
      final wavFile = File('${tempDir.path}/tts_output_$_wavCounter.wav');

      final pcmData = Uint8List.fromList(_audioBuffer);
      _audioBuffer.clear();

      final wavData = _createWavHeader(pcmData, 24000, 1, 16);
      await wavFile.writeAsBytes(wavData);

      // Cancel any previous listener
      await _playerStateSub?.cancel();

      final completer = Completer<void>();

      _playerStateSub = _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _isPlaying = false;
          if (!completer.isCompleted) completer.complete();
        }
      });

      await _player.setFilePath(wavFile.path);
      await _player.play();
      await completer.future;

      // Cleanup old file
      try { await wavFile.delete(); } catch (_) {}
    } catch (e) {
      _isPlaying = false;
    }
  }

  /// Stop any ongoing audio playback immediately (for interrupts).
  Future<void> stopPlayback() async {
    _audioBuffer.clear();
    _isPlaying = false;
    await _player.stop();
  }

  /// Create a WAV header for raw PCM data.
  Uint8List _createWavHeader(
      Uint8List pcmData, int sampleRate, int channels, int bitsPerSample) {
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    final dataSize = pcmData.length;
    final fileSize = 36 + dataSize;

    final header = ByteData(44);
    header.setUint8(0, 0x52); header.setUint8(1, 0x49);
    header.setUint8(2, 0x46); header.setUint8(3, 0x46);
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57); header.setUint8(9, 0x41);
    header.setUint8(10, 0x56); header.setUint8(11, 0x45);
    header.setUint8(12, 0x66); header.setUint8(13, 0x6D);
    header.setUint8(14, 0x74); header.setUint8(15, 0x20);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    header.setUint8(36, 0x64); header.setUint8(37, 0x61);
    header.setUint8(38, 0x74); header.setUint8(39, 0x61);
    header.setUint32(40, dataSize, Endian.little);

    final wav = Uint8List(44 + dataSize);
    wav.setAll(0, header.buffer.asUint8List());
    wav.setAll(44, pcmData);
    return wav;
  }

  Future<void> dispose() async {
    await stopRecording();
    await stopPlayback();
    await _playerStateSub?.cancel();
    await _player.dispose();
    _recorder.dispose();
  }
}
