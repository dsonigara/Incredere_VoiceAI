import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/cost_history_service.dart';

class CostHistoryScreen extends StatefulWidget {
  const CostHistoryScreen({super.key});

  @override
  State<CostHistoryScreen> createState() => _CostHistoryScreenState();
}

class _CostHistoryScreenState extends State<CostHistoryScreen> {
  List<SessionCostData> _history = [];
  Map<String, double> _totals = {'stt': 0, 'llm': 0, 'tts': 0, 'total': 0};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final history = await CostHistoryService.getHistory();
    final totals = await CostHistoryService.getTotalCosts();
    setState(() {
      _history = history;
      _totals = totals;
      _loading = false;
    });
  }

  String _formatCost(double cost) {
    if (cost < 0.01) return '\$${cost.toStringAsFixed(6)}';
    return '\$${cost.toStringAsFixed(4)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A1A),
        elevation: 0,
        title: const Text(
          'Cost History',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              onPressed: _confirmClear,
              icon: Icon(Icons.delete_outline,
                  color: Colors.white.withValues(alpha: 0.5)),
              tooltip: 'Clear History',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? _buildEmpty()
              : _buildContent(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_rounded,
              size: 64, color: Colors.white.withValues(alpha: 0.15)),
          const SizedBox(height: 16),
          Text(
            'No conversations yet',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Cost data will appear here after your first chat',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.25),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // Total cost summary card
        _buildTotalCard(),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Sessions (${_history.length})',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // Session list
        ..._history.map((s) => _buildSessionCard(s)),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildTotalCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF2563EB).withValues(alpha: 0.2),
            const Color(0xFF8B5CF6).withValues(alpha: 0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF2563EB).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Text(
            'Total Spend',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _formatCost(_totals['total']!),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildCostPill('STT', _totals['stt']!, const Color(0xFF10B981)),
              const SizedBox(width: 8),
              _buildCostPill('LLM', _totals['llm']!, const Color(0xFFF59E0B)),
              const SizedBox(width: 8),
              _buildCostPill('TTS', _totals['tts']!, const Color(0xFF8B5CF6)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCostPill(String label, double cost, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatCost(cost),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionCard(SessionCostData session) {
    final dateStr = DateFormat('MMM d, h:mm a').format(session.date);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E3A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding:
              const EdgeInsets.only(left: 16, right: 16, bottom: 16),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: session.voice == 'Aria'
                  ? const Color(0xFF8B5CF6).withValues(alpha: 0.2)
                  : const Color(0xFF2563EB).withValues(alpha: 0.2),
            ),
            child: Icon(
              session.voice == 'Aria'
                  ? Icons.face_3_rounded
                  : Icons.face_rounded,
              color: session.voice == 'Aria'
                  ? const Color(0xFF8B5CF6)
                  : const Color(0xFF2563EB),
              size: 22,
            ),
          ),
          title: Row(
            children: [
              Text(
                session.voice,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                session.formattedDuration,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 13,
                ),
              ),
            ],
          ),
          subtitle: Text(
            dateStr,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 12,
            ),
          ),
          trailing: Text(
            _formatCost(session.totalCost),
            style: const TextStyle(
              color: Colors.greenAccent,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          iconColor: Colors.white.withValues(alpha: 0.3),
          collapsedIconColor: Colors.white.withValues(alpha: 0.3),
          children: [
            const Divider(color: Color(0xFF2A2A4A), height: 1),
            const SizedBox(height: 12),
            _buildDetailRow(
              'STT (Deepgram)',
              '${session.sttDurationMin.toStringAsFixed(2)} min',
              session.sttCost,
              const Color(0xFF10B981),
            ),
            const SizedBox(height: 8),
            _buildDetailRow(
              'LLM (Groq)',
              '${session.llmInputTokens}+${session.llmOutputTokens} tokens (${session.llmCalls} calls)',
              session.llmCost,
              const Color(0xFFF59E0B),
            ),
            const SizedBox(height: 8),
            _buildDetailRow(
              'TTS (Cartesia)',
              '${session.ttsCharacters} chars',
              session.ttsCost,
              const Color(0xFF8B5CF6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(
      String service, String usage, double cost, Color color) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                service,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                usage,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Text(
          _formatCost(cost),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  void _confirmClear() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E3A),
        title: const Text('Clear History',
            style: TextStyle(color: Colors.white)),
        content: const Text('Delete all cost history data?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await CostHistoryService.clearHistory();
              _loadHistory();
            },
            child:
                const Text('Clear', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}
