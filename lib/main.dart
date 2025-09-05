import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MindBreathApp());
}

/// ---------- Palette (single teal hue, minimalist) ----------
class MB {
  // Background (airy, neutral)
  static const bgTop = Color(0xFFF6FBFA);
  static const bgBottom = Color(0xFFFFFFFF);

  // Teal family
  static const primary = Color(0xFF0FB59C);       // core teal
  static const primaryDark = Color(0xFF0A8D79);   // deeper tone
  static const primaryLight = Color(0xFF9FE4D8);  // soft glow
  static const primarySoft = Color(0xFFE8F7F4);   // soft surface

  // Text
  static const label = Color(0xFF0F1222);
  static const labelSub = Color(0x990F1222);

  // Surfaces
  static const card = Color(0xCCFFFFFF); // translucent white
  static const stroke = Color(0x220F1222);
}

class MindBreathApp extends StatelessWidget {
  const MindBreathApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const CupertinoApp(
      debugShowCheckedModeBanner: false,
      home: RootTabs(),
    );
  }
}

class RootTabs extends StatelessWidget {
  const RootTabs({super.key});
  @override
  Widget build(BuildContext context) {
    return CupertinoTabScaffold(
      // not const: avoids const-assert at build
      tabBar: CupertinoTabBar(
        backgroundColor: const Color(0xF0FFFFFF),
        activeColor: MB.primary,
        inactiveColor: MB.labelSub,
        items: const [
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.wind), label: 'Breathe'),
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.chart_bar_alt_fill), label: 'Progress'),
        ],
      ),
      tabBuilder: (context, index) => index == 0 ? const BreathePage() : const ProgressPage(),
    );
  }
}

/// ---------------------- Breathing engine ----------------------
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

class BreathePage extends StatefulWidget {
  const BreathePage({super.key});
  @override
  State<BreathePage> createState() => _BreathePageState();
}

class _BreathePageState extends State<BreathePage> with TickerProviderStateMixin {
  final _cfg = const BreathConfig();
  late final AnimationController _scale;
  Phase _phase = Phase.rest;
  Timer? _timer;
  bool _running = false;
  bool _hapticsOn = true;

  late SharedPreferences _prefs;
  Map<String, int> _weekCounts = {};

  @override
  void initState() {
    super.initState();
    _scale = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
      lowerBound: 0.75,
      upperBound: 1.0,
      value: 0.85,
    );
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs.getStringList('week') ?? [];
    for (final s in raw) {
      final parts = s.split('|');
      if (parts.length == 2) _weekCounts[parts[0]] = int.tryParse(parts[1]) ?? 0;
    }
    setState(() {});
  }

  Future<void> _saveTodayCompletion() async {
    final t = DateTime.now();
    final key = "${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}";
    _weekCounts[key] = (_weekCounts[key] ?? 0) + 1;

    final cutoff = t.subtract(const Duration(days: 7));
    _weekCounts.removeWhere((k, _) =>
        DateTime.parse(k).isBefore(DateTime(cutoff.year, cutoff.month, cutoff.day)));

    final list = _weekCounts.entries.map((e) => "${e.key}|${e.value}").toList();
    await _prefs.setStringList('week', list);
  }

  void _start() {
    if (_running) return;
    setState(() => _running = true);
    _runPhase(Phase.inhale);
  }

  void _stop() {
    _timer?.cancel();
    _scale.stop();
    setState(() {
      _running = false;
      _phase = Phase.rest;
      _scale.value = 0.85;
    });
  }

  void _runPhase(Phase next) {
    _timer?.cancel();
    setState(() => _phase = next);
    _haptic(next);

    switch (next) {
      case Phase.inhale:
        _scale.animateTo(1.0, duration: _cfg.inhale, curve: Curves.easeInOutCubic);
        _timer = Timer(_cfg.inhale, () => _runPhase(Phase.hold));
        break;
      case Phase.hold:
        _timer = Timer(_cfg.hold, () => _runPhase(Phase.exhale));
        break;
      case Phase.exhale:
        _scale.animateTo(0.75, duration: _cfg.exhale, curve: Curves.easeInOutCubic);
        _timer = Timer(_cfg.exhale, () => _runPhase(Phase.rest));
        break;
      case Phase.rest:
        _timer = Timer(_cfg.rest, () async {
          await _saveTodayCompletion();
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

  String get _label => switch (_phase) {
        Phase.inhale => 'Inhale',
        Phase.hold   => 'Hold',
        Phase.exhale => 'Exhale',
        Phase.rest   => 'Rest',
      };

  @override
  void dispose() {
    _timer?.cancel();
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: MB.bgBottom,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('MindBreath', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        border: null,
        backgroundColor: Color(0xF2FFFFFF),
      ),
      child: Stack(
        children: [
          // Gentle teal wash
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [MB.bgTop, MB.bgBottom],
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 12),

                // Phase pill
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _Card(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_label,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: MB.label,
                            )),
                        Row(
                          children: [
                            const Text('Haptics', style: TextStyle(color: MB.labelSub)),
                            const SizedBox(width: 8),
                            CupertinoSwitch(
                              value: _hapticsOn,
                              onChanged: (v) => setState(() => _hapticsOn = v),
                              activeColor: MB.primary,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // CENTER AREA — globe is *perfectly centered* in the remaining space
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, bc) {
                      // size globe by the tighter axis of this center area
                      final maxDiameter = (bc.maxWidth < bc.maxHeight ? bc.maxWidth : bc.maxHeight) * 0.68;
                      return Center(
                        child: AnimatedBuilder(
                          animation: _scale,
                          builder: (context, _) => _BreathGlobe(diameter: maxDiameter * _scale.value),
                        ),
                      );
                    },
                  ),
                ),

                // Controls
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: CupertinoButton.filled(
                          onPressed: _start,
                          child: const Text('Start'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: CupertinoButton(
                          onPressed: _stop,
                          color: MB.primarySoft,
                          child: const Text('Stop', style: TextStyle(color: MB.primary)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Minimal “floating globe” (single hue + soft shadows, no 3D)
class _BreathGlobe extends StatelessWidget {
  final double diameter;
  const _BreathGlobe({required this.diameter});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // gentle depth within the same hue
        gradient: const RadialGradient(
          center: Alignment(-0.2, -0.25),
          radius: 0.95,
          colors: [MB.primaryLight, MB.primaryDark],
          stops: [0.0, 1.0],
        ),
        // symmetric shadows → no perceived horizontal offset
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 26, offset: Offset(0, 14)),
          BoxShadow(color: Color(0x14000000), blurRadius: 8,  offset: Offset(0, 2)),
        ],
        border: Border.all(color: MB.stroke, width: 1),
      ),
      // subtle top highlight, centered and balanced
      foregroundDecoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment(0.0, 0.3),
          colors: [Color(0x33FFFFFF), Color(0x00FFFFFF)],
        ),
      ),
    );
  }
}

/// Simple translucent card
class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: MB.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MB.stroke),
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), blurRadius: 14, offset: Offset(0, 8)),
        ],
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }
}

/// ---------------------- Progress (separate tab) ----------------------
class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});
  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  late SharedPreferences _prefs;
  Map<String, int> _week = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs.getStringList('week') ?? [];
    for (final s in raw) {
      final parts = s.split('|');
      if (parts.length == 2) _week[parts[0]] = int.tryParse(parts[1]) ?? 0;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final days = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      final key = "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
      return (d, _week[key] ?? 0);
    });

    return CupertinoPageScaffold(
      backgroundColor: MB.bgBottom,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Progress', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        border: null,
        backgroundColor: Color(0xF2FFFFFF),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Weekly Sessions',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: MB.label)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: days.map((e) {
                      final int v = e.$2;
                      final h = (v == 0) ? 18.0 : (18 + (v.clamp(0, 6) * 12)).toDouble();
                      return Column(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOutCubic,
                            width: 22,
                            height: h,
                            decoration: BoxDecoration(
                              color: v == 0 ? MB.primarySoft : MB.primary,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: v == 0
                                  ? null
                                  : const [BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 6))],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(_dayLetter(e.$1), style: const TextStyle(color: MB.labelSub)),
                        ],
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  Text('Today: ${_todayCount()} session(s)',
                      style: const TextStyle(color: MB.labelSub)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  int _todayCount() {
    final t = DateTime.now();
    final key = "${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}";
    return _week[key] ?? 0;
  }

  static String _dayLetter(DateTime d) => ['S', 'M', 'T', 'W', 'T', 'F', 'S'][d.weekday % 7];
}
