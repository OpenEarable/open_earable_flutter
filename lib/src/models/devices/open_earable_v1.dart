import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../managers/open_earable_sensor_manager.dart';
import '../../utils/simple_kalman.dart';
import '../capabilities/audio_player_controls.dart';
import '../capabilities/device_firmware_version.dart';
import '../capabilities/device_hardware_version.dart';
import '../capabilities/device_identifier.dart';
import '../capabilities/frequency_player.dart';
import '../capabilities/jingle_player.dart';
import '../capabilities/rgb_led.dart';
import '../capabilities/sensor.dart';
import '../capabilities/sensor_configuration.dart';
import '../capabilities/sensor_configuration_manager.dart';
import '../capabilities/sensor_manager.dart';
import '../../managers/ble_manager.dart';
import '../capabilities/storage_path_audio_player.dart';
import 'discovered_device.dart';
import 'wearable.dart';

const String _ledServiceUuid = "81040a2e-4819-11ee-be56-0242ac120002";
const String _ledSetStateCharacteristic =
    "81040e7a-4819-11ee-be56-0242ac120002";

const String _deviceInfoServiceUuid = "45622510-6468-465a-b141-0b9b0f96b468";
const String _deviceIdentifierCharacteristicUuid =
    "45622511-6468-465a-b141-0b9b0f96b468";
const String _deviceFirmwareVersionCharacteristicUuid =
    "45622512-6468-465a-b141-0b9b0f96b468";
const String _deviceHardwareVersionCharacteristicUuid =
    "45622513-6468-465a-b141-0b9b0f96b468";

const String _audioPlayerServiceUuid = "5669146e-476d-11ee-be56-0242ac120002";
const String _audioSourceCharacteristic =
    "566916a8-476d-11ee-be56-0242ac120002";
const String _audioStateCharacteristic = "566916a9-476d-11ee-be56-0242ac120002";

class OpenEarableV1 extends Wearable
    implements
        SensorManager,
        SensorConfigurationManager,
        RgbLed,
        DeviceIdentifier,
        DeviceFirmwareVersion,
        DeviceHardwareVersion,
        FrequencyPlayer,
        JinglePlayer,
        AudioPlayerControls,
        StoragePathAudioPlayer {
  final List<Sensor> _sensors;
  final List<SensorConfiguration> _sensorConfigurations;
  final BleManager _bleManager;
  final DiscoveredDevice _discoveredDevice;
  final List<WaveType> _supportedFrequencyPlayerWaveTypes;
  final List<Jingle> _supportedJingles;

  OpenEarableV1({
    required super.name,
    required super.disconnectNotifier,
    required BleManager bleManager,
    required DiscoveredDevice discoveredDevice,
  })  : _sensors = [],
        _sensorConfigurations = [],
        _bleManager = bleManager,
        _supportedFrequencyPlayerWaveTypes = const [
          WaveType(key: "SINE"),
          WaveType(key: "SQUARE"),
          WaveType(key: "TRIANGLE"),
          WaveType(key: "SAW"),
        ],
        _supportedJingles = const [
          Jingle(key: "IDLE"),
          Jingle(key: "NOTIFICATION"),
          Jingle(key: "SUCCESS"),
          Jingle(key: "ERROR"),
          Jingle(key: "ALARM"),
          Jingle(key: "PING"),
          Jingle(key: "OPEN"),
          Jingle(key: "CLOSE"),
          Jingle(key: "CLICK"),
        ],
        _discoveredDevice = discoveredDevice {
    _initSensors();
  }

  void _initSensors() {
    OpenEarableSensorManager sensorManager = OpenEarableSensorManager(
      bleManager: _bleManager,
      deviceId: _discoveredDevice.id,
    );

    _sensors.add(
      _OpenEarableSensor(
        sensorManager: sensorManager,
        sensorName: 'ACC',
        chartTitle: 'Accelerometer',
        shortChartTitle: 'Acc.',
        axisNames: ['X', 'Y', 'Z'],
        axisUnits: ["m/s\u00B2", "m/s\u00B2", "m/s\u00B2"],
      ),
    );
    _sensors.add(
      _OpenEarableSensor(
        sensorManager: sensorManager,
        sensorName: 'GYRO',
        chartTitle: 'Gyroscope',
        shortChartTitle: 'Gyro.',
        axisNames: ['X', 'Y', 'Z'],
        axisUnits: ["°/s", "°/s", "°/s"],
      ),
    );
    _sensors.add(
      _OpenEarableSensor(
        sensorManager: sensorManager,
        sensorName: 'MAG',
        chartTitle: 'Magnetometer',
        shortChartTitle: 'Magn.',
        axisNames: ['X', 'Y', 'Z'],
        axisUnits: ["µT", "µT", "µT"],
      ),
    );
    _sensors.add(
      _OpenEarableSensor(
        sensorManager: sensorManager,
        sensorName: 'BARO',
        chartTitle: 'Pressure',
        shortChartTitle: 'Press.',
        axisNames: ['Pressure'],
        axisUnits: ["Pa"],
      ),
    );
    _sensors.add(
      _OpenEarableSensor(
        sensorManager: sensorManager,
        sensorName: 'TEMP',
        chartTitle: 'Temperature (Ambient)',
        shortChartTitle: 'Temp. (A.)',
        axisNames: ['Temperature'],
        axisUnits: ["°C"],
      ),
    );

    _sensorConfigurations.add(
      _ImuSensorConfiguration(
        sensorManager: sensorManager,
      ),
    );
    _sensorConfigurations.add(
      _BarometerSensorConfiguration(
        sensorManager: sensorManager,
      ),
    );
    _sensorConfigurations.add(
      _MicrophoneSensorConfiguration(
        sensorManager: sensorManager,
      ),
    );
  }

  @override
  String get deviceId => _discoveredDevice.id;

  @override
  Future<void> writeLedColor({
    required int r,
    required int g,
    required int b,
  }) async {
    // if (!_bleManager.connected) {
    //   Exception("Can't write sensor config. Earable not connected");
    // }
    if (r < 0 || r > 255 || g < 0 || g > 255 || b < 0 || b > 255) {
      throw ArgumentError('The color values must be in range 0-255');
    }
    ByteData data = ByteData(3);
    data.setUint8(0, r);
    data.setUint8(1, g);
    data.setUint8(2, b);
    await _bleManager.write(
      deviceId: _discoveredDevice.id,
      serviceId: _ledServiceUuid,
      characteristicId: _ledSetStateCharacteristic,
      byteData: data.buffer.asUint8List(),
    );
  }

  /// Reads the device identifier from the connected OpenEarable device.
  ///
  /// Returns a `Future` that completes with the device identifier as a `String`.
  @override
  Future<String?> readDeviceIdentifier() async {
    List<int> deviceIdentifierBytes = await _bleManager.read(
      deviceId: _discoveredDevice.id,
      serviceId: _deviceInfoServiceUuid,
      characteristicId: _deviceIdentifierCharacteristicUuid,
    );
    return String.fromCharCodes(deviceIdentifierBytes);
  }

  /// Reads the device firmware version from the connected OpenEarable device.
  ///
  /// Returns a `Future` that completes with the device firmware version as a `String`.
  @override
  Future<String?> readDeviceFirmwareVersion() async {
    List<int> deviceGenerationBytes = await _bleManager.read(
      deviceId: _discoveredDevice.id,
      serviceId: _deviceInfoServiceUuid,
      characteristicId: _deviceFirmwareVersionCharacteristicUuid,
    );
    return String.fromCharCodes(deviceGenerationBytes);
  }

  /// Reads the device hardware version from the connected OpenEarable device.
  ///
  /// Returns a `Future` that completes with the device firmware version as a `String`.
  @override
  Future<String?> readDeviceHardwareVersion() async {
    List<int> hardwareGenerationBytes = await _bleManager.read(
      deviceId: _discoveredDevice.id,
      serviceId: _deviceInfoServiceUuid,
      characteristicId: _deviceHardwareVersionCharacteristicUuid,
    );
    return String.fromCharCodes(hardwareGenerationBytes);
  }

  @override
  Future<void> disconnect() {
    return _bleManager.disconnect(_discoveredDevice.id);
  }

  @override
  List<SensorConfiguration> get sensorConfigurations =>
      List.unmodifiable(_sensorConfigurations);

  @override
  List<Sensor> get sensors => List.unmodifiable(_sensors);

  @override
  List<WaveType> get supportedFrequencyPlayerWaveTypes =>
      List.unmodifiable(_supportedFrequencyPlayerWaveTypes);

  @override
  Future<void> playFrequency(
    WaveType waveType, {
    double frequency = 440.0,
    double loudness = 1,
  }) async {
    if (!supportedFrequencyPlayerWaveTypes.contains(waveType)) {
      throw UnimplementedError();
    }

    final Map<String, int> waveFormMap = {
      'SINE': 0,
      'SQUARE': 1,
      'TRIANGLE': 2,
      'SAW': 3,
    };

    int type = 2;
    var data = Uint8List(10);
    data[0] = type;
    data[1] = waveFormMap[waveType.key]!;

    var freqBytes = Float32List.fromList([frequency]);
    var loudnessBytes = Float32List.fromList([loudness]);
    data.setAll(2, freqBytes.buffer.asUint8List());
    data.setAll(6, loudnessBytes.buffer.asUint8List());

    await _bleManager.write(
      serviceId: _audioPlayerServiceUuid,
      characteristicId: _audioSourceCharacteristic,
      byteData: data,
    );
  }

  @override
  Future<void> playJingle(Jingle jingle) async {
    final Map<String, int> jingleMap = {
      'IDLE': 0,
      'NOTIFICATION': 1,
      'SUCCESS': 2,
      'ERROR': 3,
      'ALARM': 4,
      'PING': 5,
      'OPEN': 6,
      'CLOSE': 7,
      'CLICK': 8,
    };

    int type = 3;
    Uint8List data = Uint8List(2);
    data[0] = type;
    data[1] = jingleMap[jingle.key]!;
    await _bleManager.write(
      serviceId: _audioPlayerServiceUuid,
      characteristicId: _audioSourceCharacteristic,
      byteData: data,
    );
  }

  @override
  List<Jingle> get supportedJingles => List.unmodifiable(_supportedJingles);

  @override
  Future<void> startAudio() async {
    Uint8List data = Uint8List(1);
    data[0] = 1;
    await _bleManager.write(
      serviceId: _audioPlayerServiceUuid,
      characteristicId: _audioStateCharacteristic,
      byteData: data,
    );
  }

  @override
  Future<void> pauseAudio() async {
    Uint8List data = Uint8List(1);
    data[0] = 2;
    await _bleManager.write(
      serviceId: _audioPlayerServiceUuid,
      characteristicId: _audioStateCharacteristic,
      byteData: data,
    );
  }

  @override
  Future<void> stopAudio()async {
    Uint8List data = Uint8List(1);
    data[0] = 3;
    await _bleManager.write(
      serviceId: _audioPlayerServiceUuid,
      characteristicId: _audioStateCharacteristic,
      byteData: data,
    );
  }

  @override
  Future<void> playAudioFromStoragePath(String filepath) async {
    int type = 1;

    List<int> nameBytes = utf8.encode(filepath);
    Uint8List data = Uint8List(2 + nameBytes.length);
    data[0] = type;
    data[1] = nameBytes.length;
    data.setRange(2, 2 + nameBytes.length, nameBytes);

    await _bleManager.write(
      serviceId: _audioPlayerServiceUuid,
      characteristicId: _audioSourceCharacteristic,
      byteData: data,
    );
  }
}

class _OpenEarableSensor extends Sensor {
  final List<String> _axisNames;
  final List<String> _axisUnits;
  final OpenEarableSensorManager _sensorManager;

  StreamSubscription? _dataSubscription;

  _OpenEarableSensor({
    required String sensorName,
    required String chartTitle,
    required String shortChartTitle,
    required List<String> axisNames,
    required List<String> axisUnits,
    required OpenEarableSensorManager sensorManager,
  })  : _axisNames = axisNames,
        _axisUnits = axisUnits,
        _sensorManager = sensorManager,
        super(
          sensorName: sensorName,
          chartTitle: chartTitle,
          shortChartTitle: shortChartTitle,
        );

  @override
  List<String> get axisNames => _axisNames;

  @override
  List<String> get axisUnits => _axisUnits;

  Stream<SensorValue> _getAccGyroMagStream() {
    StreamController<SensorValue> streamController = StreamController();

    final errorMeasure = {"ACC": 5.0, "GYRO": 10.0, "MAG": 25.0};

    SimpleKalman kalmanX = SimpleKalman(
      errorMeasure: errorMeasure[sensorName]!,
      errorEstimate: errorMeasure[sensorName]!,
      q: 0.9,
    );
    SimpleKalman kalmanY = SimpleKalman(
      errorMeasure: errorMeasure[sensorName]!,
      errorEstimate: errorMeasure[sensorName]!,
      q: 0.9,
    );
    SimpleKalman kalmanZ = SimpleKalman(
      errorMeasure: errorMeasure[sensorName]!,
      errorEstimate: errorMeasure[sensorName]!,
      q: 0.9,
    );
    _dataSubscription?.cancel();
    _dataSubscription = _sensorManager.subscribeToSensorData(0).listen((data) {
      int timestamp = data["timestamp"];

      SensorValue sensorValue = SensorValue(
        values: [
          kalmanX.filtered(data[sensorName]["X"]),
          kalmanY.filtered(data[sensorName]["Y"]),
          kalmanZ.filtered(data[sensorName]["Z"]),
        ],
        timestamp: timestamp,
      );

      streamController.add(sensorValue);
    });

    return streamController.stream;
  }

  Stream<SensorValue> _createSingleDataSubscription(String componentName) {
    StreamController<SensorValue> streamController = StreamController();

    _dataSubscription?.cancel();
    _dataSubscription = _sensorManager.subscribeToSensorData(1).listen((data) {
      int timestamp = data["timestamp"];

      SensorValue sensorValue = SensorValue(
        values: [data[sensorName][componentName]],
        timestamp: timestamp,
      );

      streamController.add(sensorValue);
    });

    return streamController.stream;
  }

  @override
  Stream<SensorValue> get sensorStream {
    switch (sensorName) {
      case "ACC":
      case "GYRO":
      case "MAG":
        return _getAccGyroMagStream();
      case "BARO":
        return _createSingleDataSubscription("Pressure");
      case "TEMP":
        return _createSingleDataSubscription("Temperature");
      default:
        throw UnimplementedError();
    }
  }
}

class _ImuSensorConfiguration extends SensorConfiguration {
  final OpenEarableSensorManager _sensorManager;

  _ImuSensorConfiguration({
    required OpenEarableSensorManager sensorManager,
  })  : _sensorManager = sensorManager,
        super(
          name: 'IMU',
          unit: 'Hz',
          values: const [
            SensorConfigurationValue(key: '0'),
            SensorConfigurationValue(key: '10'),
            SensorConfigurationValue(key: '20'),
            SensorConfigurationValue(key: '30'),
          ],
        );

  @override
  void setConfiguration(SensorConfigurationValue configuration) {
    if (!super.values.contains(configuration)) {
      throw UnimplementedError();
    }

    double imuSamplingRate = double.parse(configuration.key);
    OpenEarableSensorConfig imuConfig = OpenEarableSensorConfig(
      sensorId: 0,
      samplingRate: imuSamplingRate,
      latency: 0,
    );

    _sensorManager.writeSensorConfig(imuConfig);
  }
}

class _BarometerSensorConfiguration extends SensorConfiguration {
  final OpenEarableSensorManager _sensorManager;

  _BarometerSensorConfiguration({
    required OpenEarableSensorManager sensorManager,
  })  : _sensorManager = sensorManager,
        super(
          name: 'Barometer',
          unit: 'Hz',
          values: const [
            SensorConfigurationValue(key: '0'),
            SensorConfigurationValue(key: '10'),
            SensorConfigurationValue(key: '20'),
            SensorConfigurationValue(key: '30'),
          ],
        );

  @override
  void setConfiguration(SensorConfigurationValue configuration) {
    if (!super.values.contains(configuration)) {
      throw UnimplementedError();
    }

    double? barometerSamplingRate = double.parse(configuration.key);
    OpenEarableSensorConfig barometerConfig = OpenEarableSensorConfig(
      sensorId: 1,
      samplingRate: barometerSamplingRate,
      latency: 0,
    );

    _sensorManager.writeSensorConfig(barometerConfig);
  }
}

class _MicrophoneSensorConfiguration extends SensorConfiguration {
  final OpenEarableSensorManager _sensorManager;

  _MicrophoneSensorConfiguration({
    required OpenEarableSensorManager sensorManager,
  })  : _sensorManager = sensorManager,
        super(
          name: 'Microphone',
          unit: 'Hz',
          values: const [
            SensorConfigurationValue(key: "0"),
            SensorConfigurationValue(key: "16000"),
            SensorConfigurationValue(key: "20000"),
            SensorConfigurationValue(key: "25000"),
            SensorConfigurationValue(key: "31250"),
            SensorConfigurationValue(key: "33333"),
            SensorConfigurationValue(key: "40000"),
            SensorConfigurationValue(key: "41667"),
            SensorConfigurationValue(key: "50000"),
            SensorConfigurationValue(key: "62500"),
          ],
        );

  @override
  void setConfiguration(SensorConfigurationValue configuration) {
    if (!super.values.contains(configuration)) {
      throw UnimplementedError();
    }

    double? microphoneSamplingRate = double.parse(configuration.key);
    OpenEarableSensorConfig microphoneConfig = OpenEarableSensorConfig(
      sensorId: 2,
      samplingRate: microphoneSamplingRate,
      latency: 0,
    );

    _sensorManager.writeSensorConfig(microphoneConfig);
  }
}
