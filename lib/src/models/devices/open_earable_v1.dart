import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:open_earable_flutter/open_earable_flutter.dart';

import '../../managers/open_earable_sensor_manager.dart';
import '../../utils/simple_kalman.dart';
import '../capabilities/device_firmware_version.dart';

const String _ledSetStateCharacteristic =
    "81040e7a-4819-11ee-be56-0242ac120002";

const String _deviceIdentifierCharacteristicUuid =
    "45622511-6468-465a-b141-0b9b0f96b468";
const String _deviceFirmwareVersionCharacteristicUuid =
    "45622513-6468-465a-b141-0b9b0f96b468";
const String _deviceHardwareVersionCharacteristicUuid =
    "45622512-6468-465a-b141-0b9b0f96b468";

const String _audioSourceCharacteristic =
    "566916a8-476d-11ee-be56-0242ac120002";
const String _audioStateCharacteristic = "566916a9-476d-11ee-be56-0242ac120002";

const String _batteryLevelCharacteristicUuid = "2A19";

class OpenEarableV1 extends Wearable
    with DeviceFirmwareVersionNumberExt
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
        StoragePathAudioPlayer,
        BatteryLevelStatus {
  static const String ledServiceUuid = "81040a2e-4819-11ee-be56-0242ac120002";
  static const String deviceInfoServiceUuid =
      "45622510-6468-465a-b141-0b9b0f96b468";
  static const String audioPlayerServiceUuid =
      "5669146e-476d-11ee-be56-0242ac120002";
  static const String sensorServiceUuid =
      "34c2e3bb-34aa-11eb-adc1-0242ac120002";
  static const String parseInfoServiceUuid =
      "caa25cb7-7e1b-44f2-adc9-e8c06c9ced43";
  static const String buttonServiceUuid =
      "29c10bdc-4773-11ee-be56-0242ac120002";
  static const String batteryServiceUuid = "180F";

  final List<Sensor> _sensors;
  final List<SensorConfiguration> _sensorConfigurations;
  final BleGattManager _bleManager;
  final DiscoveredDevice _discoveredDevice;
  final List<WaveType> _supportedFrequencyPlayerWaveTypes;
  final List<Jingle> _supportedJingles;

  @override
  Stream<Map<SensorConfiguration, SensorConfigurationValue>>
      get sensorConfigurationStream => const Stream.empty();

  OpenEarableV1({
    required super.name,
    required super.disconnectNotifier,
    required BleGattManager bleManager,
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
    OpenEarableSensorHandler sensorManager = OpenEarableSensorHandler(
      bleManager: _bleManager,
      deviceId: _discoveredDevice.id,
    );

    final imuSensorConfig = _ImuSensorConfiguration(
      sensorManager: sensorManager,
    );
    _sensorConfigurations.add(imuSensorConfig);

    final barometerSensorConfig = _BarometerSensorConfiguration(
      sensorManager: sensorManager,
    );
    _sensorConfigurations.add(barometerSensorConfig);

    final microphoneSensorConfig = _MicrophoneSensorConfiguration(
      sensorManager: sensorManager,
    );
    _sensorConfigurations.add(microphoneSensorConfig);

    _sensors.add(
      _OpenEarableSensor(
        sensorManager: sensorManager,
        sensorName: 'ACC',
        chartTitle: 'Accelerometer',
        shortChartTitle: 'Acc.',
        axisNames: ['X', 'Y', 'Z'],
        axisUnits: ["m/s\u00B2", "m/s\u00B2", "m/s\u00B2"],
        relatedConfigurations: [imuSensorConfig],
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
        relatedConfigurations: [imuSensorConfig],
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
        relatedConfigurations: [imuSensorConfig],
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
        relatedConfigurations: [barometerSensorConfig],
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
        relatedConfigurations: [barometerSensorConfig],
      ),
    );
  }

  @override
  String? getWearableIconPath({bool darkmode = false}) {
    String basePath =
        'packages/open_earable_flutter/assets/wearable_icons/open_earable_v1';

    if (darkmode) {
      return '$basePath/icon_no_text_white.svg';
    }

    return '$basePath/icon_no_text.svg';
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
      serviceId: ledServiceUuid,
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
      serviceId: deviceInfoServiceUuid,
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
      serviceId: deviceInfoServiceUuid,
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
      serviceId: deviceInfoServiceUuid,
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
      deviceId: _discoveredDevice.id,
      serviceId: audioPlayerServiceUuid,
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
      deviceId: _discoveredDevice.id,
      serviceId: audioPlayerServiceUuid,
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
      deviceId: _discoveredDevice.id,
      serviceId: audioPlayerServiceUuid,
      characteristicId: _audioStateCharacteristic,
      byteData: data,
    );
  }

  @override
  Future<void> pauseAudio() async {
    Uint8List data = Uint8List(1);
    data[0] = 2;
    await _bleManager.write(
      deviceId: _discoveredDevice.id,
      serviceId: audioPlayerServiceUuid,
      characteristicId: _audioStateCharacteristic,
      byteData: data,
    );
  }

  @override
  Future<void> stopAudio() async {
    Uint8List data = Uint8List(1);
    data[0] = 3;
    await _bleManager.write(
      deviceId: _discoveredDevice.id,
      serviceId: audioPlayerServiceUuid,
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
      deviceId: _discoveredDevice.id,
      serviceId: audioPlayerServiceUuid,
      characteristicId: _audioSourceCharacteristic,
      byteData: data,
    );
  }

  @override
  Stream<int> get batteryPercentageStream {
    StreamController<int> controller = StreamController();
    Timer? pollingTimer;

    controller.onCancel = () {
      pollingTimer?.cancel();
    };

    controller.onListen = () {
      pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
        try {
          int batteryPercentage = await readBatteryPercentage();
          controller.add(batteryPercentage);
        } catch (e) {
          controller.addError(e);
        }
      });
    };

    readBatteryPercentage().then(controller.add).catchError((e) {
      logger.e('Error reading battery percentage: $e');
    });

    return controller.stream;
  }

  @override
  Future<int> readBatteryPercentage() async {
    List<int> batteryLevelList = await _bleManager.read(
      deviceId: _discoveredDevice.id,
      serviceId: batteryServiceUuid,
      characteristicId: _batteryLevelCharacteristicUuid,
    );

    logger.t("Battery level bytes: $batteryLevelList");

    if (batteryLevelList.length != 1) {
      throw StateError(
        'Battery level characteristic expected 1 value, but got ${batteryLevelList.length}',
      );
    }

    return batteryLevelList[0];
  }
}

class _OpenEarableSensor extends Sensor<SensorDoubleValue> {
  final List<String> _axisNames;
  final List<String> _axisUnits;
  final OpenEarableSensorHandler _sensorManager;

  _OpenEarableSensor({
    required super.sensorName,
    required super.chartTitle,
    required super.shortChartTitle,
    required List<String> axisNames,
    required List<String> axisUnits,
    required OpenEarableSensorHandler sensorManager,
    required super.relatedConfigurations,
  })  : _axisNames = axisNames,
        _axisUnits = axisUnits,
        _sensorManager = sensorManager;

  @override
  List<String> get axisNames => _axisNames;

  @override
  List<String> get axisUnits => _axisUnits;

  Stream<SensorDoubleValue> _getAccGyroMagStream() {
    StreamController<SensorDoubleValue> streamController = StreamController();

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

    StreamSubscription subscription =
        _sensorManager.subscribeToSensorData(0).listen((data) {
      BigInt timestamp = data["timestamp"];

      SensorDoubleValue sensorValue = SensorDoubleValue(
        values: [
          kalmanX.filtered(data[sensorName]["X"]),
          kalmanY.filtered(data[sensorName]["Y"]),
          kalmanZ.filtered(data[sensorName]["Z"]),
        ],
        timestamp: timestamp,
      );

      streamController.add(sensorValue);
    });

    // Cancel BLE subscription when canceling stream
    streamController.onCancel = () {
      subscription.cancel();
    };

    return streamController.stream;
  }

  Stream<SensorDoubleValue> _createSingleDataSubscription(
    String componentName,
  ) {
    StreamController<SensorDoubleValue> streamController = StreamController();

    StreamSubscription subscription =
        _sensorManager.subscribeToSensorData(1).listen((data) {
      BigInt timestamp = data["timestamp"];

      SensorDoubleValue sensorValue = SensorDoubleValue(
        values: [data[sensorName][componentName]],
        timestamp: timestamp,
      );

      streamController.add(sensorValue);
    });

    // Cancel BLE subscription when canceling stream
    streamController.onCancel = () {
      subscription.cancel();
    };

    return streamController.stream;
  }

  @override
  Stream<SensorDoubleValue> get sensorStream {
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

class _ImuSensorConfiguration extends SensorFrequencyConfiguration {
  final OpenEarableSensorHandler _sensorManager;

  _ImuSensorConfiguration({
    required OpenEarableSensorHandler sensorManager,
  })  : _sensorManager = sensorManager,
        super(
          name: 'IMU',
          values: [
            SensorFrequencyConfigurationValue(frequencyHz: 0),
            SensorFrequencyConfigurationValue(frequencyHz: 10),
            SensorFrequencyConfigurationValue(frequencyHz: 20),
            SensorFrequencyConfigurationValue(frequencyHz: 30),
          ],
          offValue: SensorFrequencyConfigurationValue(frequencyHz: 0),
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

class _BarometerSensorConfiguration extends SensorFrequencyConfiguration {
  final OpenEarableSensorHandler _sensorManager;

  _BarometerSensorConfiguration({
    required OpenEarableSensorHandler sensorManager,
  })  : _sensorManager = sensorManager,
        super(
          name: 'Barometer',
          values: [
            SensorFrequencyConfigurationValue(frequencyHz: 0),
            SensorFrequencyConfigurationValue(frequencyHz: 10),
            SensorFrequencyConfigurationValue(frequencyHz: 20),
            SensorFrequencyConfigurationValue(frequencyHz: 30),
          ],
          offValue: SensorFrequencyConfigurationValue(frequencyHz: 0),
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

class _MicrophoneSensorConfiguration extends SensorFrequencyConfiguration {
  final OpenEarableSensorHandler _sensorManager;

  _MicrophoneSensorConfiguration({
    required OpenEarableSensorHandler sensorManager,
  })  : _sensorManager = sensorManager,
        super(
          name: 'Microphone',
          values: [
            SensorFrequencyConfigurationValue(frequencyHz: 0),
            SensorFrequencyConfigurationValue(frequencyHz: 16000),
            SensorFrequencyConfigurationValue(frequencyHz: 20000),
            SensorFrequencyConfigurationValue(frequencyHz: 25000),
            SensorFrequencyConfigurationValue(frequencyHz: 31250),
            SensorFrequencyConfigurationValue(frequencyHz: 33333),
            SensorFrequencyConfigurationValue(frequencyHz: 40000),
            SensorFrequencyConfigurationValue(frequencyHz: 41667),
            SensorFrequencyConfigurationValue(frequencyHz: 50000),
            SensorFrequencyConfigurationValue(frequencyHz: 62500),
          ],
          offValue: SensorFrequencyConfigurationValue(frequencyHz: 0),
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
