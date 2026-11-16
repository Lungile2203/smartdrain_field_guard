import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/report.dart';
import 'screens/jobs_screen.dart';
import 'screens/report_screen.dart';
import 'screens/settings_screen.dart';
import 'services/report_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Show the app immediately; start-up work happens behind a loading screen,
  // so a slow network or an error can never leave the phone on the logo.
  runApp(const SmartDrainApp());
}

/// Runs ReportService.init() with a time limit and shows any error on screen.
class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  late Future<void> _ready;

  @override
  void initState() {
    super.initState();
    _ready = ReportService.instance.init().timeout(const Duration(seconds: 15));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Starting Drainage Guard…'),
              ]),
            ),
          );
        }
        if (snap.hasError) {
          return Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('The app could not start',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  const Text('Send a screenshot of this screen to the tech lead:'),
                  const SizedBox(height: 12),
                  SelectableText('${snap.error}', style: const TextStyle(fontFamily: 'monospace')),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => setState(() {
                      _ready = ReportService.instance.init().timeout(const Duration(seconds: 15));
                    }),
                    child: const Text('Try again'),
                  ),
                ]),
              ),
            ),
          );
        }
        return const HomeShell();
      },
    );
  }
}

class SmartDrainApp extends StatelessWidget {
  const SmartDrainApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0B6E99);
    return MaterialApp(
      title: 'Drainage Guard Community',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true, brightness: Brightness.light),
      darkTheme: ThemeData(colorSchemeSeed: seed, useMaterial3: true, brightness: Brightness.dark),
      home: const StartupGate(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final service = ReportService.instance;
  int tab = 0;

  @override
  void initState() {
    super.initState();
    // First run with no broker details: open Settings
    service.onMyReportUpdated = _myReportUpdated;
  }

  void _myReportUpdated(Report r) {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r.isCleared ? 'Your report at ${r.title} was fixed ✓' : 'A worker is on the way to your report at ${r.title}'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 6),
      action: SnackBarAction(label: 'View', onPressed: () => setState(() => tab = 1)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final open = service.reports.values.where((r) => service.mine.contains(r.id) && !r.isCleared).length;
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Drainage Guard · Community', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                Text(
                  'Report a blocked or flooded drain. No sign-up needed.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            actions: [const _ConnChip(), const SizedBox(width: 12)],
          ),
          body: IndexedStack(
            index: tab,
            children: [
              ReportScreen(onSent: () => setState(() => tab = 1)),
              const JobsScreen(),
              const SettingsScreen(),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (i) => setState(() => tab = i),
            destinations: [
              const NavigationDestination(icon: Icon(Icons.add_location_alt_outlined), selectedIcon: Icon(Icons.add_location_alt), label: 'Report'),
              NavigationDestination(
                icon: Badge(isLabelVisible: open > 0, label: Text('$open'), child: const Icon(Icons.assignment_outlined)),
                selectedIcon: Badge(isLabelVisible: open > 0, label: Text('$open'), child: const Icon(Icons.assignment)),
                label: 'My reports',
              ),
              const NavigationDestination(icon: Icon(Icons.info_outline), selectedIcon: Icon(Icons.info), label: 'About'),
            ],
          ),
        );
      },
    );
  }
}

class _ConnChip extends StatelessWidget {
  const _ConnChip();

  @override
  Widget build(BuildContext context) {
    final s = ReportService.instance;
    // Listens by itself: a const widget is not rebuilt by its parent
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final (String label, Color color) = switch (s.state) {
          ConnState.online => ('Online', Colors.green),
          ConnState.connecting => ('Connecting…', Colors.orange),
          ConnState.offline => ('Offline', Colors.grey),
          ConnState.error => ('No connection', Colors.red),
        };
        return Chip(
          avatar: CircleAvatar(backgroundColor: color, radius: 5),
          label: Text(label, style: const TextStyle(fontSize: 12)),
          visualDensity: VisualDensity.compact,
        );
      },
    );
  }
}
