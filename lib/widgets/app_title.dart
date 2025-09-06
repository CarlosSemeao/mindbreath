import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;

class AppTitle extends StatelessWidget {
  const AppTitle({super.key});

  @override
  Widget build(BuildContext context) {
    final brightness = CupertinoTheme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    return Text(
      'MindBreath',
      style: TextStyle(
        fontFamily: 'Manrope',
        fontWeight: FontWeight.bold,
        fontSize: 26,
        letterSpacing: 1.2,
        color: isDark ? Colors.teal[100] : Colors.teal[700],
        shadows: [
          Shadow(
            color: isDark ? Colors.black45 : Colors.teal.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }
}
