import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:http/http.dart' as http;

import 'providers/auth_provider.dart';
import 'screens/disk_screen.dart';
import 'screens/docker_screen.dart';
import 'screens/home_screen.dart';
import 'screens/network_screen.dart';
import 'screens/processes_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/terminal_screen.dart';
import 'services/monitor_service.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';
import 'widgets/app_drawer.dart';

// ── WorkManager background task ───────────────────────────────────────────────
// Must be top-level (not inside a class) and annotated for AOT compilation.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    if (task != 'heartbeat') return true;

    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('bg_api_url') ?? '';
    final key = prefs.getString('bg_api_key') ?? '';
    if (url.isEmpty || key.isEmpty) return true;

    // Init notifications (needed in background isolate)
    await NotificationService.init();

    // Smart check: don't alert if conditions aren't right
    if (!await NotificationService.shouldHeartbeatAlert()) return true;

    try {
      final resp = await http.get(
        Uri.parse('$url/api/health'),
        headers: {'Authorization': 'Bearer $key'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 401) {
        // Credentials changed, don't spam
        return true;
      }
      if (resp.statusCode != 200) {
        await NotificationService.showHeartbeatAlert();
      }
    } catch (_) {
      // Could not reach server
      await NotificationService.showHeartbeatAlert();
    }
    return true;
  });
}

// ─────────────────────────────────────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  await NotificationService.init();

  // Register background heartbeat task (fires every 15 min when network available)
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  await Workmanager().registerPeriodicTask(
    'drilex_heartbeat',
    'heartbeat',
    frequency: const Duration(minutes: 15),
    initialDelay: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingWorkPolicy.keep,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..load()),
        ChangeNotifierProvider.value(value: MonitorService()),
      ],
      child: const DrilexApp(),
    ),
  );
}

class DrilexApp extends StatelessWidget {
  const DrilexApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drilex VPS',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Consumer<AuthProvider>(
        builder: (ctx, auth, _) {
          if (auth.isLoading) return const _SplashScreen();
          if (!auth.isAuthenticated) return const SetupScreen();
          return const MainScreen();
        },
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.dns_rounded, color: AppColors.primary, size: 56),
          SizedBox(height: 16),
          Text('Drilex VPS',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          SizedBox(height: 24),
          CircularProgressIndicator(),
        ]),
      ),
    );
  }
}

// ── MainScreen: lifecycle + MonitorService wiring ─────────────────────────────

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _idx = 0;

  static const _titles = [
    'Dashboard', 'Statistics', 'CPU Monitor', 'RAM Monitor',
    'Disk Manager', 'Network', 'Docker', 'Terminal',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.markForeground();
    _startMonitor();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MonitorService().stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      NotificationService.markForeground();
      if (!MonitorService().isConnected) MonitorService().start();
    } else if (state == AppLifecycleState.paused) {
      // Stop SSE when app goes to background (saves battery, avoids spurious reconnect alerts)
      MonitorService().stop();
    }
  }

  void _startMonitor() {
    final auth = context.read<AuthProvider>();
    if (auth.apiUrl == null || auth.apiKey == null) return;
    MonitorService().configure(auth.apiUrl!, auth.apiKey!);
    MonitorService().start();

    // Also subscribe to alert events to show in-app banners
    MonitorService().alerts.listen(_onAlert);
  }

  void _onAlert(Map<String, dynamic> e) {
    if (!mounted) return;
    final kind = e['kind'] as String? ?? '';
    final message = e['message'] as String? ?? '';
    Color color;
    IconData icon;
    switch (kind) {
      case 'cpu': color = AppColors.primary; icon = Icons.memory_rounded; break;
      case 'ram': color = AppColors.accent; icon = Icons.storage_rounded; break;
      case 'disk': color = AppColors.danger; icon = Icons.folder_rounded; break;
      case 'ssh': color = AppColors.warning; icon = Icons.security_rounded; break;
      default: color = AppColors.textDim; icon = Icons.info_rounded;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(message,
              style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
        ]),
        backgroundColor: AppColors.surface,
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: color.withValues(alpha: 0.5)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<AuthProvider>().apiService!;

    Widget screen;
    switch (_idx) {
      case 0:  screen = HomeScreen(api: api); break;
      case 1:  screen = StatsScreen(api: api); break;
      case 2:  screen = ProcessesScreen(api: api, defaultSort: 'cpu'); break;
      case 3:  screen = ProcessesScreen(api: api, defaultSort: 'ram'); break;
      case 4:  screen = DiskScreen(api: api); break;
      case 5:  screen = NetworkScreen(api: api); break;
      case 6:  screen = DockerScreen(api: api); break;
      default: screen = TerminalScreen(api: api);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_idx]),
        actions: const [_LiveBadge(), SizedBox(width: 12)],
      ),
      drawer: AppDrawer(
        selectedIndex: _idx,
        onItemSelected: (i) => setState(() => _idx = i),
        onDisconnect: () {
          MonitorService().stop();
          context.read<AuthProvider>().clear();
        },
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: KeyedSubtree(key: ValueKey(_idx), child: screen),
      ),
    );
  }
}

// ── Live badge (pulses green = SSE connected, grey = reconnecting) ─────────────

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Consumer<MonitorService>(
      builder: (_, monitor, __) => _PulsingBadge(connected: monitor.isConnected),
    );
  }
}

class _PulsingBadge extends StatefulWidget {
  final bool connected;
  const _PulsingBadge({required this.connected});
  @override
  State<_PulsingBadge> createState() => _PulsingBadgeState();
}

class _PulsingBadgeState extends State<_PulsingBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.connected ? AppColors.accent : AppColors.textDim;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: widget.connected
                ? Color.lerp(color, color.withValues(alpha: 0.3), _ctrl.value)!
                : color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          widget.connected ? 'LIVE' : 'SYNC',
          style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700,
            color: color, letterSpacing: 1,
          ),
        ),
      ]),
    );
  }
}
