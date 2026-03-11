import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SessionCostData {
  final DateTime date;
  final String voice;
  final double sessionDurationSec;
  final double sttDurationMin;
  final double sttCost;
  final int llmInputTokens;
  final int llmOutputTokens;
  final int llmCalls;
  final double llmCost;
  final int ttsCharacters;
  final double ttsCost;
  final double totalCost;

  SessionCostData({
    required this.date,
    required this.voice,
    required this.sessionDurationSec,
    required this.sttDurationMin,
    required this.sttCost,
    required this.llmInputTokens,
    required this.llmOutputTokens,
    required this.llmCalls,
    required this.llmCost,
    required this.ttsCharacters,
    required this.ttsCost,
    required this.totalCost,
  });

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'voice': voice,
        'session_duration_sec': sessionDurationSec,
        'stt_duration_min': sttDurationMin,
        'stt_cost': sttCost,
        'llm_input_tokens': llmInputTokens,
        'llm_output_tokens': llmOutputTokens,
        'llm_calls': llmCalls,
        'llm_cost': llmCost,
        'tts_characters': ttsCharacters,
        'tts_cost': ttsCost,
        'total_cost': totalCost,
      };

  factory SessionCostData.fromJson(Map<String, dynamic> json) {
    return SessionCostData(
      date: DateTime.parse(json['date'] as String),
      voice: json['voice'] as String? ?? 'Unknown',
      sessionDurationSec: (json['session_duration_sec'] as num).toDouble(),
      sttDurationMin: (json['stt_duration_min'] as num).toDouble(),
      sttCost: (json['stt_cost'] as num).toDouble(),
      llmInputTokens: (json['llm_input_tokens'] as num).toInt(),
      llmOutputTokens: (json['llm_output_tokens'] as num).toInt(),
      llmCalls: (json['llm_calls'] as num).toInt(),
      llmCost: (json['llm_cost'] as num).toDouble(),
      ttsCharacters: (json['tts_characters'] as num).toInt(),
      ttsCost: (json['tts_cost'] as num).toDouble(),
      totalCost: (json['total_cost'] as num).toDouble(),
    );
  }

  factory SessionCostData.fromServerMessage(Map<String, dynamic> raw) {
    return SessionCostData(
      date: DateTime.now(),
      voice: raw['voice'] as String? ?? 'Unknown',
      sessionDurationSec: (raw['session_duration_sec'] as num?)?.toDouble() ?? 0,
      sttDurationMin: (raw['stt_duration_min'] as num?)?.toDouble() ?? 0,
      sttCost: (raw['stt_cost'] as num?)?.toDouble() ?? 0,
      llmInputTokens: (raw['llm_input_tokens'] as num?)?.toInt() ?? 0,
      llmOutputTokens: (raw['llm_output_tokens'] as num?)?.toInt() ?? 0,
      llmCalls: (raw['llm_calls'] as num?)?.toInt() ?? 0,
      llmCost: (raw['llm_cost'] as num?)?.toDouble() ?? 0,
      ttsCharacters: (raw['tts_characters'] as num?)?.toInt() ?? 0,
      ttsCost: (raw['tts_cost'] as num?)?.toDouble() ?? 0,
      totalCost: (raw['total_cost'] as num?)?.toDouble() ?? 0,
    );
  }

  String get formattedDuration {
    final mins = sessionDurationSec ~/ 60;
    final secs = (sessionDurationSec % 60).toInt();
    if (mins > 0) return '${mins}m ${secs}s';
    return '${secs}s';
  }
}

class CostHistoryService {
  static const _key = 'voiceai_cost_history';

  static Future<List<SessionCostData>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    return list
        .map((s) => SessionCostData.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList()
        .reversed
        .toList(); // newest first
  }

  static Future<void> addSession(SessionCostData session) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    list.add(jsonEncode(session.toJson()));
    await prefs.setStringList(_key, list);
  }

  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static Future<Map<String, double>> getTotalCosts() async {
    final history = await getHistory();
    double stt = 0, llm = 0, tts = 0, total = 0;
    for (final s in history) {
      stt += s.sttCost;
      llm += s.llmCost;
      tts += s.ttsCost;
      total += s.totalCost;
    }
    return {'stt': stt, 'llm': llm, 'tts': tts, 'total': total};
  }
}
