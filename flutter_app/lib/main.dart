import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'screens/disk_screen.dart';
import 'screens/docker_screen.dart';
import 'screens/home_screen.dart';
import 'screens/network_screen.dart';
import 'screens/processes_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/terminal_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/app_drawer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthProvider()..load(),
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
          if (auth.isLoading) {
            return const _SplashScreen();
          }
          if (!auth.isAuthenticated) {
            return const SetupScreen();
          }
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dns_rounded, color: AppColors.primary, size: 56),
            SizedBox(height: 16),
            Text('Drilex VPS',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            SizedBox(height: 24),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _idx = 0;

  static const _titles = [
    'Dashboard',
    'Statistics',
    'CPU Monitor',
    'RAM Monitor',
    'Disk Manager',
    'Network',
    'Docker',
    'Terminal',
  ];

  @override
  Widget build(BuildContext context) {
    final api = context.read<AuthProvider>().apiService!;

    // Build the active screen. We rebuild on switch (screens restart = fresh data).
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
        actions: [
          const _LiveBadge(),
          const SizedBox(width: 12),
        ],
      ),
      drawer: AppDrawer(
        selectedIndex: _idx,
        onItemSelected: (i) => setState(() => _idx = i),
        onDisconnect: () => context.read<AuthProvider>().clear(),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: KeyedSubtree(key: ValueKey(_idx), child: screen),
      ),
    );
  }
}

class _LiveBadge extends StatefulWidget {
  const _LiveBadge();

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Color.lerp(AppColors.accent, AppColors.accent.withOpacity(0.3), _ctrl.value)!,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          const Text(
            'LIVE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}
