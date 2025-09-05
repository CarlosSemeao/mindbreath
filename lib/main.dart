import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MindBreathApp());
}

/// ===== Theme (teal palette, light/dark aware) ===================
class T {
  // app primary (controls, filled button)
  static const primary = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF14B8A6),      // teal 500
    darkColor: Color(0xFF2DD4BF),  // teal 400 (brighter on dark)
  );

  // background
  static const bg = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFF6FBFA),      // very light mint
    darkColor: Color(0xFF0C1413),  // near-black teal
  );

  // ink
  static const ink = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF0F172A),      // slate-900
    darkColor: Color(0xFFE2E8F0),  // slate-200
  );

  // subtle surface for the top chip
  static const surface = CupertinoDynamicColor.withBrightness(
    color: Color(0xAAFFFFFF),
    darkColor: Color(0x3314B8A6),
  );

  // ring fills (same hue, different alphas)
  static Color ring(BuildContext c, double a) =>
      CupertinoDynamicColor.resolve(primary, c).withOpacity(a);
}

class MindBreathApp extends StatelessWidget {
  const MindBreathApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      theme: const CupertinoThemeData(
        primaryColor: T.primary, // <- sets filled button & switches
        barBackgroundColor: T.surface,
      ),
      home: const RootTabs(),
    );
  }
}

/// ================= Root with 2 tabs =============================
class RootTabs extends StatelessWidget {
  const RootTabs({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoTabScaffold(
      // DO NOT use const here (breaks assert in CupertinoTabBar)
      tabBar: CupertinoTabBar(
        backgroundColor:
            CupertinoDynamicColor.resolve(T.surface, context),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.circle), label: 'Breathe'),
          BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.chart_bar_alt_fill), label: 'Progress'),
        ],
      ),
      tabBuilder: (context, index) {
        return CupertinoTabView(
          builder: (_) => index == 0 ? const BreathePage() : const ProgressPage(),
        );
      },
    );
  }
}

/// ================= Breathe page (minimal, centered) =============
enum Phase { inhale, hold, exhale, rest }

class BreathConfig {
  final Duration inhale, hold, exhale, rest;
  const BreathConfig({
    this.inhale = const Duration(seconds: 5),
    this.hold   = const Duration(seconds: 5),
    this.exhale = const Duration(seconds: 8),
    this.rest   = const Duration(seconds: 3),
  });
}

class BreathePage extends StatefulWidget {
  const BreathePage({super.key});
  @override
  State<BreathePage> createState() => _BreathePageState();
}

class _BreathePageState extends State<BreathePage> with TickerProviderStateMixin {
  final _cfg = const BreathConfig();

  late final AnimationController _scale; // breathing size
  late final AnimationController _float; // tiny vertical float
  Phase _phase = Phase.rest;
  Timer? _timer;
  bool _running = false;
  bool _haptics = true;

  late SharedPreferences _prefs;
  Map<String, int> _week = {};

  @override
  void initState() {
    super.initState();
    _scale = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
      lowerBound: 0.70,
      upperBound: 1.00,
      value: 0.85,
    );
    _float = AnimationController(vsync: this, duration: const Duration(seconds: 8))
      ..repeat();

    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    for (final s in _prefs.getStringList('week') ?? []) {
      final parts = s.split('|');
      if (parts.length == 2) _week[parts[0]] = int.tryParse(parts[1]) ?? 0;
    }
    setState(() {});
  }

  Future<void> _saveToday() async {
    final t = DateTime.now();
    final key = "${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}";
    _week[key] = (_week[key] ?? 0) + 1;

    final cutoff = t.subtract(const Duration(days: 7));
    _week.removeWhere((k, _) =>
        DateTime.parse(k).isBefore(DateTime(cutoff.year, cutoff.month, cutoff.day)));

    await _prefs.setStringList('week', _week.entries.map((e) => "${e.key}|${e.value}").toList());
  }

  void _start() {
    if (_running) return;
    setState(() => _running = true);
    _go(Phase.inhale);
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

  void _go(Phase p) {
    _timer?.cancel();
    setState(() => _phase = p);
    if (_haptics) {
      switch (p) {
        case Phase.inhale:
        case Phase.exhale:
        case Phase.rest:
          HapticFeedback.selectionClick();
          break;
        case Phase.hold:
          HapticFeedback.lightImpact();
          break;
      }
    }

    switch (p) {
      case Phase.inhale:
        _scale.animateTo(1.00, duration: _cfg.inhale, curve: Curves.easeInOutCubic);
        _timer = Timer(_cfg.inhale, () => _go(Phase.hold));
        break;
      case Phase.hold:
        _timer = Timer(_cfg.hold, () => _go(Phase.exhale));
        break;
      case Phase.exhale:
        _scale.animateTo(0.70, duration: _cfg.exhale, curve: Curves.easeInOutCubic);
        _timer = Timer(_cfg.exhale, () => _go(Phase.rest));
        break;
      case Phase.rest:
        _timer = Timer(_cfg.rest, () async {
          await _saveToday();                   // count session here
          if (_haptics) HapticFeedback.mediumImpact();
          if (_running) _go(Phase.inhale);
        });
        break;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scale.dispose();
    _float.dispose();
    super.dispose();
  }

  String get _label => switch (_phase) {
        Phase.inhale => 'Inhale',
        Phase.hold   => 'Hold',
        Phase.exhale => 'Exhale',
        Phase.rest   => 'Rest',
      };

  @override
  Widget build(BuildContext context) {
    final bg = CupertinoDynamicColor.resolve(T.bg, context);
    final ink = CupertinoDynamicColor.resolve(T.ink, context);

    return CupertinoPageScaffold(
      backgroundColor: bg,
      navigationBar: CupertinoNavigationBar(
        middle: Text('MindBreath',
            style: TextStyle(color: ink, fontSize: 22, fontWeight: FontWeight.w600)),
        border: null,
        backgroundColor: CupertinoDynamicColor.resolve(T.surface, context),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // small chip with current phase + haptics toggle
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: _Glass(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_label, style: TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w600)),
                      Row(children: [
                        Text('Haptics', style: TextStyle(color: ink.withOpacity(.6))),
                        const SizedBox(width: 8),
                        CupertinoSwitch(
                          value: _haptics,
                          onChanged: (v) => setState(() => _haptics = v),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),

            // Centered globe (takes remaining space)
            Expanded(
              child: AnimatedBuilder(
                animation: Listenable.merge([_scale, _float]),
                builder: (context, _) {
                  // centered, with gentle float
                  final w = MediaQuery.of(context).size.width;
                  final base = w * 0.7;
                  final s    = _scale.value;
                  final dy   = math.sin(_float.value * 2 * math.pi) * 6; // px
                  final d    = base * s;

                  return Center(
                    child: Transform.translate(
                      offset: Offset(0, dy),
                      child: SizedBox(
                        width: d,
                        height: d,
                        child: _RingsGlobe(label: _label),
                      ),
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
                      color: CupertinoDynamicColor.resolve(T.primary, context).withOpacity(0.12),
                      child: Text('Stop',
                          style: TextStyle(color: ink, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Frosted minimal card
class _Glass extends StatelessWidget {
  final Widget child;
  const _Glass({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: CupertinoDynamicColor.resolve(T.surface, context),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 18,
                offset: Offset(0, 10),
              )
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Minimal concentric “globe” with soft depth
class _RingsGlobe extends StatelessWidget {
  final String label;
  const _RingsGlobe({required this.label});

  @override
  Widget build(BuildContext context) {
    final c1 = T.ring(context, .18);
    final c2 = T.ring(context, .10);
    final c3 = T.ring(context, .06);
    final ink = CupertinoDynamicColor.resolve(T.ink, context);

    return Stack(
      fit: StackFit.expand,
      children: [
        // drop shadow for depth
        Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: Color(0x25000000), blurRadius: 38, spreadRadius: 2, offset: Offset(0, 18)),
              BoxShadow(color: Color(0x12000000), blurRadius: 8, offset: Offset(0, 2)),
            ],
          ),
        ),
        // rings
        CustomPaint(
          painter: _RingsPainter(c1: c1, c2: c2, c3: c3),
        ),
        // center label
        Center(
          child: Text(
            label,
            style: TextStyle(
              color: ink.withOpacity(.85),
              fontSize: 24,
              fontWeight: FontWeight.w600,
              letterSpacing: .2,
            ),
          ),
        ),
      ],
    );
  }
}

class _RingsPainter extends CustomPainter {
  final Color c1, c2, c3;
  _RingsPainter({required this.c1, required this.c2, required this.c3});

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);

    // outer
    final p1 = Paint()..color = c1..isAntiAlias = true;
    canvas.drawCircle(center, r, p1);

    // middle
    final p2 = Paint()..color = c2..isAntiAlias = true;
    canvas.drawCircle(center, r * .66, p2);

    // inner
    final p3 = Paint()..color = c3..isAntiAlias = true;
    canvas.drawCircle(center, r * .36, p3);
  }

  @override
  bool shouldRepaint(covariant _RingsPainter old) =>
      old.c1 != c1 || old.c2 != c2 || old.c3 != c3;
}

/// ================= Progress page (simple & working) =============
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
    for (final s in _prefs.getStringList('week') ?? []) {
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
      final k = "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
      return (d, _week[k] ?? 0);
    });

    final bg = CupertinoDynamicColor.resolve(T.bg, context);
    final ink = CupertinoDynamicColor.resolve(T.ink, context);

    return CupertinoPageScaffold(
      backgroundColor: bg,
      navigationBar: CupertinoNavigationBar(
        middle: Text('Progress',
            style: TextStyle(color: ink, fontSize: 22, fontWeight: FontWeight.w600)),
        border: null,
        backgroundColor: CupertinoDynamicColor.resolve(T.surface, context),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _Glass(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Weekly Sessions',
                      style: TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: days.map((e) {
                      final v = e.$2;
                      final h = (v == 0) ? 18.0 : (18 + (v.clamp(0, 6) * 12)).toDouble();
                      return Column(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeInOutCubic,
                            width: 20,
                            height: h,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: T.ring(context, v == 0 ? .10 : .28),
                              boxShadow: v == 0
                                  ? null
                                  : const [BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 6))],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(_dayLetter(e.$1),
                              style: TextStyle(color: ink.withOpacity(.55))),
                        ],
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  Text("Today: ${_today()} session(s)",
                      style: TextStyle(color: ink.withOpacity(.65))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  int _today() {
    final t = DateTime.now();
    final k = "${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}";
    return _week[k] ?? 0;
  }

  static String _dayLetter(DateTime d) => ['S', 'M', 'T', 'W', 'T', 'F', 'S'][d.weekday % 7];
}
