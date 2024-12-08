import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';

class RgbLedControlWidget extends StatefulWidget {
  final RgbLed rgbLed;

  const RgbLedControlWidget({Key? key, required this.rgbLed}) : super(key: key);

  @override
  State<RgbLedControlWidget> createState() => _RgbLedControlWidgetState();
}

class _RgbLedControlWidgetState extends State<RgbLedControlWidget> {
  Color _currentColor = Colors.black;

  void _showColorPickerDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Pick a color for the RGB LED'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: _currentColor,
              onColorChanged: (color) {
                setState(() {
                  _currentColor = color;
                });
              },
              pickerAreaHeightPercent: 0.8,
              enableAlpha: false,
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Done'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: _showColorPickerDialog,
          style: ElevatedButton.styleFrom(
            backgroundColor: _currentColor,
            foregroundColor: _currentColor.computeLuminance() > 0.5
                ? Colors.black
                : Colors.white,
          ),
          child: const Text('Choose Color'),
        ),
        const SizedBox(width: 20),
        ElevatedButton(
          onPressed: () {
            widget.rgbLed.writeLedColor(
              r: _currentColor.red,
              g: _currentColor.green,
              b: _currentColor.blue,
            );
          },
          child: const Text('Set'),
        ),
        const SizedBox(width: 20),
        ElevatedButton(
          onPressed: () {
            widget.rgbLed.writeLedColor(r: 0, g: 0, b: 0);
          },
          child: const Text('Off'),
        ),
      ],
    );
  }
}
