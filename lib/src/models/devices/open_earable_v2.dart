import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:open_earable_flutter/src/constants.dart';
import 'package:pub_semver/pub_semver.dart';

import '../../../open_earable_flutter.dart' hide Version;
import '../../managers/v2_sensor_handler.dart';
import '../capabilities/device_firmware_version.dart';
import '../capabilities/sensor_configuration_specializations/sensor_configuration_open_earable_v2.dart';

const String _batteryLevelCharacteristicUuid = "2A19";
const String _batteryLevelStatusCharacteristicUuid = "2BED";
const String _batteryHealthStatusCharacteristicUuid = "2BEA";
const String _batteryEnergyStatusCharacteristicUuid = "2BF0";

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

final VersionConstraint _versionConstraint = VersionConstraint.parse("<2.2.0");

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
class OpenEarableV2 extends Wearable
    with DeviceFirmwareVersionNumberExt
    implements
        SensorManager,
        SensorConfigurationManager,
        RgbLed,
        StatusLed,
        BatteryLevelStatus,
        BatteryLevelStatusService,
        BatteryHealthStatusService,
        BatteryEnergyStatusService,
        DeviceIdentifier,
        DeviceFirmwareVersion,
        DeviceHardwareVersion,
        MicrophoneManager<OpenEarableV2Mic>,
        AudioModeManager,
        EdgeRecorderManager,
        ButtonManager,
        StereoDevice,
        SystemDevice {
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

    _sensorConfigSubscription = _bleManager.subscribe(
      deviceId: deviceId,
      serviceId: sensorServiceUuid,
      characteristicId: sensorConfigStateCharacteristicUuid,
    ).listen(
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
      _bleManager.read(
        deviceId: deviceId,
        serviceId: sensorServiceUuid,
        characteristicId: sensorConfigStateCharacteristicUuid,
      ).then((data) {
        controller.add(_parseConfigMap(data));
      }).catchError((error) {
        logger.e('Error reading initial sensor configuration: $error');
        controller.addError(error);
      });
    };
    return controller.stream;
  }

  Map<SensorConfiguration, SensorConfigurationValue> _parseConfigMap(List<int> data) {
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
    
      SensorConfigurationValue? sensorConfigValue =
          matchingConfig.values.where(
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

  final BleGattManager _bleManager;
  final DiscoveredDevice _discoveredDevice;

  @override
  final Set<OpenEarableV2Mic> availableMicrophones;
  @override
  final Set<AudioMode> availableAudioModes;

  @override
  Future<String> get filePrefix async {
    List<int> prefixBytes = await _bleManager.read(
      deviceId: deviceId,
      serviceId: sensorServiceUuid,
      characteristicId: sensorEdgeRecorderFilePrefixCharacteristicUuid,
    );
    return String.fromCharCodes(prefixBytes);
  }

  @override
  Stream<ButtonEvent> get buttonEvents {
    StreamController<ButtonEvent> controller =
        StreamController<ButtonEvent>();

    _buttonSubscription?.cancel();

    _buttonSubscription = _bleManager.subscribe(
      deviceId: deviceId,
      serviceId: _buttonServiceUuid,
      characteristicId: _buttonCharacteristicUuid,
    ).listen(
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
      _bleManager.read(
        deviceId: deviceId,
        serviceId: _buttonServiceUuid,
        characteristicId: _buttonCharacteristicUuid,
      ).then((data) {
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
    required BleGattManager bleManager,
    required DiscoveredDevice discoveredDevice,
    this.availableMicrophones = const {},
    this.availableAudioModes = const {},
    bool isConnectedViaSystem = false,
  })  : _sensors = sensors,
        _sensorConfigurations = sensorConfigurations,
        _bleManager = bleManager,
        _discoveredDevice = discoveredDevice,
        _isConnectedViaSystem = isConnectedViaSystem;

  @override
  String get deviceId => _discoveredDevice.id;

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
    await _bleManager.write(
      deviceId: _discoveredDevice.id,
      serviceId: ledServiceUuid,
      characteristicId: _ledSetColorCharacteristic,
      byteData: data.buffer.asUint8List(),
    );
  }

  @override
  Future<void> showStatus(bool status) async {
    ByteData statusData = ByteData(1);
    statusData.setUint8(0, status ? 0 : 1);
    await _bleManager.write(
      deviceId: _discoveredDevice.id,
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
    List<int> deviceIdentifierBytes = await _bleManager.read(
      deviceId: _discoveredDevice.id,
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
    List<int> deviceGenerationBytes = await _bleManager.read(
      deviceId: _discoveredDevice.id,
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
    List<int> hardwareGenerationBytes = await _bleManager.read(
      deviceId: _discoveredDevice.id,
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
    return _bleManager.disconnect(_discoveredDevice.id);
  }

  @override
  List<SensorConfiguration> get sensorConfigurations =>
      List.unmodifiable(_sensorConfigurations);

  @override
  List<Sensor> get sensors => List.unmodifiable(_sensors);

  // MARK: Battery

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

  @override
  Future<BatteryEnergyStatus> readEnergyStatus() async {
    List<int> energyStatusList = await _bleManager.read(
      deviceId: _discoveredDevice.id,
      serviceId: batteryServiceUuid,
      characteristicId: _batteryEnergyStatusCharacteristicUuid,
    );

    logger.t("Battery energy status bytes: $energyStatusList");

    if (energyStatusList.length != 7) {
      throw StateError(
        'Battery energy status characteristic expected 7 values, but got ${energyStatusList.length}',
      );
    }

    int rawVoltage = (energyStatusList[2] << 8) | energyStatusList[1];
    double voltage = _convertSFloat(rawVoltage);

    int rawAvailableCapacity = (energyStatusList[4] << 8) | energyStatusList[3];
    double availableCapacity = _convertSFloat(rawAvailableCapacity);

    int rawChargeRate = (energyStatusList[6] << 8) | energyStatusList[5];
    double chargeRate = _convertSFloat(rawChargeRate);

    BatteryEnergyStatus batteryEnergyStatus = BatteryEnergyStatus(
      voltage: voltage,
      availableCapacity: availableCapacity,
      chargeRate: chargeRate,
    );

    logger.d('Battery energy status: $batteryEnergyStatus');

    return batteryEnergyStatus;
  }

  double _convertSFloat(int rawBits) {
    int exponent = ((rawBits & 0xF000) >> 12) - 16;
    int mantissa = rawBits & 0x0FFF;

    if (mantissa >= 0x800) {
      mantissa = -((0x1000) - mantissa);
    }
    logger.t("Exponent: $exponent, Mantissa: $mantissa");
    double result = mantissa.toDouble() * pow(10.0, exponent.toDouble());
    return result;
  }

  @override
  Future<BatteryHealthStatus> readHealthStatus() async {
    List<int> healthStatusList = await _bleManager.read(
      deviceId: _discoveredDevice.id,
      serviceId: batteryServiceUuid,
      characteristicId: _batteryHealthStatusCharacteristicUuid,
    );

    logger.t("Battery health status bytes: $healthStatusList");

    if (healthStatusList.length != 5) {
      throw StateError(
        'Battery health status characteristic expected 5 values, but got ${healthStatusList.length}',
      );
    }

    int healthSummary = healthStatusList[1];
    int cycleCount = (healthStatusList[2] << 8) | healthStatusList[3];
    int currentTemperature = healthStatusList[4];

    BatteryHealthStatus batteryHealthStatus = BatteryHealthStatus(
      healthSummary: healthSummary,
      cycleCount: cycleCount,
      currentTemperature: currentTemperature,
    );

    logger.d('Battery health status: $batteryHealthStatus');

    return batteryHealthStatus;
  }

  @override
  Future<BatteryPowerStatus> readPowerStatus() async {
    List<int> powerStateList = await _bleManager.read(
      deviceId: _discoveredDevice.id,
      serviceId: batteryServiceUuid,
      characteristicId: _batteryLevelStatusCharacteristicUuid,
    );

    int powerState = (powerStateList[1] << 8) | powerStateList[2];
    logger.d("Battery power status bits: ${powerState.toRadixString(2)}");

    bool batteryPresent = powerState >> 15 & 0x1 != 0;

    int wiredExternalPowerSourceConnectedRaw = (powerState >> 13) & 0x3;
    ExternalPowerSourceConnected wiredExternalPowerSourceConnected =
        ExternalPowerSourceConnected
            .values[wiredExternalPowerSourceConnectedRaw];

    int wirelessExternalPowerSourceConnectedRaw = (powerState >> 11) & 0x3;
    ExternalPowerSourceConnected wirelessExternalPowerSourceConnected =
        ExternalPowerSourceConnected
            .values[wirelessExternalPowerSourceConnectedRaw];

    int chargeStateRaw = (powerState >> 9) & 0x3;
    ChargeState chargeState = ChargeState.values[chargeStateRaw];

    int chargeLevelRaw = (powerState >> 7) & 0x3;
    BatteryChargeLevel chargeLevel = BatteryChargeLevel.values[chargeLevelRaw];

    int chargingTypeRaw = (powerState >> 5) & 0x7;
    BatteryChargingType chargingType =
        BatteryChargingType.values[chargingTypeRaw];

    int chargingFaultReasonRaw = (powerState >> 2) & 0x5;
    List<ChargingFaultReason> chargingFaultReason = [];
    if ((chargingFaultReasonRaw & 0x1) != 0) {
      chargingFaultReason.add(ChargingFaultReason.other);
    }
    if ((chargingFaultReasonRaw & 0x2) != 0) {
      chargingFaultReason.add(ChargingFaultReason.externalPowerSource);
    }
    if ((chargingFaultReasonRaw & 0x4) != 0) {
      chargingFaultReason.add(ChargingFaultReason.battery);
    }

    BatteryPowerStatus batteryPowerStatus = BatteryPowerStatus(
      batteryPresent: batteryPresent,
      wiredExternalPowerSourceConnected: wiredExternalPowerSourceConnected,
      wirelessExternalPowerSourceConnected:
          wirelessExternalPowerSourceConnected,
      chargeState: chargeState,
      chargeLevel: chargeLevel,
      chargingType: chargingType,
      chargingFaultReason: chargingFaultReason,
    );

    logger.d('Battery power status: $batteryPowerStatus');

    return batteryPowerStatus;
  }

  @override
  Stream<int> get batteryPercentageStream {
    StreamController<int> controller = StreamController<int>();
    Timer? batteryPollingTimer;

    controller.onCancel = () {
      batteryPollingTimer?.cancel();
    };

    controller.onListen = () {
      batteryPollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        readBatteryPercentage().then((batteryPercentage) {
          controller.add(batteryPercentage);
        }).catchError((e) {
          logger.e('Error reading battery percentage: $e');
        });
      });

      readBatteryPercentage().then((batteryPercentage) {
        controller.add(batteryPercentage);
      }).catchError((e) {
        logger.e('Error reading battery percentage: $e');
      });
    };

    return controller.stream;
  }

  @override
  Stream<BatteryPowerStatus> get powerStatusStream {
    StreamController<BatteryPowerStatus> controller =
        StreamController<BatteryPowerStatus>();
    Timer? powerPollingTimer;

    controller.onCancel = () {
      powerPollingTimer?.cancel();
    };

    controller.onListen = () {
      powerPollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        readPowerStatus().then((powerStatus) {
          controller.add(powerStatus);
        }).catchError((e) {
          logger.e('Error reading power status: $e');
        });
      });

      readPowerStatus().then((powerStatus) {
        controller.add(powerStatus);
      }).catchError((e) {
        logger.e('Error reading power status: $e');
      });
    };

    return controller.stream;
  }

  @override
  Stream<BatteryEnergyStatus> get energyStatusStream {
    StreamController<BatteryEnergyStatus> controller =
        StreamController<BatteryEnergyStatus>();
    Timer? energyPollingTimer;

    controller.onCancel = () {
      energyPollingTimer?.cancel();
    };

    controller.onListen = () {
      energyPollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        readEnergyStatus().then((energyStatus) {
          controller.add(energyStatus);
        }).catchError((e) {
          logger.e('Error reading energy status: $e');
        });
      });

      readEnergyStatus().then((energyStatus) {
        controller.add(energyStatus);
      }).catchError((e) {
        logger.e('Error reading energy status: $e');
      });
    };

    return controller.stream;
  }

  @override
  Stream<BatteryHealthStatus> get healthStatusStream {
    StreamController<BatteryHealthStatus> controller =
        StreamController<BatteryHealthStatus>();
    Timer? healthPollingTimer;

    controller.onCancel = () {
      healthPollingTimer?.cancel();
    };

    controller.onListen = () {
      healthPollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        readHealthStatus().then((healthStatus) {
          controller.add(healthStatus);
        }).catchError((e) {
          logger.e('Error reading health status: $e');
        });
      });

      readHealthStatus().then((healthStatus) {
        controller.add(healthStatus);
      }).catchError((e) {
        logger.e('Error reading health status: $e');
      });
    };

    return controller.stream;
  }

  // MARK: MicrophoneManager

  @override
  void setMicrophone(OpenEarableV2Mic microphone) {
    if (!availableMicrophones.contains(microphone)) {
      throw ArgumentError('Microphone not available: ${microphone.key}');
    }

    _bleManager.write(
      deviceId: deviceId,
      serviceId: _audioConfigServiceUuid,
      characteristicId: _micSelectCharacteristicUuid,
      byteData: [microphone.id],
    );
  }

  @override
  Future<OpenEarableV2Mic> getMicrophone() async {
    List<int> microphoneBytes = await _bleManager.read(
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

    _bleManager.write(
      deviceId: deviceId,
      serviceId: _audioConfigServiceUuid,
      characteristicId: _audioModeCharacteristicUuid,
      byteData: [audioMode.id],
    );
  }

  @override
  Future<AudioMode> getAudioMode() async {
    List<int> audioModeBytes = await _bleManager.read(
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
    return _bleManager.write(
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
      positionBytes = await _bleManager.read(
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
