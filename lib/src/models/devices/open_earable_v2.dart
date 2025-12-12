import 'dart:async';
import 'dart:typed_data';

import 'package:open_earable_flutter/src/constants.dart';
import 'package:open_earable_flutter/src/models/devices/bluetooth_wearable.dart';
import 'package:pub_semver/pub_semver.dart';

import '../../../open_earable_flutter.dart' hide Version;
import '../../managers/v2_sensor_handler.dart';
import '../capabilities/device_firmware_version.dart';
import '../capabilities/sensor_configuration_specializations/sensor_configuration_open_earable_v2.dart';
import 'battery_gatt_reader/battery_energy_status_gatt_reader.dart';
import 'battery_gatt_reader/battery_health_status_gatt_reader.dart';
import 'battery_gatt_reader/battery_level_status_gatt_reader.dart';
import 'battery_gatt_reader/battery_level_status_service_gatt_reader.dart';

const String _ledSetColorCharacteristic =
    "81040e7a-4819-11ee-be56-0242ac120002";
const String _ledSetStateCharacteristic =
    "81040e7b-4819-11ee-be56-0242ac120002";

const String _deviceIdentifierCharacteristicUuid =
    "45622511-6468-465a-b141-0b9b0f96b468";
const String _deviceFirmwareVersionCharacteristicUuid =
    "45622513-6468-465a-b141-0b9b0f96b468";
const String _deviceHardwareVersionCharacteristicUuid =
    "45622512-6468-465a-b141-0b9b0f96b468";

const String _audioConfigServiceUuid = "1410df95-5f68-4ebb-a7c7-5e0fb9ae7557";
const String _micSelectCharacteristicUuid =
    "0x1410df97-5f68-4ebb-a7c7-5e0fb9ae7557";
const String _audioModeCharacteristicUuid =
    "0x1410df96-5f68-4ebb-a7c7-5e0fb9ae7557";

const String _buttonServiceUuid = "29c10bdc-4773-11ee-be56-0242ac120002";
const String _buttonCharacteristicUuid = "29c10f38-4773-11ee-be56-0242ac120002";

const String timeSynchronizationServiceUuid = "2e04cbf7-939d-4be5-823e-271838b75259";
const String _timeSyncTimeMappingCharacteristicUuid =
    "2e04cbf8-939d-4be5-823e-271838b75259";
const String _timeSyncRttCharacteristicUuid =
    "2e04cbf9-939d-4be5-823e-271838b75259";

const String _audioResponseServiceUuid = "12345678-1234-5678-9abc-def123456789";
const String _audioResponseControlCharacteristicUuid = "12345679-1234-5678-9abc-def123456789";
const String _audioResponseDataCharacteristicUuid = "1234567a-1234-5678-9abc-def123456789";

final VersionConstraint _versionConstraint =
    VersionConstraint.parse(">=2.1.0 <2.3.0");

// MARK: OpenEarableV2

/// Represents the OpenEarable V2 device.
/// This class implements various interfaces to provide functionality
/// such as sensor management, LED control, battery status, and device information.
/// It extends the Wearable class and implements several interfaces
/// to provide a comprehensive set of features for the OpenEarable V2 device.
/// The class is designed to be used with the OpenEarable Flutter SDK.
/// It provides methods to read and write data to the device,
/// manage sensors, control LEDs, and retrieve battery and device information.
/// The class also provides streams for monitoring battery and power status,
/// as well as health and energy status.
class OpenEarableV2 extends BluetoothWearable
    with
      DeviceFirmwareVersionNumberExt,
      BatteryLevelStatusGattReader,
      BatteryLevelStatusServiceGattReader,
      BatteryHealthStatusGattReader,
      BatteryEnergyStatusGattReader
    implements
        SensorManager,
        SensorConfigurationManager,
        RgbLed,
        StatusLed,
        BatteryEnergyStatusService,
        DeviceIdentifier,
        DeviceFirmwareVersion,
        DeviceHardwareVersion,
        MicrophoneManager<OpenEarableV2Mic>,
        AudioModeManager,
        EdgeRecorderManager,
        ButtonManager,
        StereoDevice,
        SystemDevice,
        AudioResponseManager {
  static const String deviceInfoServiceUuid =
      "45622510-6468-465a-b141-0b9b0f96b468";
  static const String ledServiceUuid = "81040a2e-4819-11ee-be56-0242ac120002";
  static const String batteryServiceUuid = "180F";

  final List<Sensor> _sensors;
  final List<SensorConfiguration> _sensorConfigurations;

  final bool _isConnectedViaSystem;
  @override
  bool get isConnectedViaSystem => _isConnectedViaSystem;

  @override
  Stream<Map<SensorConfiguration, SensorConfigurationValue>>
      get sensorConfigurationStream {
    StreamController<Map<SensorConfiguration, SensorConfigurationValue>>
        controller =
        StreamController<Map<SensorConfiguration, SensorConfigurationValue>>();

    _sensorConfigSubscription?.cancel();

    _sensorConfigSubscription = bleManager
        .subscribe(
      deviceId: deviceId,
      serviceId: sensorServiceUuid,
      characteristicId: sensorConfigStateCharacteristicUuid,
    )
        .listen(
      (data) {
        controller.add(_parseConfigMap(data));
      },
      onError: (error) {
        logger.e('Error in sensor configuration stream: $error');
        controller.addError(error);
      },
    );

    controller.onCancel = () {
      _sensorConfigSubscription?.cancel();
      _sensorConfigSubscription = null;
    };

    controller.onListen = () {
      // Immediately read the current sensor configuration
      bleManager
          .read(
        deviceId: deviceId,
        serviceId: sensorServiceUuid,
        characteristicId: sensorConfigStateCharacteristicUuid,
      )
          .then((data) {
        controller.add(_parseConfigMap(data));
      }).catchError((error) {
        logger.e('Error reading initial sensor configuration: $error');
        controller.addError(error);
      });
    };
    return controller.stream;
  }

  Map<SensorConfiguration, SensorConfigurationValue> _parseConfigMap(
    List<int> data,
  ) {
    List<V2SensorConfig> sensorConfigs =
        V2SensorConfig.listFromBytes(Uint8List.fromList(data));
    logger.d('Received sensor configuration data: $sensorConfigs');

    Map<SensorConfiguration, SensorConfigurationValue> sensorConfigMap = {};

    for (V2SensorConfig sensorConfig in sensorConfigs) {
      // Find the matching sensor configuration
      SensorConfiguration? matchingConfig = _sensorConfigurations.where(
        (config) {
          if (config is SensorConfigurationOpenEarableV2) {
            return config.sensorId == sensorConfig.sensorId;
          }
          return false;
        },
      ).firstOrNull;

      if (matchingConfig == null) {
        logger.w(
          'No matching sensor configuration found for ID: ${sensorConfig.sensorId}',
        );
        continue;
      }

      SensorConfigurationValue? sensorConfigValue = matchingConfig.values.where(
        (value) {
          if (value is SensorConfigurationOpenEarableV2Value) {
            return value.frequencyIndex == sensorConfig.sampleRateIndex &&
                value.streamData == sensorConfig.streamData &&
                value.recordData == sensorConfig.storeData;
          }
          return false;
        },
      ).firstOrNull;

      if (sensorConfigValue == null) {
        logger.w(
          'No matching sensor configuration value found for sensor ID: ${sensorConfig.sensorId}',
        );
        continue;
      }
      sensorConfigMap[matchingConfig] = sensorConfigValue;
    }

    return sensorConfigMap;
  }

  StreamSubscription? _sensorConfigSubscription;
  StreamSubscription? _buttonSubscription;


  @override
  final Set<OpenEarableV2Mic> availableMicrophones;
  @override
  final Set<AudioMode> availableAudioModes;

  @override
  Future<String> get filePrefix async {
    List<int> prefixBytes = await bleManager.read(
      deviceId: deviceId,
      serviceId: sensorServiceUuid,
      characteristicId: sensorEdgeRecorderFilePrefixCharacteristicUuid,
    );
    return String.fromCharCodes(prefixBytes);
  }

  @override
  Stream<ButtonEvent> get buttonEvents {
    StreamController<ButtonEvent> controller = StreamController<ButtonEvent>();

    _buttonSubscription?.cancel();

    _buttonSubscription = bleManager
        .subscribe(
      deviceId: deviceId,
      serviceId: _buttonServiceUuid,
      characteristicId: _buttonCharacteristicUuid,
    )
        .listen(
      (data) {
        if (data.isNotEmpty) {
          int buttonState = data[0];
          if (buttonState == 0) {
            controller.add(ButtonEvent.released);
          } else if (buttonState == 1) {
            controller.add(ButtonEvent.pressed);
          }
        }
      },
      onError: (error) {
        logger.e('Error in button events stream: $error');
        controller.addError(error);
      },
    );

    controller.onCancel = () {
      _buttonSubscription?.cancel();
      _buttonSubscription = null;
    };

    controller.onListen = () {
      // Immediately read current button state
      bleManager
          .read(
        deviceId: deviceId,
        serviceId: _buttonServiceUuid,
        characteristicId: _buttonCharacteristicUuid,
      )
          .then((data) {
        if (data.isNotEmpty) {
          int buttonState = data[0];
          if (buttonState == 0) {
            controller.add(ButtonEvent.released);
          } else if (buttonState == 1) {
            controller.add(ButtonEvent.pressed);
          }
        }
      }).catchError((error) {
        logger.e('Error reading initial button state: $error');
        controller.addError(error);
      });
    };

    return controller.stream;
  }

  OpenEarableV2({
    required super.name,
    required super.disconnectNotifier,
    required List<Sensor> sensors,
    required List<SensorConfiguration> sensorConfigurations,
    required super.bleManager,
    required super.discoveredDevice,
    this.availableMicrophones = const {},
    this.availableAudioModes = const {},
    bool isConnectedViaSystem = false,
  })  : _sensors = sensors,
        _sensorConfigurations = sensorConfigurations,
        _isConnectedViaSystem = isConnectedViaSystem;

  @override
  String get deviceId => discoveredDevice.id;

  @override
  String? getWearableIconPath({bool darkmode = false}) {
    String basePath =
        'packages/open_earable_flutter/assets/wearable_icons/open_earable_v2';

    if (darkmode) {
      return '$basePath/icon_no_text_white.svg';
    }

    return '$basePath/icon_no_text.svg';
  }

  @override
  Future<void> writeLedColor({
    required int r,
    required int g,
    required int b,
  }) async {
    if (r < 0 || r > 255 || g < 0 || g > 255 || b < 0 || b > 255) {
      throw ArgumentError('The color values must be in range 0-255');
    }
    ByteData data = ByteData(3);
    data.setUint8(0, r);
    data.setUint8(1, g);
    data.setUint8(2, b);
    await bleManager.write(
      deviceId: discoveredDevice.id,
      serviceId: ledServiceUuid,
      characteristicId: _ledSetColorCharacteristic,
      byteData: data.buffer.asUint8List(),
    );
  }

  @override
  Future<void> showStatus(bool status) async {
    ByteData statusData = ByteData(1);
    statusData.setUint8(0, status ? 0 : 1);
    await bleManager.write(
      deviceId: discoveredDevice.id,
      serviceId: ledServiceUuid,
      characteristicId: _ledSetStateCharacteristic,
      byteData: statusData.buffer.asUint8List(),
    );
  }

  // MARK: DeviceIdentifier / DeviceFirmwareVersion / DeviceHardwareVersion

  /// Reads the device identifier from the connected OpenEarable device.
  ///
  /// Returns a `Future` that completes with the device identifier as a `String`.
  @override
  Future<String?> readDeviceIdentifier() async {
    List<int> deviceIdentifierBytes = await bleManager.read(
      deviceId: discoveredDevice.id,
      serviceId: deviceInfoServiceUuid,
      characteristicId: _deviceIdentifierCharacteristicUuid,
    );
    int nullIndex = deviceIdentifierBytes.indexOf(0);
    if (nullIndex != -1) {
      deviceIdentifierBytes = deviceIdentifierBytes.sublist(0, nullIndex);
    }
    return String.fromCharCodes(deviceIdentifierBytes);
  }

  /// Reads the device firmware version from the connected OpenEarable device.
  ///
  /// Returns a `Future` that completes with the device firmware version as a `String`.
  @override
  Future<String?> readDeviceFirmwareVersion() async {
    List<int> deviceGenerationBytes = await bleManager.read(
      deviceId: discoveredDevice.id,
      serviceId: deviceInfoServiceUuid,
      characteristicId: _deviceFirmwareVersionCharacteristicUuid,
    );
    int nullIndex = deviceGenerationBytes.indexOf(0);
    if (nullIndex != -1) {
      deviceGenerationBytes = deviceGenerationBytes.sublist(0, nullIndex);
    }
    return String.fromCharCodes(deviceGenerationBytes);
  }

  @override
  VersionConstraint get supportedFirmwareRange => _versionConstraint;

  /// Reads the device hardware version from the connected OpenEarable device.
  ///
  /// Returns a `Future` that completes with the device firmware version as a `String`.
  @override
  Future<String?> readDeviceHardwareVersion() async {
    List<int> hardwareGenerationBytes = await bleManager.read(
      deviceId: discoveredDevice.id,
      serviceId: deviceInfoServiceUuid,
      characteristicId: _deviceHardwareVersionCharacteristicUuid,
    );
    int nullIndex = hardwareGenerationBytes.indexOf(0);
    if (nullIndex != -1) {
      hardwareGenerationBytes = hardwareGenerationBytes.sublist(0, nullIndex);
    }
    return String.fromCharCodes(hardwareGenerationBytes);
  }

  // MARK: SensorManager / SensorConfigurationManager

  @override
  Future<void> disconnect() {
    return bleManager.disconnect(discoveredDevice.id);
  }

  @override
  List<SensorConfiguration> get sensorConfigurations =>
      List.unmodifiable(_sensorConfigurations);

  @override
  List<Sensor> get sensors => List.unmodifiable(_sensors);

  // MARK: MicrophoneManager

  @override
  void setMicrophone(OpenEarableV2Mic microphone) {
    if (!availableMicrophones.contains(microphone)) {
      throw ArgumentError('Microphone not available: ${microphone.key}');
    }

    bleManager.write(
      deviceId: deviceId,
      serviceId: _audioConfigServiceUuid,
      characteristicId: _micSelectCharacteristicUuid,
      byteData: [microphone.id],
    );
  }

  @override
  Future<OpenEarableV2Mic> getMicrophone() async {
    List<int> microphoneBytes = await bleManager.read(
      deviceId: deviceId,
      serviceId: _audioConfigServiceUuid,
      characteristicId: _micSelectCharacteristicUuid,
    );

    if (microphoneBytes.length != 1) {
      throw StateError(
        'Microphone characteristic expected 1 value, but got ${microphoneBytes.length}',
      );
    }

    int microphoneId = microphoneBytes[0];
    return availableMicrophones.firstWhere((mic) => mic.id == microphoneId);
  }

  // MARK: AudioModeManager

  @override
  void setAudioMode(AudioMode audioMode) {
    if (!availableAudioModes.contains(audioMode)) {
      throw ArgumentError('Audio mode not available: ${audioMode.key}');
    }

    bleManager.write(
      deviceId: deviceId,
      serviceId: _audioConfigServiceUuid,
      characteristicId: _audioModeCharacteristicUuid,
      byteData: [audioMode.id],
    );
  }

  @override
  Future<AudioMode> getAudioMode() async {
    List<int> audioModeBytes = await bleManager.read(
      deviceId: deviceId,
      serviceId: _audioConfigServiceUuid,
      characteristicId: _audioModeCharacteristicUuid,
    );

    if (audioModeBytes.length != 1) {
      throw StateError(
        'Audio mode characteristic expected 1 value, but got ${audioModeBytes.length}',
      );
    }

    int audioModeId = audioModeBytes[0];
    return availableAudioModes.firstWhere((mode) => mode.id == audioModeId);
  }

  // MARK: EdgeRecorderManager

  @override
  Future<void> setFilePrefix(String prefix) {
    return bleManager.write(
      deviceId: deviceId,
      serviceId: sensorServiceUuid,
      characteristicId: sensorEdgeRecorderFilePrefixCharacteristicUuid,
      byteData: prefix.codeUnits,
    );
  }

  // MARK: StereoDevice

  @override
  Future<DevicePosition?> get position async {
    List<int> positionBytes;
    try {
      positionBytes = await bleManager.read(
        deviceId: deviceId,
        serviceId: "1410df95-5f68-4ebb-a7c7-5e0fb9ae7557",
        characteristicId: "1410df98-5f68-4ebb-a7c7-5e0fb9ae7557",
      );
    } catch (e) {
      logger.w("Failed to read position characteristic: $e");
      return _determinePositionFromName(name);
    }

    if (positionBytes.length != 1) {
      logger.e("Expected 1 byte for position, but got ${positionBytes.length}");
      return null;
    }

    return switch (positionBytes[0]) {
      0 => DevicePosition.left,
      1 => DevicePosition.right,
      _ => null,
    };
  }

  DevicePosition? _determinePositionFromName(String name) {
    if (name.endsWith('-L')) {
      return DevicePosition.left;
    } else if (name.endsWith('-R')) {
      return DevicePosition.right;
    }
    return null;
  }

  StereoDevice? _pairedDevice;

  @override
  Future<StereoDevice?> get pairedDevice async {
    return _pairedDevice;
  }

  @override
  Future<void> pair(StereoDevice device) async {
    if (device == await pairedDevice) return;
    _pairedDevice = device;
    _pairedDevice!.pair(this);
  }

  @override
  Future<void> unpair() async {
    if (await pairedDevice == null) return;
    _pairedDevice?.unpair();
    _pairedDevice = null;
  }

  // MARK: AudioResponseManager

  void _triggerAudioResponseMeasurement() {
    bleManager.write(
      deviceId: deviceId,
      serviceId: _audioResponseServiceUuid,
      characteristicId: _audioResponseControlCharacteristicUuid,
      byteData: [0xFF], // Command to start audio response measurement
    );
  }

  Future<Map<String, dynamic>> _parseAudioResponseData(Uint8List data) async {
    if (data.isEmpty) {
      throw StateError('Audio response data is empty');
    }

    // New v1 payload size:
    // 1 (version) + 1 (quality) + 1 (mean_magnitude) + 1 (num_peaks)
    // + 9*2 (frequencies) + 9*2 (magnitudes) = 40 bytes
    const int expectedLenV1 = 40;

    if (data.length < expectedLenV1) {
      throw StateError(
        'Audio response data too short: ${data.length} bytes (expected $expectedLenV1)',
      );
    }

    final int version = data[0];
    if (version != 1) {
      throw StateError('Unsupported audio response data version: $version');
    }

    if (data.length != expectedLenV1) {
      throw StateError(
        'Unexpected audio response data length for version 1: ${data.length} bytes (expected $expectedLenV1)',
      );
    }

    final int quality = data[1];
    final int meanMagnitude = data[2];
    final int numPeaks = data[3];

    // Frequencies: 9 * uint16_t (12.4 fixed point) starting at offset 4
    // NOTE: Endianness: this uses big-endian to match your previous implementation.
    // If firmware sends little-endian, swap the byte order.
    const int freqBase = 4;
    final List<int> frequenciesRaw = List<int>.filled(9, 0);
    final List<double> frequenciesHz = List<double>.filled(9, 0);
    for (int i = 0; i < 9; i++) {
      final int off = freqBase + i * 2;
      final int raw = (data[off + 1] << 8) | data[off];
      frequenciesRaw[i] = raw;
      frequenciesHz[i] = raw / 16.0; // 12.4 fixed point -> Hz
    }

    // Magnitudes: 9 * uint16_t starting at offset 4 + 18 = 22
    const int magBase = freqBase + 9 * 2; // 22
    final List<int> magnitudes = List<int>.filled(9, 0);
    for (int i = 0; i < 9; i++) {
      final int off = magBase + i * 2;
      final int mag = (data[off + 1] << 8) | data[off];
      magnitudes[i] = mag;
    }

    final List<Map<String, dynamic>> points = List.generate(9, (i) {
      return {
        'frequency_hz': frequenciesHz[i],
        'frequency_raw_q12_4': frequenciesRaw[i],
        'magnitude': magnitudes[i],
      };
    });

    return {
      'version': version,
      'quality': quality,
      'mean_magnitude': meanMagnitude,
      'num_peaks': numPeaks,
      'frequencies_hz': frequenciesHz,
      'frequencies_raw_q12_4': frequenciesRaw,
      'magnitudes': magnitudes,
      'points': points,
    };
  }

  @override
  Future<Map<String, dynamic>> measureAudioResponse(Map<String, dynamic> parameters) async {
    _triggerAudioResponseMeasurement();

    // Wait for the result via notification
    final completer = Completer<Map<String, dynamic>>();

    late final StreamSubscription<List<int>> audioRespSub;
    audioRespSub = bleManager
        .subscribe(
          deviceId: deviceId,
          serviceId: _audioResponseServiceUuid,
          characteristicId: _audioResponseDataCharacteristicUuid,
        )
        .listen(
      (data) async {
        logger.d("Received audio response data: $data");
        try {
          final parsed = await _parseAudioResponseData(Uint8List.fromList(data));
          if (!completer.isCompleted) {
            completer.complete(parsed);
          }
        } catch (e, stack) {
          logger.e("Error parsing audio response data: $e, $stack");
          if (!completer.isCompleted) {
            completer.completeError(e, stack);
          }
        } finally {
          await audioRespSub.cancel();
        }
      },
      onError: (error, stack) async {
        logger.e("Error during audio response subscription: $error, $stack");
        if (!completer.isCompleted) {
          completer.completeError(error, stack);
        }
      },
    );

    return completer.future;
  }
}

// MARK: OpenEarableV2Mic

class OpenEarableV2Mic extends Microphone {
  final int id;

  const OpenEarableV2Mic({
    required this.id,
    required super.key,
  });
}

class OpenEarableV2PairingRule extends PairingRule<OpenEarableV2> {
  @override
  Future<bool> isValidPair(OpenEarableV2 left, OpenEarableV2 right) async {
    // Example rule: both devices must be OpenEarable V2 and have different positions
    DevicePosition? leftPosition = await left.position;
    DevicePosition? rightPosition = await right.position;
    if (leftPosition == null || rightPosition == null) {
      return false;
    }
    if (leftPosition == rightPosition) {
      return false;
    }

    return left.name == right.name;
  }
}

// MARK: OpenEarable Sync Time packet

enum _TimeSyncOperation {
  request(0x00),
  response(0x01);

  final int value;
  const _TimeSyncOperation(this.value);
}

class _SyncTimePacket {
  final int version;
  final _TimeSyncOperation op;
  final int seq;
  final int timePhoneSend;
  final int timeDeviceReceive;
  final int timeDeviceSend;

  factory _SyncTimePacket.fromBytes(Uint8List bytes) {
    if (bytes.length < 15) {
      throw ArgumentError.value(
        bytes,
        'bytes',
        'Byte array too short to be a valid SyncTimePacket',
      );
    }

    ByteData bd = ByteData.sublistView(bytes);
    int version = bd.getUint8(0);
    _TimeSyncOperation op =
        _TimeSyncOperation.values.firstWhere((e) => e.value == bd.getUint8(1));
    int seq = bd.getUint16(2, Endian.little);
    int timePhoneSend = bd.getUint64(4, Endian.little);
    int timeDeviceReceive = bd.getUint64(12, Endian.little);
    int timeDeviceSend = bd.getUint64(20, Endian.little);

    return _SyncTimePacket(
      version: version,
      op: op,
      seq: seq,
      timePhoneSend: timePhoneSend,
      timeDeviceReceive: timeDeviceReceive,
      timeDeviceSend: timeDeviceSend,
    );
  }

  const _SyncTimePacket({
    required this.version,
    required this.op,
    required this.seq,
    required this.timePhoneSend,
    required this.timeDeviceReceive,
    required this.timeDeviceSend,
  });

  /// Serialize packet to bytes.
  /// Layout (little-endian):
  /// [0]    : version (1 byte)
  /// [1]    : operation (1 byte)
  /// [2]    : sequence (2 byte)
  /// [3..6] : timePhoneSend (uint64)
  /// [7..10]: timeDeviceReceive (uint64)
  /// [11..14]: timeDeviceSend (uint64)
  Uint8List toBytes() {
    if (seq < 0 || seq > 0xFFFF) {
      throw ArgumentError.value(seq, 'seq', 'Must fit in two bytes (0..65535)');
    }

    final ByteData bd = ByteData(28);
    bd.setUint8(0, version);
    bd.setUint8(1, op.value);
    bd.setUint16(2, seq, Endian.little);
    bd.setUint64(4, timePhoneSend, Endian.little);
    bd.setUint64(12, timeDeviceReceive, Endian.little);
    bd.setUint64(20, timeDeviceSend, Endian.little);
    return bd.buffer.asUint8List();
  }

  @override
  String toString() {
    return '_SyncTimePacket(version: $version, op: $op, seq: $seq, timePhoneSend: $timePhoneSend, timeDeviceReceive: $timeDeviceReceive, timeDeviceSend: $timeDeviceSend)';
  }
}

// MARK: TimeSynchronizable

class OpenEarableV2TimeSyncImp implements TimeSynchronizable {
  final BleGattManager bleManager;
  final String deviceId;

  OpenEarableV2TimeSyncImp({
    required this.bleManager,
    required this.deviceId,
  });

  @override
  bool get isTimeSynchronized {
    // Placeholder implementation
    return true;
  }

  /// How many RTT samples to collect before computing the median offset.
  static const int _timeSyncSampleCount = 7;

  @override
  Future<void> synchronizeTime() async {
    logger.i("Synchronizing time with OpenEarable V2 device...");

    // Will complete when we have enough samples and wrote the final offset.
    final completer = Completer<void>();

    // Collected offset estimates (µs).
    final offsets = <int>[];

    // Subscribe to RTT responses
    late final StreamSubscription<List<int>> rttSub;
    rttSub = bleManager
        .subscribe(
          deviceId: deviceId,
          serviceId: timeSynchronizationServiceUuid,
          characteristicId: _timeSyncRttCharacteristicUuid,
        )
        .listen(
      (data) async {
        final t4 = DateTime.now().microsecondsSinceEpoch;
        final pkt = _SyncTimePacket.fromBytes(Uint8List.fromList(data));

        if (pkt.op != _TimeSyncOperation.response) {
          return; // ignore anything that's not a response
        }

        logger.d("Received time sync response packet: $pkt");

        final t1 = pkt.timePhoneSend;   // phone send timestamp (µs)
        final t3 = pkt.timeDeviceSend;  // device send timestamp (µs, device clock)

        // Estimate Unix time at the moment the device sent the response.
        // Use midpoint between T1 and T4 as an estimate of when the device was "in the middle".
        final unixAtT3 = t1 + ((t4 - t1) ~/ 2);

        // offset = unix_time - device_time
        final offset = unixAtT3 - t3;
        offsets.add(offset);

        logger.i("Time sync sample #${offsets.length}: offset=$offset µs");

        if (offsets.length >= _timeSyncSampleCount && !completer.isCompleted) {
          await rttSub.cancel();

          final medianOffset = _computeMedian(offsets);
          logger.i(
            "Collected ${offsets.length} samples. Median offset: $medianOffset µs",
          );

          // Convert to bytes (signed int64, little endian)
          final offsetBytes = ByteData(8)
            ..setInt64(0, medianOffset, Endian.little);

          // Write the final median offset to the device
          await bleManager.write(
            deviceId: deviceId,
            serviceId: timeSynchronizationServiceUuid,
            characteristicId: _timeSyncTimeMappingCharacteristicUuid,
            byteData: offsetBytes.buffer.asUint8List(),
          );

          logger.i("Median offset written to device. Time sync complete.");

          completer.complete();
        }
      },
      onError: (error, stack) async {
        logger.e("Error during time sync subscription $error, $stack",);
        if (!completer.isCompleted) {
          completer.completeError(error, stack);
        }
      },
    );

    // Send multiple RTT requests.
    // Each request carries its own send timestamp (T1) inside the packet.
    for (var i = 0; i < _timeSyncSampleCount; i++) {
      final t1 = DateTime.now().microsecondsSinceEpoch;

      final request = _SyncTimePacket(
        version: 1,
        op: _TimeSyncOperation.request,
        seq: i, // optional: use i to correlate if you want
        timePhoneSend: t1,
        timeDeviceReceive: 0,
        timeDeviceSend: 0,
      );

      logger.d("Sending time sync request seq=$i, t1=$t1");

      await bleManager.write(
        deviceId: deviceId,
        serviceId: timeSynchronizationServiceUuid,
        characteristicId: _timeSyncRttCharacteristicUuid,
        byteData: request.toBytes(),
      );

      // Short delay between requests to avoid overloading BLE
      await Future.delayed(const Duration(milliseconds: 50));
    }

    // Wait until enough responses arrive and median is written
    await completer.future;
  }

  /// Compute the median of a non-empty list of integers.
  int _computeMedian(List<int> values) {
    final sorted = List<int>.from(values)..sort();
    final mid = sorted.length ~/ 2;

    if (sorted.length.isOdd) {
      return sorted[mid];
    } else {
      // average of the two middle values (integer division)
      return ((sorted[mid - 1] + sorted[mid]) ~/ 2);
    }
  }
}
