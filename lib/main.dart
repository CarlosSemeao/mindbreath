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
      tabBar: const CupertinoTabBar(
        backgroundColor: Color(0xF0FFFFFF),
        items: [
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.sun_max), label: 'Breathe'),
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.chart_bar_alt_fill), label: 'Progress'),
        ],
      ),
      tabBuilder: (context, index) {
        switch (index) {
          case 0:
            return const BreathePage();
          default:
            return const ProgressPage();
        }
      },
    );
  }
}

/// Palette — soft, oceanic, spa-grade
class Ink {
  static const bgTop = Color(0xFFEFF4FF);
  static const bgBottom = Color(0xFFF8FAFF);
  static const glassStroke = Color(0x40FFFFFF);
  static const orbDeep = Color(0xFF2F6BFF);
  static const orbMid = Color(0xFF82B0FF);
  static const orbLight = Color(0xFFE2ECFF);
  static const label = Color(0xFF0F1222);
  static const labelSub = Color(0x990F1222);
  static const action = Color(0xFF0E1A4A);
}

/// ========================= BREATHE PAGE =========================
enum Phase { inhale, hold, exhale, rest }

class BreathConfig {
  final Duration inhale, hold, exhale, rest;
  const BreathConfig({
    this.inhale = const Duration(seconds: 4),
    this.hold = const Duration(seconds: 4),
    this.exhale = const Duration(seconds: 6),
    this.rest = const Duration(seconds: 2),
  });
}

class BreathePage extends StatefulWidget {
  const BreathePage({super.key});
  @override
  State<BreathePage> createState() => _BreathePageState();
}

class _BreathePageState extends State<BreathePage> with TickerProviderStateMixin {
  final _cfg = const BreathConfig();
  late final AnimationController _orbScale;   // size + “breathing”
  late final AnimationController _orbDrift;   // slow 3D parallax drift
  Phase _phase = Phase.rest;
  Timer? _timer;
  bool _running = false;
  bool _hapticsOn = true;

  late SharedPreferences _prefs;
  Map<String, int> _weekCounts = {};

  @override
  void initState() {
    super.initState();
    _orbScale = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
      lowerBound: 0.7,
      upperBound: 1.0,
      value: 0.85,
    );

    _orbDrift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

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

    final cutoff = t.subtract(const Duration(days: 7));
    _weekCounts.removeWhere((k, _) => DateTime.parse(k)
        .isBefore(DateTime(cutoff.year, cutoff.month, cutoff.day)));

    final list = _weekCounts.entries.map((e) => "${e.key}|${e.value}").toList();
    await _prefs.setStringList('week', list);
  }

  // Engine
  void _start() {
    if (_running) return;
    setState(() => _running = true);
    _runPhase(Phase.inhale);
  }

  void _stop() {
    _timer?.cancel();
    _orbScale.stop();
    setState(() {
      _running = false;
      _phase = Phase.rest;
      _orbScale.value = 0.85;
    });
  }

  void _runPhase(Phase next) {
    _timer?.cancel();
    setState(() => _phase = next);
    _haptic(next);

    switch (next) {
      case Phase.inhale:
        _orbScale.animateTo(1.0, duration: _cfg.inhale, curve: Curves.easeInOutCubic);
        _timer = Timer(_cfg.inhale, () => _runPhase(Phase.hold));
        break;
      case Phase.hold:
        _timer = Timer(_cfg.hold, () => _runPhase(Phase.exhale));
        break;
      case Phase.exhale:
        _orbScale.animateTo(0.7, duration: _cfg.exhale, curve: Curves.easeInOutCubic);
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

  @override
  void dispose() {
    _timer?.cancel();
    _orbScale.dispose();
    _orbDrift.dispose();
    super.dispose();
  }

  String get _label => switch (_phase) {
        Phase.inhale => 'Inhale',
        Phase.hold => 'Hold',
        Phase.exhale => 'Exhale',
        Phase.rest => 'Rest',
      };

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return CupertinoPageScaffold(
      backgroundColor: Ink.bgBottom,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('MindBreath', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        border: null,
        backgroundColor: Color(0xCCFFFFFF),
      ),
      child: Stack(
        children: [
          // Soft background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Ink.bgTop, Ink.bgBottom],
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 12),

                // Glass card with phase label
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _Glass(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Ink.label)),
                          Row(
                            children: [
                              const Text('Haptics', style: TextStyle(color: Ink.labelSub)),
                              const SizedBox(width: 8),
                              CupertinoSwitch(
                                value: _hapticsOn,
                                onChanged: (v) => setState(() => _hapticsOn = v),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const Spacer(),

                // Liquid-glass breathing orb
                AnimatedBuilder(
                  animation: Listenable.merge([_orbScale, _orbDrift]),
                  builder: (context, _) {
                    final drift = math.sin(_orbDrift.value * 2 * math.pi) * 0.07;
                    final scale = _orbScale.value + drift * 0.03;
                    final diameter = size.width * 0.68 * scale;
                    return Center(
                      child: _LiquidOrb(diameter: diameter, phase: _phase, t: _orbDrift.value),
                    );
                  },
                ),

                const SizedBox(height: 28),

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
                          color: const Color(0xFFE9ECF6),
                          child: const Text('Stop', style: TextStyle(color: Ink.action)),
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

/// Frosted glass container
class _Glass extends StatelessWidget {
  final Widget child;
  const _Glass({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0x66FFFFFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Ink.glassStroke, width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The liquid-glass 3D orb with inner glow and rim light
class _LiquidOrb extends StatelessWidget {
  final double diameter;
  final Phase phase;
  final double t; // 0..1 drifting time
  const _LiquidOrb({required this.diameter, required this.phase, required this.t});

  @override
  Widget build(BuildContext context) {
    // Subtle color shift by phase
    final tint = switch (phase) {
      Phase.inhale => Ink.orbMid,
      Phase.hold => Ink.orbLight,
      Phase.exhale => Ink.orbDeep,
      Phase.rest => Ink.orbMid,
    };

    return CustomPaint(
      size: Size.square(diameter),
      painter: _OrbPainter(t: t, tint: tint),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final double t; // 0..1
  final Color tint;
  _OrbPainter({required this.t, required this.tint});

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    final paint = Paint()..isAntiAlias = true;

    // Base radial gradient (depth)
    final base = RadialGradient(
      center: Alignment(0.0 + 0.2 * math.sin(t * 2 * math.pi), 0.0 - 0.2 * math.cos(t * 2 * math.pi)),
      radius: 0.85,
      colors: [tint, Ink.orbDeep, const Color(0xFF0B1440)],
      stops: const [0.0, 0.55, 1.0],
    );
    paint.shader = base.createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, paint);

    // Inner glow (additive)
    final inner = Paint()
      ..shader = RadialGradient(
        colors: [Ink.orbLight.withOpacity(0.45), Colors.transparent],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: c.translate(-r * 0.15, -r * 0.15), radius: r * 0.9))
      ..blendMode = BlendMode.plus
      ..isAntiAlias = true;
    canvas.drawCircle(c, r * 0.95, inner);

    // Rim light / specular highlight
    final rim = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [
          Colors.transparent,
          Colors.white.withOpacity(0.28),
          Colors.transparent,
        ],
        stops: const [0.0, 0.08, 0.16],
        transform: GradientRotation(1.2 + t * 2 * math.pi),
      ).createShader(Rect.fromCircle(center: c, radius: r))
      ..blendMode = BlendMode.screen
      ..isAntiAlias = true;
    canvas.drawCircle(c, r, rim);

    // Soft shadow under the orb (ambient drop)
    final shadow = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18)
      ..color = const Color(0x33000000);
    canvas.drawOval(
      Rect.fromCenter(center: c.translate(0, r * 0.85), width: r * 1.2, height: r * 0.32),
      shadow,
    );
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) => old.t != t || old.tint != tint;
}

/// ========================= PROGRESS PAGE =========================

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
      if (parts.length == 2) {
        _week[parts[0]] = int.tryParse(parts[1]) ?? 0;
      }
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
      backgroundColor: Ink.bgBottom,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Progress', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        border: null,
        backgroundColor: Color(0xCCFFFFFF),
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
                  const Text('Weekly Sessions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Ink.label)),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: days.map((e) {
                      final int v = e.$2;
                      final h = (v == 0) ? 20.0 : (20 + (v.clamp(0, 6) * 12)).toDouble();
                      return Column(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOutCubic,
                            width: 22,
                            height: h,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: v == 0
                                    ? [const Color(0xFFE8ECF8), const Color(0xFFE8ECF8)]
                                    : [Ink.orbLight, Ink.orbMid],
                              ),
                              boxShadow: v == 0 ? null : const [
                                BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 6)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(_dayLetter(e.$1), style: const TextStyle(color: Ink.labelSub)),
                        ],
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Today: ${_todayCount()} session(s)',
                    style: const TextStyle(color: Ink.labelSub),
                  ),
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
