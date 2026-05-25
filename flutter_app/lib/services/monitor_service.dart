import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'notification_service.dart';

/// Real-time SSE connection to the backend.
/// Forwards live stats and triggers local notifications on alerts.
class MonitorService extends ChangeNotifier {
  // Singleton
  static final MonitorService _i = MonitorService._();
  factory MonitorService() => _i;
  MonitorService._();

  // ── Live stats ─────────────────────────────────────────────────────────────
  double cpuPercent = 0;
  double ramPercent = 0;
  double diskPercent = 0;
  int lastHeartbeatTs = 0;
  bool isConnected = false;

  // ── Config ─────────────────────────────────────────────────────────────────
  String? _baseUrl;
  String? _apiKey;
  bool _active = false;

  http.Client? _client;
  Timer? _reconnectTimer;

  final _alertCtrl = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get alerts => _alertCtrl.stream;

  // ── Public API ─────────────────────────────────────────────────────────────

  void configure(String baseUrl, String apiKey) {
    _baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    _apiKey = apiKey;
  }

  Future<void> start() async {
    _active = true;
    _reconnectTimer?.cancel();
    await _connect();
  }

  void stop() {
    _active = false;
    _reconnectTimer?.cancel();
    _client?.close();
    _client = null;
    _setConnected(false);
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  Future<void> _connect() async {
    if (!_active || _baseUrl == null || _apiKey == null) return;

    _client?.close();
    _client = http.Client();

    try {
      final uri = Uri.parse('$_baseUrl/api/events/stream');
      final req = http.Request('GET', uri);
      req.headers['Authorization'] = 'Bearer $_apiKey';
      req.headers['Accept'] = 'text/event-stream';
      req.headers['Cache-Control'] = 'no-cache';

      final resp = await _client!.send(req).timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        _scheduleReconnect();
        return;
      }

      _setConnected(true);

      final buffer = StringBuffer();
      await for (final chunk in resp.stream.transform(utf8.decoder)) {
        if (!_active) break;
        buffer.write(chunk);
        // SSE events are double-newline delimited
        final text = buffer.toString();
        final blocks = text.split('\n\n');
        for (int i = 0; i < blocks.length - 1; i++) {
          final block = blocks[i].trim();
          if (block.startsWith('data: ')) {
            try {
              final event = jsonDecode(block.substring(6)) as Map<String, dynamic>;
              _handleEvent(event);
            } catch (_) {}
          }
        }
        buffer.clear();
        buffer.write(blocks.last); // keep incomplete block
      }
    } catch (_) {
      // Connection dropped — reconnect silently
    } finally {
      _setConnected(false);
      if (_active) _scheduleReconnect();
    }
  }

  void _handleEvent(Map<String, dynamic> e) {
    final type = e['type'] as String?;
    switch (type) {
      case 'stats':
        cpuPercent = (e['cpu'] as num?)?.toDouble() ?? cpuPercent;
        ramPercent = (e['ram'] as num?)?.toDouble() ?? ramPercent;
        diskPercent = (e['disk'] as num?)?.toDouble() ?? diskPercent;
        notifyListeners();
        break;

      case 'heartbeat':
        lastHeartbeatTs = (e['timestamp'] as int?) ?? lastHeartbeatTs;
        break;

      case 'alert':
        _alertCtrl.add(e);
        _dispatchNotification(e);
        break;
    }
  }

  Future<void> _dispatchNotification(Map<String, dynamic> e) async {
    final kind = e['kind'] as String? ?? 'unknown';
    final message = e['message'] as String? ?? '';
    final value = e['value'];

    switch (kind) {
      case 'cpu':
        await NotificationService.showAlert(
          kind: 'cpu',
          title: 'CPU Alert — ${value?.toStringAsFixed(1)}%',
          body: message,
          cooldown: const Duration(minutes: 5),
        );
        break;
      case 'ram':
        await NotificationService.showAlert(
          kind: 'ram',
          title: 'RAM Alert — ${value?.toStringAsFixed(1)}%',
          body: message,
          cooldown: const Duration(minutes: 5),
        );
        break;
      case 'disk':
        await NotificationService.showAlert(
          kind: 'disk',
          title: 'Disk Critical — ${value?.toStringAsFixed(1)}%',
          body: message,
          cooldown: const Duration(minutes: 10),
        );
        break;
      case 'ssh':
        await NotificationService.showAlert(
          kind: 'ssh',
          title: 'SSH Login Detected',
          body: message.length > 80 ? message.substring(0, 80) : message,
          cooldown: const Duration(minutes: 1),
        );
        break;
    }
  }

  void _setConnected(bool v) {
    if (isConnected != v) {
      isConnected = v;
      notifyListeners();
    }
  }

  void _scheduleReconnect() {
    if (!_active) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 12), () {
      if (_active) _connect();
    });
  }

  @override
  void dispose() {
    _active = false;
    _client?.close();
    _reconnectTimer?.cancel();
    _alertCtrl.close();
    super.dispose();
  }
}
