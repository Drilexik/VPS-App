// Defensive int/double parsers — handle cases where JSON sends numbers as strings
int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

double _toDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}

class CpuInfo {
  final String model;
  final int cores;
  final int logicalCores;
  final double usagePercent;
  final List<double> perCore;
  final double? frequencyMhz;
  final double? temperature;

  const CpuInfo({
    required this.model,
    required this.cores,
    required this.logicalCores,
    required this.usagePercent,
    required this.perCore,
    this.frequencyMhz,
    this.temperature,
  });

  factory CpuInfo.fromJson(Map<String, dynamic> j) => CpuInfo(
        model: j['model']?.toString() ?? 'Unknown',
        cores: _toInt(j['cores']),
        logicalCores: _toInt(j['logical_cores']),
        usagePercent: _toDouble(j['usage_percent']),
        perCore: (j['per_core'] as List<dynamic>? ?? [])
            .map((e) => _toDouble(e))
            .toList(),
        frequencyMhz: j['frequency_mhz'] != null ? _toDouble(j['frequency_mhz']) : null,
        temperature: j['temperature'] != null ? _toDouble(j['temperature']) : null,
      );
}

class RamInfo {
  final int total;
  final int used;
  final int free;
  final double percent;
  final int swapTotal;
  final int swapUsed;
  final int swapFree;
  final double swapPercent;

  const RamInfo({
    required this.total,
    required this.used,
    required this.free,
    required this.percent,
    required this.swapTotal,
    required this.swapUsed,
    required this.swapFree,
    required this.swapPercent,
  });

  factory RamInfo.fromJson(Map<String, dynamic> j) => RamInfo(
        total: _toInt(j['total']),
        used: _toInt(j['used']),
        free: _toInt(j['free']),
        percent: _toDouble(j['percent']),
        swapTotal: _toInt(j['swap_total']),
        swapUsed: _toInt(j['swap_used']),
        swapFree: _toInt(j['swap_free']),
        swapPercent: _toDouble(j['swap_percent']),
      );
}

class DiskInfo {
  final int total;
  final int used;
  final int free;
  final double percent;

  const DiskInfo({
    required this.total,
    required this.used,
    required this.free,
    required this.percent,
  });

  factory DiskInfo.fromJson(Map<String, dynamic> j) => DiskInfo(
        total: _toInt(j['total']),
        used: _toInt(j['used']),
        free: _toInt(j['free']),
        percent: _toDouble(j['percent']),
      );
}

class NetSummary {
  final int bytesSent;
  final int bytesRecv;

  const NetSummary({required this.bytesSent, required this.bytesRecv});

  factory NetSummary.fromJson(Map<String, dynamic> j) => NetSummary(
        bytesSent: _toInt(j['bytes_sent']),
        bytesRecv: _toInt(j['bytes_recv']),
      );
}

class SystemOverview {
  final CpuInfo cpu;
  final RamInfo ram;
  final DiskInfo disk;
  final NetSummary network;
  final String hostname;
  final String os;
  final int uptimeSeconds;

  const SystemOverview({
    required this.cpu,
    required this.ram,
    required this.disk,
    required this.network,
    required this.hostname,
    required this.os,
    required this.uptimeSeconds,
  });

  factory SystemOverview.fromJson(Map<String, dynamic> j) => SystemOverview(
        cpu: CpuInfo.fromJson(j['cpu'] ?? {}),
        ram: RamInfo.fromJson(j['ram'] ?? {}),
        disk: DiskInfo.fromJson(j['disk'] ?? {}),
        network: NetSummary.fromJson(j['network'] ?? {}),
        hostname: j['hostname']?.toString() ?? 'unknown',
        os: j['os']?.toString() ?? 'unknown',
        uptimeSeconds: _toInt(j['uptime_seconds']),
      );
}

class ProcessInfo {
  final int pid;
  final String name;
  final double cpuPercent;
  final double ramMb;
  final String status;
  final String command;
  final bool killable;

  const ProcessInfo({
    required this.pid,
    required this.name,
    required this.cpuPercent,
    required this.ramMb,
    required this.status,
    required this.command,
    required this.killable,
  });

  factory ProcessInfo.fromJson(Map<String, dynamic> j) => ProcessInfo(
        pid: _toInt(j['pid']),
        name: j['name']?.toString() ?? '',
        cpuPercent: _toDouble(j['cpu_percent']),
        ramMb: _toDouble(j['ram_mb']),
        status: j['status']?.toString() ?? '',
        command: j['command']?.toString() ?? '',
        killable: j['killable'] == true,
      );
}

class TopProcess {
  final int pid;
  final String name;
  final double cpuPercent;
  final double ramMb;
  final int? connections;

  const TopProcess({
    required this.pid,
    required this.name,
    required this.cpuPercent,
    required this.ramMb,
    this.connections,
  });

  factory TopProcess.fromJson(Map<String, dynamic> j) => TopProcess(
        pid: _toInt(j['pid']),
        name: j['name']?.toString() ?? '',
        cpuPercent: _toDouble(j['cpu_percent']),
        ramMb: _toDouble(j['ram_mb']),
        connections: j['connections'] != null ? _toInt(j['connections']) : null,
      );
}

class DiskFolder {
  final String path;
  final int size;

  const DiskFolder({required this.path, required this.size});

  factory DiskFolder.fromJson(Map<String, dynamic> j) =>
      DiskFolder(path: j['path']?.toString() ?? '', size: _toInt(j['size']));
}

class DiskEntry {
  final String name;
  final String path;
  final bool isDir;
  final int size;
  final double modified;

  const DiskEntry({
    required this.name,
    required this.path,
    required this.isDir,
    required this.size,
    required this.modified,
  });

  factory DiskEntry.fromJson(Map<String, dynamic> j) => DiskEntry(
        name: j['name']?.toString() ?? '',
        path: j['path']?.toString() ?? '',
        isDir: j['is_dir'] == true,
        size: _toInt(j['size']),
        modified: _toDouble(j['modified']),
      );
}

class NetworkInterface {
  final String name;
  final int bytesSent;
  final int bytesRecv;
  final int packetsSent;
  final int packetsRecv;

  const NetworkInterface({
    required this.name,
    required this.bytesSent,
    required this.bytesRecv,
    required this.packetsSent,
    required this.packetsRecv,
  });
}

class BannedIp {
  final String ip;
  const BannedIp({required this.ip});
  factory BannedIp.fromJson(Map<String, dynamic> j) =>
      BannedIp(ip: j['ip']?.toString() ?? '');
}

class DockerContainer {
  final String id;
  final String name;
  final String image;
  final String status;
  final double cpuPercent;
  final double ramMb;

  const DockerContainer({
    required this.id,
    required this.name,
    required this.image,
    required this.status,
    required this.cpuPercent,
    required this.ramMb,
  });

  factory DockerContainer.fromJson(Map<String, dynamic> j) => DockerContainer(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        image: j['image']?.toString() ?? '',
        status: j['status']?.toString() ?? '',
        cpuPercent: _toDouble(j['cpu_percent']),
        ramMb: _toDouble(j['ram_mb']),
      );
}

String fmtBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
}

String fmtUptime(int seconds) {
  final d = seconds ~/ 86400;
  final h = (seconds % 86400) ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (d > 0) return '${d}d ${h}h ${m}m';
  if (h > 0) return '${h}h ${m}m';
  return '${m}m ${seconds % 60}s';
}
