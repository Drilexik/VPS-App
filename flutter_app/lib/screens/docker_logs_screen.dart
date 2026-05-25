import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class DockerLogsScreen extends StatefulWidget {
  final ApiService api;
  final String containerId;
  final String containerName;

  const DockerLogsScreen({
    super.key,
    required this.api,
    required this.containerId,
    required this.containerName,
  });

  @override
  State<DockerLogsScreen> createState() => _DockerLogsScreenState();
}

class _DockerLogsScreenState extends State<DockerLogsScreen> {
  String _logs = '';
  bool _loading = true;
  String? _error;
  int _lines = 50;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final logs = await widget.api.getDockerLogs(widget.containerId, lines: _lines);
      if (mounted) {
        setState(() { _logs = logs; _loading = false; });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Logs — ${widget.containerName}',
            style: const TextStyle(fontSize: 15)),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'Copy logs',
            onPressed: _logs.isEmpty ? null : () {
              Clipboard.setData(ClipboardData(text: _logs));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Logs copied to clipboard')),
              );
            },
          ),
          PopupMenuButton<int>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) { _lines = v; _load(); },
            itemBuilder: (_) => [50, 100, 200, 500]
                .map((n) => PopupMenuItem(value: n, child: Text('Last $n lines')))
                .toList(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.error_outline, color: AppColors.danger, size: 40),
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: AppColors.textDim)),
                    const SizedBox(height: 16),
                    ElevatedButton(onPressed: _load, child: const Text('Retry')),
                  ]),
                )
              : Container(
                  color: const Color(0xFF080610),
                  child: SelectableText.rich(
                    TextSpan(
                      text: _logs.isEmpty ? '(no logs)' : _logs,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Color(0xFF88FF88),
                        height: 1.4,
                      ),
                    ),
                    scrollPhysics: const ClampingScrollPhysics(),
                  ),
                ),
    );
  }
}
