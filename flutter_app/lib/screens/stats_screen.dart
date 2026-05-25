import 'dart:async';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/stat_card.dart';

class StatsScreen extends StatefulWidget {
  final ApiService api;
  const StatsScreen({super.key, required this.api});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  List<TopProcess>? _topCpu;
  List<TopProcess>? _topRam;
  List<TopProcess>? _topNet;
  List<DiskFolder>? _topDisk;
  String? _error;
  bool _loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.api.getTopCpu(),
        widget.api.getTopRam(),
        widget.api.getTopNetwork(),
        widget.api.getTopDiskFolders(),
      ]);
      if (mounted) {
        setState(() {
          _topCpu = results[0] as List<TopProcess>;
          _topRam = results[1] as List<TopProcess>;
          _topNet = results[2] as List<TopProcess>;
          _topDisk = results[3] as List<DiskFolder>;
          _error = null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_rounded, color: AppColors.danger, size: 48),
          const SizedBox(height: 16),
          Text(_error!, style: const TextStyle(color: AppColors.textDim)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _load, child: const Text('Retry')),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView(
        children: [
          const SectionHeader(title: 'Top CPU', icon: Icons.memory_rounded),
          ..._buildProcessList(_topCpu!, 'cpu'),
          const SectionHeader(title: 'Top RAM', icon: Icons.storage_rounded),
          ..._buildProcessList(_topRam!, 'ram'),
          const SectionHeader(title: 'Top Network', icon: Icons.wifi_rounded),
          ..._buildNetList(_topNet!),
          const SectionHeader(title: 'Largest Folders', icon: Icons.folder_rounded),
          ..._buildFolderList(_topDisk!),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  List<Widget> _buildProcessList(List<TopProcess> list, String type) {
    return list.map((p) {
      final val = type == 'cpu' ? '${p.cpuPercent.toStringAsFixed(1)}%' : '${p.ramMb.toStringAsFixed(0)} MB';
      final color = type == 'cpu' ? AppColors.primary : AppColors.accent;
      return _StatRow(pid: p.pid, name: p.name, badge: val, badgeColor: color);
    }).toList();
  }

  List<Widget> _buildNetList(List<TopProcess> list) {
    return list.map((p) {
      return _StatRow(pid: p.pid, name: p.name, badge: '${p.connections ?? 0} conn', badgeColor: AppColors.warning);
    }).toList();
  }

  List<Widget> _buildFolderList(List<DiskFolder> list) {
    return list.map((f) {
      final name = f.path.split('/').last.isEmpty ? f.path : f.path.split('/').last;
      return _StatRow(
        pid: null,
        name: name,
        subtitle: f.path,
        badge: fmtBytes(f.size),
        badgeColor: AppColors.textDim,
        icon: Icons.folder_rounded,
      );
    }).toList();
  }
}

class _StatRow extends StatelessWidget {
  final int? pid;
  final String name;
  final String? subtitle;
  final String badge;
  final Color badgeColor;
  final IconData? icon;

  const _StatRow({
    required this.pid,
    required this.name,
    this.subtitle,
    required this.badge,
    required this.badgeColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: badgeColor, width: 3)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: pid != null
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$pid',
                  style: const TextStyle(fontSize: 11, color: AppColors.textDim, fontFamily: 'monospace'),
                ),
              )
            : Icon(icon ?? Icons.circle, size: 16, color: badgeColor),
        title: Text(name,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.text),
            overflow: TextOverflow.ellipsis),
        subtitle: subtitle != null
            ? Text(subtitle!,
                style: const TextStyle(fontSize: 11, color: AppColors.textDim),
                overflow: TextOverflow.ellipsis)
            : null,
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: badgeColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: badgeColor.withOpacity(0.4)),
          ),
          child: Text(badge,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: badgeColor)),
        ),
      ),
    );
  }
}
