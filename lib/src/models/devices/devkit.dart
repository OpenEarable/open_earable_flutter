import 'dart:async';
import 'dart:typed_data';

import '../../../open_earable_flutter.dart';
import '../../managers/ble_manager.dart';

class DevKit extends Wearable
    implements
        DeviceFirmwareVersion,
        DeviceHardwareVersion,
        AudioPlayerControls,
        BatteryEnergyStatus,
        BatteryHealthStatus,
        BatteryLevelStatus,
        DeviceIdentifier,
        FrequencyPlayer,
        JinglePlayer,
        RgbLed,
        SensorConfigurationManager,
        SensorConfiguration,
        SensorManager,
        Sensor,
        StatusLed,
        StoragePathAudioPlayer {
  final BleManager _bleManager;
  final DiscoveredDevice _discoveredDevice;

  DevKit({
    required super.name,
    required super.disconnectNotifier,
    required BleManager bleManager,
    required DiscoveredDevice discoveredDevice,
  })  : _bleManager = bleManager,
        _discoveredDevice = discoveredDevice;

  @override
  String get deviceId => _discoveredDevice.id;

  @override
  Future<void> disconnect() {
    return _bleManager.disconnect(_discoveredDevice.id);
  }

  @override
  Future<String?> readDeviceFirmwareVersion() {
    return Future(() => "not available");
  }

  @override
  Future<String?> readDeviceHardwareVersion() {
    return Future(() => "not available");
  }

  @override
  double get availableCapacity => throw UnimplementedError();

  @override
  int get axisCount => throw UnimplementedError();

  @override
  List<String> get axisNames => throw UnimplementedError();

  @override
  List<String> get axisUnits => throw UnimplementedError();

  @override
  Stream<int> get batteryPercentageStream => throw UnimplementedError();

  @override
  double get chargeRate => throw UnimplementedError();

  @override
  String get chartTitle => throw UnimplementedError();

  @override
  int get currentTemperature => throw UnimplementedError();

  @override
  int get cycleCount => throw UnimplementedError();

  @override
  int get healthSummary => throw UnimplementedError();

  @override
  Future<void> pauseAudio() {
    throw UnimplementedError();
  }

  @override
  Future<void> playAudioFromStoragePath(String filepath) {
    throw UnimplementedError();
  }

  @override
  Future<void> playFrequency(WaveType waveType,
      {double frequency = 440.0, double loudness = 1}) {
    return Future.value();
  }

  @override
  Future<void> playJingle(Jingle jingle) {
    return Future.value();
  }

  @override
  Future<int> readBatteryPercentage() {
    return Future.value(100);
  }

  @override
  Future<String?> readDeviceIdentifier() {
    return Future.value("not available");
  }

  @override
  // TODO: implement relatedConfigurations
  List<SensorConfiguration<SensorConfigurationValue>>
      get relatedConfigurations {
    return [];
  }

  @override
  // TODO: implement sensorConfigurations
  List<SensorConfiguration<SensorConfigurationValue>> get sensorConfigurations {
    return [];
  }

  @override
  // TODO: implement sensorName
  String get sensorName {
    return "not implemented";
  }

  @override
  // TODO: implement sensorStream
  Stream<SensorValue> get sensorStream {
    return const Stream.empty();
  }

  @override
  List<Sensor<SensorValue>> get sensors {
    return [
      HeartRateVariabilitySensor(rrIntervalsMsStream: const Stream.empty()),
    ];
  }

  @override
  void setConfiguration(SensorConfigurationValue configuration) {}

  @override
  String get shortChartTitle {
    return "not implemented";
  }

  @override
  Future<void> showStatus(bool status) {
    return Future.value();
  }

  @override
  Future<void> startAudio() {
    return Future.value();
  }

  @override
  Future<void> stopAudio() {
    return Future.value();
  }

  @override
  List<WaveType> get supportedFrequencyPlayerWaveTypes {
    return [const WaveType(key: "SINE")];
  }

  @override
  List<Jingle> get supportedJingles {
    return [const Jingle(key: "IDLE")];
  }

  @override
  int get timestampExponent {
    return 0;
  }

  @override
  String? get unit {
    return "not implemented";
  }

  @override
  List<SensorConfigurationValue> get values {
    return [SensorConfigurationValue(key: "key")];
  }

  @override
  double get voltage {
    return 0.0;
  }

  @override
  Future<void> writeLedColor({required int r, required int g, required int b}) {
    return Future.value();
  }
}
