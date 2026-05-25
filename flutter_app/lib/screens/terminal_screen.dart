import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class TerminalScreen extends StatefulWidget {
  final ApiService api;
  const TerminalScreen({super.key, required this.api});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalEntry {
  final String command;
  final String stdout;
  final String stderr;
  final int returnCode;

  _TerminalEntry({
    required this.command,
    required this.stdout,
    required this.stderr,
    required this.returnCode,
  });
}

class _TerminalScreenState extends State<TerminalScreen> {
  final _cmdCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_TerminalEntry> _history = [];
  final List<String> _cmdHistory = [];
  int _historyIdx = -1;
  bool _running = false;

  static const _quickCmds = [
    'uptime',
    'df -h',
    'free -h',
    'ps aux --sort=-%cpu | head -20',
    'netstat -tuln',
    'docker ps',
    'systemctl --failed',
    'who',
    'uname -a',
  ];

  @override
  void dispose() {
    _cmdCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(String cmd) async {
    if (cmd.trim().isEmpty) return;
    setState(() => _running = true);
    try {
      final result = await widget.api.execCommand(cmd.trim());
      if (mounted) {
        setState(() {
          _history.add(_TerminalEntry(
            command: cmd.trim(),
            stdout: result['stdout'] ?? '',
            stderr: result['stderr'] ?? '',
            returnCode: result['returncode'] ?? 0,
          ));
          _cmdHistory.insert(0, cmd.trim());
          _historyIdx = -1;
          _cmdCtrl.clear();
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _history.add(_TerminalEntry(
            command: cmd.trim(),
            stdout: '',
            stderr: e.toString(),
            returnCode: 1,
          ));
        });
        _scrollToBottom();
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _navigateHistory(bool up) {
    if (_cmdHistory.isEmpty) return;
    setState(() {
      if (up) {
        _historyIdx = (_historyIdx + 1).clamp(0, _cmdHistory.length - 1);
      } else {
        _historyIdx = (_historyIdx - 1);
        if (_historyIdx < 0) {
          _historyIdx = -1;
          _cmdCtrl.clear();
          return;
        }
      }
      _cmdCtrl.text = _cmdHistory[_historyIdx];
      _cmdCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _cmdCtrl.text.length),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Quick commands
        Container(
          height: 44,
          color: AppColors.surface,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: _quickCmds.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () {
                _cmdCtrl.text = _quickCmds[i];
                _run(_quickCmds[i]);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                ),
                child: Text(
                  _quickCmds[i],
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        // Output area
        Expanded(
          child: Container(
            color: const Color(0xFF080610),
            child: _history.isEmpty
                ? const Center(
                    child: Text(
                      'Run a command to see output here',
                      style: TextStyle(color: AppColors.textDim, fontSize: 13),
                    ),
                  )
                : SelectionArea(
                    child: ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.all(12),
                      itemCount: _history.length,
                      itemBuilder: (_, i) => _HistoryEntry(entry: _history[i]),
                    ),
                  ),
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        // Input bar
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                // History navigation
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
                  onPressed: () => _navigateHistory(true),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  color: AppColors.textDim,
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                  onPressed: () => _navigateHistory(false),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  color: AppColors.textDim,
                ),
                const SizedBox(width: 4),
                // Prompt
                const Text(
                  '\$ ',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _cmdCtrl,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      color: AppColors.text,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onSubmitted: (v) => _run(v),
                    autocorrect: false,
                    autocorrectionTextEditingController: null,
                    textInputAction: TextInputAction.send,
                  ),
                ),
                // Clear
                IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: () => setState(() {
                    _history.clear();
                    _cmdCtrl.clear();
                  }),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  color: AppColors.textDim,
                  tooltip: 'Clear output',
                ),
                // Send
                Container(
                  decoration: BoxDecoration(
                    color: _running ? AppColors.border : AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    icon: _running
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded, size: 18, color: Colors.white),
                    onPressed: _running ? null : () => _run(_cmdCtrl.text),
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HistoryEntry extends StatelessWidget {
  final _TerminalEntry entry;
  const _HistoryEntry({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('\$ ',
                  style: TextStyle(color: AppColors.accent, fontFamily: 'monospace', fontSize: 13)),
              Expanded(
                child: Text(
                  entry.command,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (entry.returnCode != 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'exit ${entry.returnCode}',
                    style: const TextStyle(fontSize: 10, color: AppColors.danger),
                  ),
                ),
            ],
          ),
          if (entry.stdout.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              entry.stdout,
              style: const TextStyle(
                color: Color(0xFF88FF88),
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
          if (entry.stderr.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              entry.stderr,
              style: const TextStyle(
                color: AppColors.danger,
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
