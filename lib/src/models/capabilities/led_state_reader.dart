/// Optional readback of the LED override selected on a device.
abstract class LedStateReader {
  Future<LedState> readLedState();
}

class LedState {
  final bool showStatus;
  final int red;
  final int green;
  final int blue;

  const LedState({
    required this.showStatus,
    required this.red,
    required this.green,
    required this.blue,
  });

  bool get isBlack => red == 0 && green == 0 && blue == 0;
}
