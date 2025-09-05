import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const MindBreathApp());

class MindBreathApp extends StatelessWidget {
  const MindBreathApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MindBreath',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const BreathingScreen(),
    );
  }
}

class BreathingScreen extends StatefulWidget {
  const BreathingScreen({super.key});
  @override
  State<BreathingScreen> createState() => _BreathingScreenState();
}

class _BreathingScreenState extends State<BreathingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctl;
  bool _running = false;
  bool _haptics = true;

  static const int inhale = 4;
  static const int hold = 2;
  static const int exhale = 4;
  static const int rest = 2;

  String? _lastPhase;

  @override
  void initState() {
    super.initState();
    final total = Duration(seconds: inhale + hold + exhale + rest);
    _ctl = AnimationController(vsync: this, duration: total)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _ctl.repeat();
      });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  String _phaseText(double t) {
    final total = (inhale + hold + exhale + rest).toDouble();
    final p = t * total;
    if (p < inhale) return 'Inhale';
    if (p < inhale + hold) return 'Hold';
    if (p < inhale + hold + exhale) return 'Exhale';
    return 'Rest';
  }

  void _maybeHaptic(String phaseNow, String phasePrev) {
    if (!_haptics || phaseNow == phasePrev) return;
    HapticFeedback.selectionClick();
  }

  void _phaseTransitionDetector(String current) {
    if (_lastPhase == null) {
      _lastPhase = current;
      return;
    }
    if (current != _lastPhase) {
      _maybeHaptic(current, _lastPhase!);
      _lastPhase = current;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MindBreath')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: AnimatedBuilder(
                  animation: _ctl,
                  builder: (context, _) {
                    final t = _ctl.value;
                    final total = (inhale + hold + exhale + rest).toDouble();
                    final p = t * total;
                    double scale;
                    if (p < inhale) {
                      scale = 0.6 + 0.4 * (p / inhale);
                    } else if (p < inhale + hold) {
                      scale = 1.0;
                    } else if (p < inhale + hold + exhale) {
                      final q = (p - inhale - hold) / exhale;
                      scale = 1.0 - 0.4 * q;
                    } else {
                      scale = 0.6;
                    }
                    final phaseNow = _phaseText(t);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _phaseTransitionDetector(phaseNow);
                    });
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Transform.scale(
                            scale: scale,
                            child: Container(
                              width: 240,
                              height: 240,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(colors: [
                                  Theme.of(context).colorScheme.primaryContainer,
                                  Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.8),
                                ]),
                                boxShadow: const [
                                  BoxShadow(
                                      blurRadius: 24,
                                      spreadRadius: 2,
                                      offset: Offset(0, 6)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(phaseNow,
                              style:
                                  Theme.of(context).textTheme.headlineMedium),
                          const SizedBox(height: 8),
                          Text(_running ? 'Cycle running' : 'Paused'),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  FilledButton(
                    onPressed: () {
                      if (!_running) {
                        setState(() => _running = true);
                        _ctl.reset();
                        _ctl.forward();
                      }
                    },
                    child: const Text('Start'),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      setState(() => _running = false);
                      _ctl.stop();
                    },
                    child: const Text('Stop'),
                  ),
                  Row(
                    children: [
                      const Text('Haptics'),
                      Switch(
                        value: _haptics,
                        onChanged: (v) => setState(() => _haptics = v),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Disclaimer: This app provides general relaxation guidance only. It is not medical advice.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
