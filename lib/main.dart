import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MindBreathApp());
}

class MindBreathApp extends StatelessWidget {
  const MindBreathApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const CupertinoApp(
      debugShowCheckedModeBanner: false,
      home: HomeScreen(),
    );
  }
}

enum Phase { inhale, hold, exhale, rest }

class BreathConfig {
  final Duration inhale, hold, exhale, rest;
  const BreathConfig({
    this.inhale = const Duration(seconds: 4),
    this.hold   = const Duration(seconds: 4),
    this.exhale = const Duration(seconds: 6),
    this.rest   = const Duration(seconds: 2),
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _cfg = const BreathConfig();
  late final AnimationController _circle;
  Phase _phase = Phase.rest;
  Timer? _timer;
  bool _running = false;
  bool _hapticsOn = true;

  // progress: last 7 days, key yyyy-MM-dd -> count
  late SharedPreferences _prefs;
  Map<String, int> _weekCounts = {};

  @override
  void initState() {
    super.initState();
    _circle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
      lowerBound: 0.65,
      upperBound: 1.0,
    )..value = 0.8;

    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs.getStringList('week') ?? [];
    for (final s in raw) {
      final parts = s.split('|');
      if (parts.length == 2) {
        _weekCounts[parts[0]] = int.tryParse(parts[1]) ?? 0;
      }
    }
    setState(() {});
  }

  Future<void> _saveTodayCompletion() async {
    final t = DateTime.now();
    final key = "${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}";
    _weekCounts[key] = (_weekCounts[key] ?? 0) + 1;

    // keep only last 7 days
    final cutoff = t.subtract(const Duration(days: 7));
    _weekCounts.removeWhere((k, _) => DateTime.parse(k).isBefore(DateTime(cutoff.year, cutoff.month, cutoff.day)));

    final list = _weekCounts.entries.map((e) => "${e.key}|${e.value}").toList();
    await _prefs.setStringList('week', list);
    setState(() {});
  }

  // ===== breathing engine =====
  void _start() {
    if (_running) return;
    setState(() => _running = true);
    _runPhase(Phase.inhale);
  }

  void _stop() {
    _timer?.cancel();
    _circle.stop();
    setState(() {
      _running = false;
      _phase = Phase.rest;
    });
  }

  void _runPhase(Phase next) {
    _timer?.cancel();
    setState(() => _phase = next);
    _haptic(next);

    switch (next) {
      case Phase.inhale:
        _circle.animateTo(1.0, duration: _cfg.inhale, curve: Curves.easeInOutCubic);
        _timer = Timer(_cfg.inhale, () => _runPhase(Phase.hold));
        break;
      case Phase.hold:
        _timer = Timer(_cfg.hold, () => _runPhase(Phase.exhale));
        break;
      case Phase.exhale:
        _circle.animateTo(0.65, duration: _cfg.exhale, curve: Curves.easeInOutCubic);
        _timer = Timer(_cfg.exhale, () => _runPhase(Phase.rest));
        break;
      case Phase.rest:
        _timer = Timer(_cfg.rest, () {
          // full cycle done
          _saveTodayCompletion();
          if (_hapticsOn) HapticFeedback.mediumImpact();
          if (_running) _runPhase(Phase.inhale);
        });
        break;
    }
  }

  void _haptic(Phase p) {
    if (!_hapticsOn) return;
    switch (p) {
      case Phase.inhale:
      case Phase.exhale:
        HapticFeedback.selectionClick();
        break;
      case Phase.hold:
        HapticFeedback.lightImpact();
        break;
      case Phase.rest:
        HapticFeedback.selectionClick();
        break;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _circle.dispose();
    super.dispose();
  }

  // ===== UI =====
  String get _label => switch (_phase) {
        Phase.inhale => 'Inhale',
        Phase.hold => 'Hold',
        Phase.exhale => 'Exhale',
        Phase.rest => 'Rest',
      };

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final circleDia = size.width * 0.62;

    const bg = Color(0xFFFAFAFB);
    const ink = Color(0xFF1C1C1E); // graphite
    final sub = const Color(0xFF3C3C43).withOpacity(0.6);

    return CupertinoPageScaffold(
      backgroundColor: bg,
      navigationBar: const CupertinoNavigationBar(
        border: null,
        middle: Text('MindBreath', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            // Progress header
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Column(
                children: [
                  const Text('Progress', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Daily Sessions Completed', style: TextStyle(fontSize: 16, color: sub)),
                  const SizedBox(height: 8),
                  Text(_todayCount().toString(), style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  WeeklyBars(data: _weekCounts),
                ],
              ),
            ),
            const Spacer(),
            // Animated outlined circle
            Semantics(
              label: 'Breathing circle, $_label phase',
              liveRegion: true,
              child: AnimatedBuilder(
                animation: _circle,
                builder: (_, __) {
                  return Container(
                    width: circleDia * _circle.value,
                    height: circleDia * _circle.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: CupertinoColors.transparent,
                      border: Border.all(color: ink, width: 2),
                      boxShadow: _circle.value > 0.95
                          ? [
                              BoxShadow(
                                color: ink.withOpacity(0.18),
                                blurRadius: 24,
                                spreadRadius: 2,
                                offset: const Offset(0, 8),
                              )
                            ]
                          : null,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            Text(_label, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(_running ? 'Cycle running' : 'Ready', style: TextStyle(fontSize: 16, color: sub)),
            const Spacer(),
            // Controls
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoButton.filled(onPressed: _start, child: const Text('Start')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CupertinoButton(
                      onPressed: _stop,
                      color: const Color(0xFFEAEAEA),
                      child: const Text('Stop', style: TextStyle(color: Color(0xFF1C1C1E))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Row(children: [
                    const Text('Haptics', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    CupertinoSwitch(
                      value: _hapticsOn,
                      onChanged: (v) => setState(() => _hapticsOn = v),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _todayCount() {
    final t = DateTime.now();
    final key = "${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}";
    return _weekCounts[key] ?? 0;
    }
}

class WeeklyBars extends StatelessWidget {
  final Map<String, int> data;
  const WeeklyBars({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final days = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      final key = "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
      return (d, data[key] ?? 0);
    });

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final e in days) ...[
              _Bar(value: e.$2),
              const SizedBox(width: 10),
            ]
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final e in days) ...[
              SizedBox(
                width: 24,
                child: Text(_dayLetter(e.$1),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: 10),
            ]
          ],
        ),
      ],
    );
  }

  static String _dayLetter(DateTime d) => ['S', 'M', 'T', 'W', 'T', 'F', 'S'][d.weekday % 7];
}

class _Bar extends StatelessWidget {
  final int value; // sessions that day
  const _Bar({required this.value});

  @override
  Widget build(BuildContext context) {
    final height = (value == 0) ? 56.0 : (56 + (value.clamp(0, 5) * 12)).toDouble();
    final color = value == 0 ? const Color(0xFFEAEAEA) : const Color(0xFF1C1C1E);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
      width: 24,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}
