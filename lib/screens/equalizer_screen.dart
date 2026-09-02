import 'package:flutter/material.dart';
import 'package:equalizer_plugin/equalizer_plugin.dart';
import 'dart:math';

class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  final Equalizer _equalizer = Equalizer();
  List<double> _bandValues = List.filled(10, 0.0);
  bool _isEnabled = true;

  @override
  void initState() {
    super.initState();
    _equalizer.init();
    _loadBands();
  }

  Future<void> _loadBands() async {
    final values = await _equalizer.getBandValues();
    setState(() {
      _bandValues = values;
    });
  }

  void _updateBand(int index, double value) {
    setState(() {
      _bandValues[index] = value;
      _equalizer.setBandLevel(index, value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Эквалайзер', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              Switch(value: _isEnabled, onChanged: (v) { setState(() => _isEnabled = v); _equalizer.setEnabled(v); }),
            ],
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _bandValues.length,
              itemBuilder: (context, index) {
                return _buildSlider(index);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider(int index) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text('${(32 * pow(2, index)).toInt()}Hz'),
          const SizedBox(width: 16),
          Expanded(
            child: Slider(
              value: _bandValues[index].clamp(-15.0, 15.0),
              min: -15,
              max: 15,
              onChanged: (v) => _updateBand(index, v),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _equalizer.dispose();
    super.dispose();
  }
}
