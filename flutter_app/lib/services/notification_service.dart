import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kLastForeground = 'notif_last_fg';
const _kPrefix = 'notif_last_';

const _androidChannel = AndroidNotificationDetails(
  'drilex_alerts',
  'Drilex Alerts',
  channelDescription: 'VPS server threshold and SSH alerts',
  importance: Importance.high,
  priority: Priority.high,
  enableVibration: true,
  playSound: true,
);

const _notifDetails = NotificationDetails(android: _androidChannel);

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: android),
    );
    // Request POST_NOTIFICATIONS permission (Android 13+)
    final impl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await impl?.requestNotificationsPermission();
    _ready = true;
  }

  /// Call every time the app comes to foreground.
  /// Used by the smart heartbeat logic to avoid false alerts.
  static Future<void> markForeground() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastForeground, _now());
  }

  /// Show an alert with per-kind cooldown deduplication.
  /// [cooldown] controls the minimum gap between same-kind notifications.
  static Future<void> showAlert({
    required String kind,
    required String title,
    required String body,
    Duration cooldown = const Duration(minutes: 5),
  }) async {
    if (!_ready) return;
    final prefs = await SharedPreferences.getInstance();
    final key = '$_kPrefix$kind';
    final lastSent = prefs.getInt(key) ?? 0;

    if (_now() - lastSent < cooldown.inMilliseconds) return;

    await prefs.setInt(key, _now());
    await _plugin.show(kind.hashCode, title, body, _notifDetails);
  }

  /// Used by background WorkManager task.
  /// Returns true only when conditions are right to send a heartbeat alert:
  ///  - app wasn't in foreground within the last 5 minutes (phone just on / screen off)
  ///  - no heartbeat alert was sent in the last 30 minutes
  static Future<bool> shouldHeartbeatAlert() async {
    final prefs = await SharedPreferences.getInstance();
    final lastFg = prefs.getInt(_kLastForeground) ?? 0;
    final lastAlert = prefs.getInt('${_kPrefix}heartbeat') ?? 0;
    final now = _now();

    // If user recently had the app open, don't alert
    if (now - lastFg < 5 * 60 * 1000) return false;
    // Minimum 30 min between heartbeat notifications
    if (now - lastAlert < 30 * 60 * 1000) return false;
    return true;
  }

  static Future<void> showHeartbeatAlert() async {
    if (!_ready) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('${_kPrefix}heartbeat', _now());
    await _plugin.show(
      0xBEEF,
      'Server Unreachable',
      'Could not connect to your VPS. Check network and server status.',
      _notifDetails,
    );
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch;
}
