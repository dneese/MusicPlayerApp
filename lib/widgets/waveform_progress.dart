import 'package:flutter/material.dart';
import 'dart:math';

class WaveformProgress extends StatelessWidget {
  final double progress;
  final Color color;
  final double height;

  const WaveformProgress({
    super.key,
    required this.progress,
    required this.color,
    this.height = 30,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    final bars = 40;
    final random = Random(42);

    return Container(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Row(
          children: List.generate(bars, (i) {
            final isFilled = i / bars <= clamped;
            final barHeight = 0.4 + (random.nextDouble() * 0.6);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Align(
                  alignment: Alignment.center,
                  child: Container(
                    height: height * barHeight,
                    decoration: BoxDecoration(
                      color: isFilled ? color : color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
