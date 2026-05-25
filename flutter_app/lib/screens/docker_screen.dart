import 'dart:async';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'docker_logs_screen.dart';

class DockerScreen extends StatefulWidget {
  final ApiService api;
  const DockerScreen({super.key, required this.api});

  @override
  State<DockerScreen> createState() => _DockerScreenState();
}

class _DockerScreenState extends State<DockerScreen> {
  List<DockerContainer> _containers = [];
  bool _loading = true;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await widget.api.getDockerContainers();
      if (mounted) setState(() { _containers = data; _error = null; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _action(DockerContainer c, String action) async {
    try {
      await widget.api.dockerAction(c.id, action);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${action.capitalize()} sent to ${c.name}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  void _showActions(DockerContainer c) {
    showModalBottomSheet(
      context: context,
      builder: (_) => _ContainerSheet(
        container: c,
        onAction: (action) {
          Navigator.pop(context);
          if (action == 'logs') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DockerLogsScreen(
                  api: widget.api,
                  containerId: c.id,
                  containerName: c.name,
                ),
              ),
            );
          } else {
            _action(c, action);
          }
        },
      ),
    );
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
          ElevatedButton(onPressed: _load, child: const Text('Retry')),
        ]),
      );
    }
    if (_containers.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: ListView(children: const [
          SizedBox(height: 120),
          Center(child: Icon(Icons.inventory_2_rounded, color: AppColors.textDim, size: 48)),
          SizedBox(height: 12),
          Center(child: Text('No containers found', style: TextStyle(color: AppColors.textDim))),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _containers.length,
        itemBuilder: (ctx, i) => _ContainerTile(
          container: _containers[i],
          onTap: () => _showActions(_containers[i]),
        ),
      ),
    );
  }
}

class _ContainerTile extends StatelessWidget {
  final DockerContainer container;
  final VoidCallback onTap;

  const _ContainerTile({required this.container, required this.onTap});

  static Color _statusColor(String status) {
    if (status == 'running') return AppColors.accent;
    if (status == 'paused') return AppColors.warning;
    return AppColors.textDim;
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(container.status);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    container.name,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(container.status,
                      style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(container.image,
                style: const TextStyle(fontSize: 12, color: AppColors.textDim, fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Row(
              children: [
                _Badge(
                  label: 'CPU',
                  value: '${container.cpuPercent.toStringAsFixed(1)}%',
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                _Badge(
                  label: 'RAM',
                  value: '${container.ramMb.toStringAsFixed(0)} MB',
                  color: AppColors.accent,
                ),
                const Spacer(),
                Text(
                  'ID: ${container.id}',
                  style: const TextStyle(fontSize: 10, color: AppColors.textDim, fontFamily: 'monospace'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Badge({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label ', style: const TextStyle(fontSize: 11, color: AppColors.textDim)),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

class _ContainerSheet extends StatelessWidget {
  final DockerContainer container;
  final ValueChanged<String> onAction;

  const _ContainerSheet({required this.container, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final isRunning = container.status == 'running';
    final isPaused = container.status == 'paused';
    final isStopped = container.status == 'exited' || container.status == 'created';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(container.name,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  Text(container.image,
                      style: const TextStyle(fontSize: 12, color: AppColors.textDim)),
                ]),
              ),
              Container(
                width: 12, height: 12,
                decoration: BoxDecoration(
                  color: isRunning ? AppColors.accent : isPaused ? AppColors.warning : AppColors.textDim,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (isStopped || isPaused) _ActionBtn('Start', Icons.play_arrow_rounded, AppColors.accent, () => onAction('start')),
              if (isRunning) _ActionBtn('Stop', Icons.stop_rounded, AppColors.warning, () => onAction('stop')),
              if (isRunning || isPaused) _ActionBtn('Restart', Icons.refresh_rounded, AppColors.primary, () => onAction('restart')),
              if (isRunning) _ActionBtn('Pause', Icons.pause_rounded, AppColors.warning, () => onAction('pause')),
              if (isPaused) _ActionBtn('Unpause', Icons.play_circle_rounded, AppColors.accent, () => onAction('unpause')),
              _ActionBtn('Logs', Icons.article_rounded, AppColors.textDim, () => onAction('logs')),
              _ActionBtn('Remove', Icons.delete_rounded, AppColors.danger, () => onAction('remove')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn(this.label, this.icon, this.color, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

extension _Str on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
