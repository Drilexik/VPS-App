import 'dart:async';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/stat_card.dart';

class NetworkScreen extends StatefulWidget {
  final ApiService api;
  const NetworkScreen({super.key, required this.api});

  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> {
  List<NetworkInterface> _ifaces = [];
  List<BannedIp> _banned = [];
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
      final results = await Future.wait([
        widget.api.getNetworkStats(),
        widget.api.getBannedIps(),
      ]);
      if (mounted) {
        setState(() {
          _ifaces = results[0] as List<NetworkInterface>;
          _banned = results[1] as List<BannedIp>;
          _error = null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _banIp() async {
    final ipCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ban IP Address'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ipCtrl,
              decoration: const InputDecoration(
                labelText: 'IP Address',
                hintText: '192.168.1.1',
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ban', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true || ipCtrl.text.trim().isEmpty) return;
    try {
      await widget.api.banIp(ipCtrl.text.trim(), reason: reasonCtrl.text.trim());
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Banned ${ipCtrl.text.trim()}')),
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

  Future<void> _unban(String ip) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Unban IP'),
        content: Text('Remove ban for $ip?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unban', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.unbanIp(ip);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
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
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView(
        children: [
          const SectionHeader(title: 'Network Interfaces', icon: Icons.router_rounded),
          ..._ifaces.map((iface) => _IfaceTile(iface: iface)),
          const Divider(color: AppColors.border, height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.block_rounded, size: 16, color: AppColors.danger),
                const SizedBox(width: 8),
                const Text('Banned IPs',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
                const Spacer(),
                GestureDetector(
                  onTap: _banIp,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.danger.withOpacity(0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, size: 14, color: AppColors.danger),
                        SizedBox(width: 4),
                        Text('Ban IP', style: TextStyle(fontSize: 13, color: AppColors.danger, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_banned.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No banned IPs', style: TextStyle(color: AppColors.textDim)),
              ),
            )
          else
            ..._banned.map((b) => _BannedTile(ip: b.ip, onUnban: () => _unban(b.ip))),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _IfaceTile extends StatelessWidget {
  final NetworkInterface iface;
  const _IfaceTile({required this.iface});

  @override
  Widget build(BuildContext context) {
    return Container(
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
              const Icon(Icons.settings_ethernet_rounded, size: 16, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(iface.name,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _NetStat(label: 'Sent', value: fmtBytes(iface.bytesSent), icon: Icons.arrow_upward_rounded, color: AppColors.primary),
              const SizedBox(width: 16),
              _NetStat(label: 'Recv', value: fmtBytes(iface.bytesRecv), icon: Icons.arrow_downward_rounded, color: AppColors.accent),
              const SizedBox(width: 16),
              _NetStat(label: 'Pkts out', value: '${iface.packetsSent}', icon: Icons.send_rounded, color: AppColors.textDim),
            ],
          ),
        ],
      ),
    );
  }
}

class _NetStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _NetStat({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textDim)),
          ],
        ),
      ],
    );
  }
}

class _BannedTile extends StatelessWidget {
  final String ip;
  final VoidCallback onUnban;

  const _BannedTile({required this.ip, required this.onUnban});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.danger.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.block_rounded, size: 16, color: AppColors.danger),
          const SizedBox(width: 10),
          Text(ip,
              style: const TextStyle(
                  fontSize: 14,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  color: AppColors.text)),
          const Spacer(),
          OutlinedButton(
            onPressed: onUnban,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: const BorderSide(color: AppColors.accent),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Unban', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
