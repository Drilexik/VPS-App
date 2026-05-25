import 'dart:async';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/stat_card.dart';

class ProcessesScreen extends StatefulWidget {
  final ApiService api;
  final String defaultSort;

  const ProcessesScreen({super.key, required this.api, this.defaultSort = 'cpu'});

  @override
  State<ProcessesScreen> createState() => _ProcessesScreenState();
}

class _ProcessesScreenState extends State<ProcessesScreen> {
  List<ProcessInfo> _procs = [];
  String? _error;
  bool _loading = true;
  bool _loadingMore = false;
  late String _sort;
  int _total = 0;
  int _loaded = 15;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sort = widget.defaultSort;
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_loadingMore) _load();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() { _loaded = 15; _procs = []; });
    }
    try {
      final data = await widget.api.getProcessList(limit: _loaded, sortBy: _sort);
      if (mounted) {
        setState(() {
          _procs = data['processes'] as List<ProcessInfo>;
          _total = data['total'] as int;
          _error = null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadMore() async {
    setState(() { _loadingMore = true; _loaded += 15; });
    await _load();
    setState(() => _loadingMore = false);
  }

  Future<void> _kill(ProcessInfo p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Kill Process'),
        content: Text('Send SIGTERM to "${p.name}" (PID ${p.pid})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kill', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.killProcess(p.pid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Killed ${p.name} (${p.pid})')),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  void _setSort(String s) {
    setState(() => _sort = s);
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_rounded, color: AppColors.danger, size: 48),
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.textDim)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: () => _load(reset: true), child: const Text('Retry')),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      color: AppColors.primary,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Row(
                children: [
                  const Text('Sort by:', style: TextStyle(fontSize: 13, color: AppColors.textDim)),
                  const SizedBox(width: 10),
                  _SortChip(label: 'CPU', value: 'cpu', current: _sort, onTap: _setSort),
                  const SizedBox(width: 6),
                  _SortChip(label: 'RAM', value: 'ram', current: _sort, onTap: _setSort),
                  const SizedBox(width: 6),
                  _SortChip(label: 'Name', value: 'name', current: _sort, onTap: _setSort),
                  const Spacer(),
                  Text(
                    '$_total processes',
                    style: const TextStyle(fontSize: 12, color: AppColors.textDim),
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _ProcessTile(proc: _procs[i], onKill: () => _kill(_procs[i])),
              childCount: _procs.length,
            ),
          ),
          if (_loaded < _total)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton(
                  onPressed: _loadingMore ? null : _loadMore,
                  child: _loadingMore
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Load more'),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final String value;
  final String current;
  final ValueChanged<String> onTap;

  const _SortChip({
    required this.label,
    required this.value,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withOpacity(0.2) : AppColors.border,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.primary : AppColors.textDim,
          ),
        ),
      ),
    );
  }
}

class _ProcessTile extends StatelessWidget {
  final ProcessInfo proc;
  final VoidCallback onKill;

  const _ProcessTile({required this.proc, required this.onKill});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              '${proc.pid}',
              style: const TextStyle(fontSize: 11, color: AppColors.primary, fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(proc.name,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                if (proc.command.isNotEmpty)
                  Text(proc.command,
                      style: const TextStyle(fontSize: 11, color: AppColors.textDim),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InfoBadge(
            text: '${proc.cpuPercent.toStringAsFixed(1)}%',
            color: AppColors.primary,
          ),
          const SizedBox(width: 4),
          InfoBadge(
            text: '${proc.ramMb.toStringAsFixed(0)}M',
            color: AppColors.accent,
          ),
          if (proc.killable) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onKill,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: AppColors.danger.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.close_rounded, color: AppColors.danger, size: 16),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
