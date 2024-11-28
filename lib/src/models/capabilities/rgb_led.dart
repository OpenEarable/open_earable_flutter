abstract class RgbLed {
  Future<void> writeLedColor({
    required int r,
    required int g,
    required int b,
  });
}
