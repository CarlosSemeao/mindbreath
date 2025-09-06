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

/* ---------- Theme: teal + minimal, with dark ink text ---------- */
class T {
  static const primary = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF14B8A6), // teal
    darkColor: Color(0xFF2DD4BF),
  );
  static const bg = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFF6FBFA),
    darkColor: Color(0xFF0C1413),
  );
  static const ink = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF1F2937), // dark gray for text
    darkColor: Color(0xFFE5E7EB),
  );
  static const surface = CupertinoDynamicColor.withBrightness(
    color: Color(0xAAFFFFFF),
    darkColor: Color(0x3314B8A6),
  );
  static Color ring(BuildContext c, double a) =>
      CupertinoDynamicColor.resolve(primary, c).withOpacity(a);
}

/* ---------- lightweight notifier so Progress updates instantly --- */
final progressTick = ValueNotifier<int>(0);

class MindBreathApp extends StatelessWidget {
  const MindBreathApp({super.key});
  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      theme: const CupertinoThemeData(
        primaryColor: T.primary,
        barBackgroundColor: T.surface,
      ),
      home: const RootTabs(),
    );
  }
}

/* -------------------------- Tabs ------------------------------- */
class RootTabs extends StatelessWidget {
  const RootTabs({super.key});
  @override
  Widget build(BuildContext context) {
    return CupertinoTabScaffold(
      tabBar: CupertinoTabBar(
        backgroundColor: CupertinoDynamicColor.resolve(T.surface, context),
        items: const [
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.circle), label: 'Breathe'),
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.chart_bar_alt_fill), label: 'Progress'),
        ],
      ),
      tabBuilder: (_, i) => CupertinoTabView(
        builder: (_) => i == 0 ? const BreathePage() : const ProgressPage(),
      ),
    );
  }
}

/* ------------------ Breathing settings & store ------------------ */
class BreathSettings {
  final int inh, hold, ex, rest; // seconds
  const BreathSettings(this.inh, this.hold, this.ex, this.rest);

  static const beginner = BreathSettings(4, 2, 6, 2);
  static const balanced = BreathSettings(6, 6, 8, 4);   // slightly longer default
  static const advanced = BreathSettings(8, 10, 10, 4);

  BreathSettings copyWith({int? inh, int? hold, int? ex, int? rest}) =>
      BreathSettings(inh ?? this.inh, hold ?? this.hold, ex ?? this.ex, rest ?? this.rest);
}

class SettingsStore {
  static const _k = 'MB.settings.v1';
  final SharedPreferences prefs;
  SettingsStore(this.prefs);
  BreathSettings load() {
    final s = prefs.getStringList(_k);
    if (s == null || s.length != 4) return BreathSettings.balanced;
    return BreathSettings(int.parse(s[0]), int.parse(s[1]), int.parse(s[2]), int.parse(s[3]));
  }
  Future<void> save(BreathSettings v) =>
      prefs.setStringList(_k, [v.inh.toString(), v.hold.toString(), v.ex.toString(), v.rest.toString()]);
}

/* ------------------------- Breathe page ------------------------- */
enum Phase { inhale, hold, exhale, rest }

class BreathePage extends StatefulWidget {
  const BreathePage({super.key});
  @override
  State<BreathePage> createState() => _BreathePageState();
}

class _BreathePageState extends State<BreathePage> with TickerProviderStateMixin {
  late final AnimationController _scale;
  late final AnimationController _float;
  Phase _phase = Phase.rest;
  Timer? _timer;
  bool _running = false;
  bool _haptics = true;

  late SharedPreferences _prefs;
  late SettingsStore _store;
  BreathSettings _settings = BreathSettings.balanced;

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
    _float = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
    _init();
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    _store = SettingsStore(_prefs);
    _settings = _store.load();
    for (final s in _prefs.getStringList('week') ?? []) {
      final p = s.split('|');
      if (p.length == 2) _week[p[0]] = int.tryParse(p[1]) ?? 0;
    }
    setState(() {});
  }

  Future<void> _saveToday() async {
    final t = DateTime.now();
    final k = "${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}";
    _week[k] = (_week[k] ?? 0) + 1;
    final cutoff = t.subtract(const Duration(days: 7));
    _week.removeWhere((d, _) => DateTime.parse(d).isBefore(DateTime(cutoff.year, cutoff.month, cutoff.day)));
    await _prefs.setStringList('week', _week.entries.map((e) => "${e.key}|${e.value}").toList());
    progressTick.value++; // notify Progress page to refresh immediately
  }

  void _start() { if (_running) return; setState(() => _running = true); _go(Phase.inhale); }
  void _stop() {
    _timer?.cancel();
    _scale.stop();
    setState(() { _running = false; _phase = Phase.rest; _scale.value = 0.85; });
  }

  Duration get _dInhale => Duration(seconds: _settings.inh);
  Duration get _dHold   => Duration(seconds: _settings.hold);
  Duration get _dExhale => Duration(seconds: _settings.ex);
  Duration get _dRest   => Duration(seconds: _settings.rest);

  void _go(Phase p) {
    _timer?.cancel();
    setState(() => _phase = p);
    if (_haptics) {
      switch (p) {
        case Phase.hold: HapticFeedback.lightImpact(); break;
        default: HapticFeedback.selectionClick(); break;
      }
    }

    switch (p) {
      case Phase.inhale:
        _scale.animateTo(1.00, duration: _dInhale, curve: Curves.easeInOutCubic);
        _timer = Timer(_dInhale, () => _go(Phase.hold));
        break;
      case Phase.hold:
        _timer = Timer(_dHold, () => _go(Phase.exhale));
        break;
      case Phase.exhale:
        _scale.animateTo(0.70, duration: _dExhale, curve: Curves.easeInOutCubic);
        _timer = Timer(_dExhale, () async {
          // COUNT A SESSION *IMMEDIATELY* AFTER EXHALE
          await _saveToday();
          _go(Phase.rest); // enter rest after saving so Stop won’t lose the session
        });
        break;
      case Phase.rest:
        _timer = Timer(_dRest, () { if (_running) _go(Phase.inhale); });
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
  void dispose() { _timer?.cancel(); _scale.dispose(); _float.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final bg  = CupertinoDynamicColor.resolve(T.bg, context);
    final ink = CupertinoDynamicColor.resolve(T.ink, context);

    return CupertinoPageScaffold(
      backgroundColor: bg,
      navigationBar: CupertinoNavigationBar(
        middle: const _BrandTitle(), // elegant gradient brand
        border: null,
        backgroundColor: CupertinoDynamicColor.resolve(T.surface, context),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _openSettings,
          child: Icon(CupertinoIcons.gear_alt, size: 22, color: ink),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: _Glass(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_label, style: TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w600)),
                      Row(
                        children: [
                          Text('Haptics', style: TextStyle(color: ink.withOpacity(.6))),
                          const SizedBox(width: 8),
                          CupertinoSwitch(value: _haptics, onChanged: (v) => setState(() => _haptics = v)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Perfectly centered globe
            Expanded(
              child: AnimatedBuilder(
                animation: Listenable.merge([_scale, _float]),
                builder: (context, _) {
                  final w = MediaQuery.of(context).size.width;
                  final base = w * 0.72;
                  final s = _scale.value;
                  final dy = math.sin(_float.value * 2 * math.pi) * 6; // gentle float
                  final d = base * s;
                  return Center(
                    child: Transform.translate(
                      offset: Offset(0, dy),
                      child: SizedBox(width: d, height: d, child: _RingsGlobe(label: _label)),
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
                  Expanded(child: CupertinoButton.filled(onPressed: _start, child: const Text('Start'))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CupertinoButton(
                      onPressed: _stop,
                      color: CupertinoDynamicColor.resolve(T.primary, context).withOpacity(0.12),
                      child: Text('Stop', style: TextStyle(color: ink, fontWeight: FontWeight.w600)),
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

  Future<void> _openSettings() async {
    final result = await showCupertinoModalPopup<BreathSettings>(
      context: context,
      builder: (_) => _SettingsSheet(initial: _settings),
    );
    if (result != null) { setState(() => _settings = result); await _store.save(result); }
  }
}

/* --------------------- Frosted card ----------------------------- */
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
              BoxShadow(color: Color(0x1A000000), blurRadius: 20, offset: Offset(0, 12)),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/* -------------------- Minimal “globe” --------------------------- */
class _RingsGlobe extends StatelessWidget {
  final String label;
  const _RingsGlobe({required this.label});
  @override
  Widget build(BuildContext context) {
    final c1 = T.ring(context, .16);
    final c2 = T.ring(context, .09);
    final c3 = T.ring(context, .05);
    final ink = CupertinoDynamicColor.resolve(T.ink, context);

    return Stack(
      fit: StackFit.expand,
      children: [
        // single soft shadow for crisp definition
        Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Color(0x1A000000), blurRadius: 26, offset: Offset(0, 14))],
          ),
        ),
        CustomPaint(painter: _RingsPainter(c1: c1, c2: c2, c3: c3)),
        Center(
          child: Text(
            label,
            style: TextStyle(color: ink.withOpacity(.85), fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: .2),
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
    final c = Offset(r, r);
    canvas
      ..drawCircle(c, r, Paint()..color = c1..isAntiAlias = true)
      ..drawCircle(c, r * .66, Paint()..color = c2..isAntiAlias = true)
      ..drawCircle(c, r * .36, Paint()..color = c3..isAntiAlias = true);
  }
  @override
  bool shouldRepaint(covariant _RingsPainter o) => o.c1 != c1 || o.c2 != c2 || o.c3 != c3;
}

/* ------------------ Brand title (stylish) ----------------------- */
class _BrandTitle extends StatelessWidget {
  const _BrandTitle();
  @override
  Widget build(BuildContext context) {
    final light = CupertinoDynamicColor.resolve(T.primary, context);
    final deep  = light.withOpacity(.7);
    return ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFF2DD4BF), Color(0xFF14B8A6)],
      ).createShader(rect),
      blendMode: BlendMode.srcIn,
      child: const Text(
        'MindBreath',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/* ---------------- Settings sheet (dark-gray text) --------------- */
class _SettingsSheet extends StatefulWidget {
  final BreathSettings initial;
  const _SettingsSheet({required this.initial});
  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

enum _Mode { preset, custom }

class _SettingsSheetState extends State<_SettingsSheet> {
  _Mode mode = _Mode.preset;
  int preset = 1; // 0 beginner, 1 balanced, 2 advanced
  late BreathSettings custom;

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    if (_eq(s, BreathSettings.beginner)) preset = 0;
    else if (_eq(s, BreathSettings.balanced)) preset = 1;
    else if (_eq(s, BreathSettings.advanced)) preset = 2;
    else { mode = _Mode.custom; }
    custom = s;
  }

  bool _eq(BreathSettings a, BreathSettings b) =>
      a.inh == b.inh && a.hold == b.hold && a.ex == b.ex && a.rest == b.rest;

  BreathSettings _selected() {
    if (mode == _Mode.custom) return custom;
    return [BreathSettings.beginner, BreathSettings.balanced, BreathSettings.advanced][preset];
  }

  @override
  Widget build(BuildContext context) {
    final ink = CupertinoDynamicColor.resolve(T.ink, context);
    return CupertinoActionSheet(
      title: Text('Breathing Settings', style: TextStyle(color: ink, fontWeight: FontWeight.w600)),
      message: Column(
        children: [
          const SizedBox(height: 8),
          CupertinoSegmentedControl<int>(
            groupValue: mode == _Mode.preset ? preset : -1,
            onValueChanged: (v) => setState(() { mode = _Mode.preset; preset = v; }),
            // dark-gray text, subtle teal selection
            selectedColor: T.ring(context, .18),
            unselectedColor: const Color(0x00000000),
            borderColor: T.ring(context, .35),
            children: {
              0: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('Beginner', style: TextStyle(color: ink))),
              1: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('Balanced', style: TextStyle(color: ink))),
              2: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('Advanced', style: TextStyle(color: ink))),
            },
          ),
          const SizedBox(height: 12),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            onPressed: () => setState(() => mode = _Mode.custom),
            child: Text('Or set custom times', style: TextStyle(color: ink)),
          ),
          const SizedBox(height: 8),
          if (mode == _Mode.custom) _CustomPickers(
            value: custom,
            onChanged: (s) => setState(() => custom = s),
          ),
        ],
      ),
      actions: [
        CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(_selected()),
          isDefaultAction: true,
          child: Text('Save', style: TextStyle(color: ink)),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.pop(context),
        isDestructiveAction: false,
        child: Text('Cancel', style: TextStyle(color: ink)),
      ),
    );
  }
}

class _CustomPickers extends StatelessWidget {
  final BreathSettings value;
  final ValueChanged<BreathSettings> onChanged;
  const _CustomPickers({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final ink = CupertinoDynamicColor.resolve(T.ink, context);

    Widget col(String label, int current, ValueChanged<int> onSec) {
      return Expanded(
        child: Column(
          children: [
            Text(label, style: TextStyle(color: ink)),
            SizedBox(
              height: 120,
              child: CupertinoPicker(
                itemExtent: 32,
                scrollController: FixedExtentScrollController(initialItem: (current.clamp(1, 60)) - 1),
                onSelectedItemChanged: (i) => onSec(i + 1),
                children: List.generate(60, (i) => Center(child: Text('${i + 1}s', style: TextStyle(color: ink)))),
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        col('Inhale', value.inh, (s) => onChanged(value.copyWith(inh: s))),
        col('Hold',   value.hold, (s) => onChanged(value.copyWith(hold: s))),
        col('Exhale', value.ex,   (s) => onChanged(value.copyWith(ex: s))),
        col('Rest',   value.rest, (s) => onChanged(value.copyWith(rest: s))),
      ],
    );
  }
}

/* ------------------------ Progress page ------------------------- */
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
    // refresh instantly whenever a session is saved
    progressTick.addListener(_load);
  }

  @override
  void dispose() {
    progressTick.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    final map = <String, int>{};
    for (final s in _prefs.getStringList('week') ?? []) {
      final p = s.split('|'); if (p.length == 2) map[p[0]] = int.tryParse(p[1]) ?? 0;
    }
    setState(() => _week = map);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final days = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      final k = "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
      return (d, _week[k] ?? 0);
    });

    final bg  = CupertinoDynamicColor.resolve(T.bg, context);
    final ink = CupertinoDynamicColor.resolve(T.ink, context);

    return CupertinoPageScaffold(
      backgroundColor: bg,
      navigationBar: CupertinoNavigationBar(
        middle: Text('Progress', style: TextStyle(color: ink, fontSize: 22, fontWeight: FontWeight.w600)),
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
                              boxShadow: v == 0 ? null : const [BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 6))],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(_dayLetter(e.$1), style: TextStyle(color: ink.withOpacity(.55))),
                        ],
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  Text('Today: ${_today()} session(s)', style: TextStyle(color: ink.withOpacity(.65))),
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
