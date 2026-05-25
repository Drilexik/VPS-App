import 'package:dio/dio.dart';
import '../models/models.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

class ApiService {
  final String baseUrl;
  final String apiKey;
  late final Dio _dio;

  ApiService({required this.baseUrl, required this.apiKey}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Accept': 'application/json',
        },
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (e, handler) {
          final msg = e.response?.data?['detail']?.toString() ??
              e.message ??
              'Unknown error';
          handler.reject(
            DioException(
              requestOptions: e.requestOptions,
              error: ApiException(msg, e.response?.statusCode),
              type: e.type,
              response: e.response,
            ),
          );
        },
      ),
    );
  }

  T _unwrap<T>(Response r) => r.data as T;

  Future<bool> checkHealth() async {
    try {
      final r = await _dio.get('/api/health');
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<SystemOverview> getSystemOverview() async {
    try {
      final r = await _dio.get('/api/system/overview');
      return SystemOverview.fromJson(_unwrap(r));
    } on DioException catch (e) {
      throw e.error ?? ApiException('Request failed');
    }
  }

  Future<List<TopProcess>> getTopCpu({int limit = 5}) async {
    try {
      final r = await _dio.get('/api/stats/top-cpu', queryParameters: {'limit': limit});
      return (r.data as List).map((e) => TopProcess.fromJson(e)).toList();
    } on DioException catch (e) {
      throw e.error ?? ApiException('Request failed');
    }
  }

  Future<List<TopProcess>> getTopRam({int limit = 5}) async {
    try {
      final r = await _dio.get('/api/stats/top-ram', queryParameters: {'limit': limit});
      return (r.data as List).map((e) => TopProcess.fromJson(e)).toList();
    } on DioException catch (e) {
      throw e.error ?? ApiException('Request failed');
    }
  }

  Future<List<TopProcess>> getTopNetwork({int limit = 5}) async {
    try {
      final r = await _dio.get('/api/stats/top-network', queryParameters: {'limit': limit});
      return (r.data as List).map((e) => TopProcess.fromJson(e)).toList();
    } on DioException catch (e) {
      throw e.error ?? ApiException('Request failed');
    }
  }

  Future<List<DiskFolder>> getTopDiskFolders({String path = '/home', int limit = 5}) async {
    try {
      final r = await _dio.get('/api/stats/top-disk-folders',
          queryParameters: {'path': path, 'limit': limit});
      return (r.data as List).map((e) => DiskFolder.fromJson(e)).toList();
    } on DioException catch (e) {
      throw e.error ?? ApiException('Request failed');
    }
  }

  Future<Map<String, dynamic>> getProcessList({
    int offset = 0,
    int limit = 15,
    String sortBy = 'cpu',
  }) async {
    try {
      final r = await _dio.get('/api/processes/list',
          queryParameters: {'offset': offset, 'limit': limit, 'sort_by': sortBy});
      final data = r.data as Map<String, dynamic>;
      return {
        'total': data['total'],
        'processes': (data['processes'] as List)
            .map((e) => ProcessInfo.fromJson(e))
            .toList(),
      };
    } on DioException catch (e) {
      throw e.error ?? ApiException('Request failed');
    }
  }

  Future<void> killProcess(int pid, {int signal = 15}) async {
    try {
      await _dio.post('/api/processes/kill', data: {'pid': pid, 'signal': signal});
    } on DioException catch (e) {
      throw e.error ?? ApiException('Request failed');
    }
  }

  Future<Map<String, dynamic>> getDiskList(String path) async {
    try {
      final r = await _dio.get('/api/disk/list', queryParameters: {'path': path});
      final data = r.data as Map<String, dynamic>;
      return {
        'path': data['path'],
        'entries': (data['entries'] as List).map((e) => DiskEntry.fromJson(e)).toList(),
      };
    } on DioException catch (e) {
      throw e.error ?? ApiException('Request failed');
    }
  }

  Future<void> createDirectory(String path) async {
    try {
      await _dio.post('/api/disk/mkdir', data: {'path': path});
    } on DioException catch (e) {
      throw e.error ?? ApiException('Request failed');
    }
  }

  Future<void> deletePath(String path, {bool recursive = false}) async {
    try {
      await _dio.delete('/api/disk/delete',
          data: {'path': path, 'recursive': recursive});
    } on DioException catch (e) {
      throw e.error ?? ApiException('Request failed');
    }
  }

  Future<List<NetworkInterface>> getNetworkStats() async {
    try {
      final r = await _dio.get('/api/network/stats');
      final data = r.data as Map<String, dynamic>;
      return data.entries
          .map((e) => NetworkInterface(
                name: e.key,
                bytesSent: e.value['bytes_sent'] ?? 0,
                bytesRecv: e.value['bytes_recv'] ?? 0,
                packetsSent: e.value['packets_sent'] ?? 0,
                packetsRecv: e.value['packets_recv'] ?? 0,
              ))
          .toList();
    } on DioException catch (e) {
      throw e.error ?? ApiException('Request failed');
    }
  }

  Future<List<BannedIp>> getBannedIps() async {
    try {
      final r = await _dio.get('/api/network/banned');
      return (r.data['banned'] as List).map((e) => BannedIp.fromJson(e)).toList();
    } on DioException catch (e) {
      throw e.error ?? ApiException('Request failed');
    }
  }

  Future<void> banIp(String ip, {String reason = ''}) async {
    try {
      await _dio.post('/api/network/ban', data: {'ip': ip, 'reason': reason});
    } on DioException catch (e) {
      throw e.error ?? ApiException('Request failed');
    }
  }

  Future<void> unbanIp(String ip) async {
    try {
      await _dio.post('/api/network/unban', data: {'ip': ip});
    } on DioException catch (e) {
      throw e.error ?? ApiException('Request failed');
    }
  }

  Future<List<DockerContainer>> getDockerContainers() async {
    try {
      final r = await _dio.get('/api/docker/containers');
      return (r.data['containers'] as List)
          .map((e) => DockerContainer.fromJson(e))
          .toList();
    } on DioException catch (e) {
      throw e.error ?? ApiException('Request failed');
    }
  }

  Future<void> dockerAction(String containerId, String action) async {
    try {
      await _dio.post('/api/docker/action',
          data: {'container_id': containerId, 'action': action});
    } on DioException catch (e) {
      throw e.error ?? ApiException('Request failed');
    }
  }

  Future<String> getDockerLogs(String containerId, {int lines = 50}) async {
    try {
      final r = await _dio.get('/api/docker/containers/$containerId/logs',
          queryParameters: {'lines': lines});
      return r.data['logs'] ?? '';
    } on DioException catch (e) {
      throw e.error ?? ApiException('Request failed');
    }
  }

  Future<Map<String, dynamic>> execCommand(String command, {int timeout = 30}) async {
    try {
      final r = await _dio.post('/api/terminal/exec',
          data: {'command': command, 'timeout': timeout});
      return r.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw e.error ?? ApiException('Request failed');
    }
  }
}
