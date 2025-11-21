import 'package:flutter/material.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';

class JinglePlayerWidget extends StatefulWidget {
  final JinglePlayer jinglePlayer;

  const JinglePlayerWidget({super.key, required this.jinglePlayer});

  @override
  State<JinglePlayerWidget> createState() => _JinglePlayerWidgetState();
}

class _JinglePlayerWidgetState extends State<JinglePlayerWidget> {
  late Jingle _selectedJingle;

  @override
  void initState() {
    super.initState();
    _selectedJingle = widget.jinglePlayer.supportedJingles.first;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        DropdownButton<Jingle>(
          value: _selectedJingle,
          items: widget.jinglePlayer.supportedJingles
              .map((jingle) {
            return DropdownMenuItem<Jingle>(
              value: jingle,
              child: Text(jingle.toString()),
            );
          }).toList(),
          onChanged: (newValue) {
            setState(() {
              _selectedJingle = newValue!;
            });
          },
        ),
        const SizedBox(width: 20),
        ElevatedButton(
          onPressed: () {
            widget.jinglePlayer.playJingle(_selectedJingle);
          },
          child: const Text('Play'),
        ),
      ],
    );
  }
}
