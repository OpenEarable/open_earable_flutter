part of open_earable_flutter;

class AudioPlayer {
  final BleManager _bleManager;

  AudioPlayer({required BleManager bleManager}) : _bleManager = bleManager;

  void writeWAVState(int state, int size, String name) {
    ByteData data = ByteData(2 + name.length);
    data.setUint8(0, state);
    data.setUint8(1, size);

    List<int> nameBytes = utf8.encode(name);
    for (var i = 0; i < nameBytes.length; i++) {
      data.setUint8(2 + i, nameBytes[i]);
    }

    _bleManager.write(
        serviceId: WAVPlayServiceUuid,
        characteristicId: WAVPlayCharacteristic,
        value: data.buffer.asUint8List());
  }
}
