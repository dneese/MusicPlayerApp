import 'package:flutter/material.dart';
import 'dart:math';

class VisualizerWidget extends StatefulWidget {
  final bool isPlaying;
  final Color color;

  const VisualizerWidget({
    super.key,
    required this.isPlaying,
    required this.color,
  });

  @override
  State<VisualizerWidget> createState() => _VisualizerWidgetState();
}

class _VisualizerWidgetState extends State<VisualizerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  List<double> _bars = List.generate(30, (_) => 0.0);
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 100))
      ..addListener(() {
        if (widget.isPlaying) _updateBars();
      });
    _controller.repeat();
  }

  void _updateBars() {
    setState(() {
      _bars = _bars.map((_) => 0.3 + _random.nextDouble() * 0.7).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        _bars.length,
        (index) => Container(
          width: 4,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          height: widget.isPlaying ? 20 + _bars[index] * 40 : 20,
          decoration: BoxDecoration(
            color: widget.color.withOpacity(0.6),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
