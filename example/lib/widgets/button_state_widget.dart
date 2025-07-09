import 'package:flutter/material.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';

class ButtonStateWidget extends StatelessWidget {
  final ButtonManager buttonManager;

  const ButtonStateWidget({super.key, required this.buttonManager});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ButtonEvent>(
      stream: buttonManager.buttonEvents,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return Text("Button State: ${snapshot.data}");
        } else if (snapshot.hasError) {
          return Text("Error: ${snapshot.error}");
        } else {
          return const CircularProgressIndicator();
        }
      },
    );
  }
}