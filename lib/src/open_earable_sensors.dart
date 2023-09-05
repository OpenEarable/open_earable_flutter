part of open_earable_flutter;

class OpenEarableSensorConfig {
  // Properties
  int sensorId; // 8-bit unsigned integer
  double samplingRate; // 4-byte float
  int latency; // 32-bit unsigned integer

  OpenEarableSensorConfig({
    required this.sensorId,
    required this.samplingRate,
    required this.latency,
  });

  Uint8List get byteList {
    ByteData data = ByteData(9);
    data.setUint8(0, sensorId);
    data.setFloat32(1, samplingRate, Endian.little);
    data.setUint32(5, latency, Endian.little);
    return data.buffer.asUint8List();
  }

  @override
  String toString() {
    return 'OpenEarableSensorConfig(sensorId: $sensorId, sampleRate: $samplingRate, latency: $latency)';
  }
}
