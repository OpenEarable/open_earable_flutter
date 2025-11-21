import 'package:flutter/material.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';

class AudioPlayerControlWidget extends StatelessWidget {
  final AudioPlayerControls audioPlayerControls;

  const AudioPlayerControlWidget({super.key, required this.audioPlayerControls});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: audioPlayerControls.startAudio,
          child: const Text('Start'),
        ),
        const SizedBox(width: 20),
        ElevatedButton(
          onPressed: audioPlayerControls.pauseAudio,
          child: const Text('Pause'),
        ),
        const SizedBox(width: 20),
        ElevatedButton(
          onPressed: audioPlayerControls.stopAudio,
          child: const Text('Stop'),
        ),
      ],
    );
  }
}
