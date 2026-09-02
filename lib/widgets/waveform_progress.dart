import 'package:flutter/material.dart';
import 'package:liquid_progress_indicator/liquid_progress_indicator.dart';
import 'package:flutter_animate/flutter_animate.dart';

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
    return Container(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: LiquidLinearProgressIndicator(
          value: progress.clamp(0.0, 1.0),
          valueColor: AlwaysStoppedAnimation(color),
          backgroundColor: Colors.grey.withOpacity(0.2),
          center: Text('${(progress * 100).toInt()}%', style: const TextStyle(color: Colors.white, fontSize: 10)),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}
