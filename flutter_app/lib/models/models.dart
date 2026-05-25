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
        model: j['model'] ?? 'Unknown',
        cores: j['cores'] ?? 1,
        logicalCores: j['logical_cores'] ?? 1,
        usagePercent: (j['usage_percent'] ?? 0).toDouble(),
        perCore: (j['per_core'] as List<dynamic>? ?? [])
            .map((e) => (e as num).toDouble())
            .toList(),
        frequencyMhz: j['frequency_mhz']?.toDouble(),
        temperature: j['temperature']?.toDouble(),
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
        total: j['total'] ?? 0,
        used: j['used'] ?? 0,
        free: j['free'] ?? 0,
        percent: (j['percent'] ?? 0).toDouble(),
        swapTotal: j['swap_total'] ?? 0,
        swapUsed: j['swap_used'] ?? 0,
        swapFree: j['swap_free'] ?? 0,
        swapPercent: (j['swap_percent'] ?? 0).toDouble(),
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
        total: j['total'] ?? 0,
        used: j['used'] ?? 0,
        free: j['free'] ?? 0,
        percent: (j['percent'] ?? 0).toDouble(),
      );
}

class NetSummary {
  final int bytesSent;
  final int bytesRecv;

  const NetSummary({required this.bytesSent, required this.bytesRecv});

  factory NetSummary.fromJson(Map<String, dynamic> j) => NetSummary(
        bytesSent: j['bytes_sent'] ?? 0,
        bytesRecv: j['bytes_recv'] ?? 0,
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
        hostname: j['hostname'] ?? 'unknown',
        os: j['os'] ?? 'unknown',
        uptimeSeconds: j['uptime_seconds'] ?? 0,
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
        pid: j['pid'] ?? 0,
        name: j['name'] ?? '',
        cpuPercent: (j['cpu_percent'] ?? 0).toDouble(),
        ramMb: (j['ram_mb'] ?? 0).toDouble(),
        status: j['status'] ?? '',
        command: j['command'] ?? '',
        killable: j['killable'] ?? false,
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
        pid: j['pid'] ?? 0,
        name: j['name'] ?? '',
        cpuPercent: (j['cpu_percent'] ?? 0).toDouble(),
        ramMb: (j['ram_mb'] ?? 0).toDouble(),
        connections: j['connections'],
      );
}

class DiskFolder {
  final String path;
  final int size;

  const DiskFolder({required this.path, required this.size});

  factory DiskFolder.fromJson(Map<String, dynamic> j) =>
      DiskFolder(path: j['path'] ?? '', size: j['size'] ?? 0);
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
        name: j['name'] ?? '',
        path: j['path'] ?? '',
        isDir: j['is_dir'] ?? false,
        size: j['size'] ?? 0,
        modified: (j['modified'] ?? 0).toDouble(),
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
      BannedIp(ip: j['ip'] ?? '');
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
        id: j['id'] ?? '',
        name: j['name'] ?? '',
        image: j['image'] ?? '',
        status: j['status'] ?? '',
        cpuPercent: (j['cpu_percent'] ?? 0).toDouble(),
        ramMb: (j['ram_mb'] ?? 0).toDouble(),
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
