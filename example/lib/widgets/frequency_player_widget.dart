import 'package:flutter/material.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';

class FrequencyPlayerWidget extends StatefulWidget {
  final FrequencyPlayer frequencyPlayer;

  const FrequencyPlayerWidget({super.key, required this.frequencyPlayer});

  @override
  State<FrequencyPlayerWidget> createState() => _FrequencyPlayerWidgetState();
}

class _FrequencyPlayerWidgetState extends State<FrequencyPlayerWidget> {
  late WaveType _selectedWaveType;
  double _frequency = 440.0;
  double _loudness = 1.0;

  @override
  void initState() {
    super.initState();
    _selectedWaveType = widget.frequencyPlayer.supportedFrequencyPlayerWaveTypes.first;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        DropdownButton<WaveType>(
          value: _selectedWaveType,
          items: widget.frequencyPlayer.supportedFrequencyPlayerWaveTypes
              .map((waveType) {
            return DropdownMenuItem<WaveType>(
              value: waveType,
              child: Text(waveType.toString()),
            );
          }).toList(),
          onChanged: (newValue) {
            setState(() {
              _selectedWaveType = newValue!;
            });
          },
        ),
        Expanded(
          child: Column(
            children: [
              Text('Frequency: ${_frequency.toStringAsFixed(0)} Hz'),
              Slider(
                value: _frequency,
                min: 1.0,
                max: 20000.0,
                onChanged: (newValue) {
                  setState(() {
                    _frequency = newValue;
                  });
                },
              ),
            ],
          ),
        ),
        Column(
          children: [
            Text('Loudness: ${(_loudness * 100).toStringAsFixed(0)}%'),Slider(
              value: _loudness,
              min: 0.0,
              max: 1.0,
              onChanged: (newValue) {
                setState(() {
                  _loudness = newValue;
                });
              },
            ),
          ],
        ),
        ElevatedButton(
          onPressed: () {
            widget.frequencyPlayer.playFrequency(
              _selectedWaveType,
              frequency: _frequency,
              loudness: _loudness,
            );
          },
          child: const Text('Play'),
        ),
      ],
    );
  }
}
