import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/gauge_widget.dart';
import '../widgets/stat_card.dart';

class HomeScreen extends StatefulWidget {
  final ApiService api;
  const HomeScreen({super.key, required this.api});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  SystemOverview? _data;
  String? _error;
  bool _loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await widget.api.getSystemOverview();
      if (mounted) setState(() { _data = data; _error = null; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorView(error: _error!, onRetry: _load);
    final d = _data!;
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView(
        children: [
          _ServerCard(d: d),
          const SizedBox(height: 4),
          _GaugeRow(d: d),
          _CpuCard(d: d),
          _BarChart(perCore: d.cpu.perCore),
          _RamCard(d: d),
          _NetworkCard(d: d),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ServerCard extends StatelessWidget {
  final SystemOverview d;
  const _ServerCard({required this.d});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.dns_rounded, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.hostname,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(d.os, style: const TextStyle(fontSize: 12, color: AppColors.textDim)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('Uptime', style: TextStyle(fontSize: 11, color: AppColors.textDim)),
              Text(
                fmtUptime(d.uptimeSeconds),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accent),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GaugeRow extends StatelessWidget {
  final SystemOverview d;
  const _GaugeRow({required this.d});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          GaugeWidget(label: 'CPU', value: d.cpu.usagePercent, color: gaugeColor(d.cpu.usagePercent)),
          GaugeWidget(label: 'RAM', value: d.ram.percent, color: gaugeColor(d.ram.percent)),
          GaugeWidget(label: 'Disk', value: d.disk.percent, color: gaugeColor(d.disk.percent)),
        ],
      ),
    );
  }
}

class _CpuCard extends StatelessWidget {
  final SystemOverview d;
  const _CpuCard({required this.d});

  @override
  Widget build(BuildContext context) {
    final cpu = d.cpu;
    return StatCard(
      title: 'PROCESSOR',
      icon: Icons.memory_rounded,
      rows: [
        StatRow('Model', cpu.model),
        StatRow('Cores', '${cpu.cores} physical / ${cpu.logicalCores} logical'),
        if (cpu.frequencyMhz != null)
          StatRow('Frequency', '${(cpu.frequencyMhz! / 1000).toStringAsFixed(2)} GHz'),
        if (cpu.temperature != null)
          StatRow(
            'Temperature',
            '${cpu.temperature!.toStringAsFixed(1)} °C',
            cpu.temperature! > 80 ? AppColors.danger : cpu.temperature! > 60 ? AppColors.warning : AppColors.accent,
          ),
      ],
    );
  }
}

class _BarChart extends StatelessWidget {
  final List<double> perCore;
  const _BarChart({required this.perCore});

  @override
  Widget build(BuildContext context) {
    if (perCore.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PER-CORE USAGE',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textDim, letterSpacing: 0.5)),
          const SizedBox(height: 14),
          SizedBox(
            height: 100,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: 100,
                minY: 0,
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) => Text(
                        'C${v.toInt()}',
                        style: const TextStyle(fontSize: 9, color: AppColors.textDim),
                      ),
                      reservedSize: 18,
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 25,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppColors.border,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(
                  perCore.length,
                  (i) => BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: perCore[i].clamp(0, 100),
                        color: gaugeColor(perCore[i]),
                        width: 12,
                        borderRadius: BorderRadius.circular(3),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: 100,
                          color: AppColors.border,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RamCard extends StatelessWidget {
  final SystemOverview d;
  const _RamCard({required this.d});

  @override
  Widget build(BuildContext context) {
    final r = d.ram;
    return StatCard(
      title: 'MEMORY',
      icon: Icons.storage_rounded,
      iconColor: AppColors.accent,
      rows: [
        StatRow('Total RAM', fmtBytes(r.total)),
        StatRow('Used', '${fmtBytes(r.used)} (${r.percent.toStringAsFixed(1)}%)',
            gaugeColor(r.percent)),
        StatRow('Free', fmtBytes(r.free)),
        StatRow('Swap Total', fmtBytes(r.swapTotal)),
        if (r.swapTotal > 0)
          StatRow('Swap Used', '${fmtBytes(r.swapUsed)} (${r.swapPercent.toStringAsFixed(1)}%)',
              gaugeColor(r.swapPercent)),
      ],
    );
  }
}

class _NetworkCard extends StatelessWidget {
  final SystemOverview d;
  const _NetworkCard({required this.d});

  @override
  Widget build(BuildContext context) {
    final n = d.network;
    return StatCard(
      title: 'NETWORK (TOTAL)',
      icon: Icons.wifi_rounded,
      iconColor: AppColors.warning,
      rows: [
        StatRow('Sent', fmtBytes(n.bytesSent)),
        StatRow('Received', fmtBytes(n.bytesRecv)),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, color: AppColors.danger, size: 48),
            const SizedBox(height: 16),
            Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textDim, fontSize: 14)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
