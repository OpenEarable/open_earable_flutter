import 'package:flutter/material.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';

class StoragePathAudioPlayerWidget extends StatefulWidget {
  final StoragePathAudioPlayer audioPlayer;

  const StoragePathAudioPlayerWidget({Key? key, required this.audioPlayer})
      : super(key: key);

  @override
  State<StoragePathAudioPlayerWidget> createState() =>
      _StoragePathAudioPlayerWidgetState();
}

class _StoragePathAudioPlayerWidgetState
    extends State<StoragePathAudioPlayerWidget> {
  final TextEditingController _textEditingController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _textEditingController,
            decoration: const InputDecoration(
              hintText: 'Enter file path',
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            widget.audioPlayer
                .playAudioFromStoragePath(_textEditingController.text);
          },
          child: const Text('Play'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _textEditingController.dispose();
    super.dispose();
  }
}
