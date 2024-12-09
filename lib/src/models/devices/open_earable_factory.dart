import 'package:logger/logger.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_earable_flutter/src/managers/ble_manager.dart';
import 'package:open_earable_flutter/src/models/devices/open_earable_v1.dart';
import 'package:open_earable_flutter/src/models/devices/open_earable_v2.dart';
import 'package:open_earable_flutter/src/models/wearable_factory.dart';
import 'package:universal_ble/universal_ble.dart';

const String _deviceInfoServiceUuid = "45622510-6468-465a-b141-0b9b0f96b468";
const String _deviceFirmwareVersionCharacteristicUuid =
    "45622512-6468-465a-b141-0b9b0f96b468";

Logger _logger = Logger();

class OpenEarableFactory extends WearableFactory {
  final _v1Regex = RegExp(r'^1\.\d+\.\d+$');
  final _v2Regex = RegExp(r'^2\.\d+\.\d+$');

  @override
  Future<bool> matches(DiscoveredDevice device, List<BleService> services) async {
    if (!services.any((service) => service.uuid == _deviceInfoServiceUuid)) {
      _logger.d("'$device' has no service matching '$_deviceInfoServiceUuid'");
      return false;
    }
    String firmwareVersion = await _getFirmwareVersion(device);
    _logger.d("Firmware Version: '$firmwareVersion'");

    _logger.t("matches V2: ${_v2Regex.hasMatch(firmwareVersion)}");

    return _v1Regex.hasMatch(firmwareVersion) || _v2Regex.hasMatch(firmwareVersion);
  }
  
  @override
  Future<Wearable> createFromDevice(DiscoveredDevice device) async {
    if (bleManager == null) {
      throw Exception("bleManager needs to be set before using the factory");
    }
    if (disconnectNotifier == null) {
      throw Exception("disconnectNotifier needs to be set before using the factory");
    }
    String firmwareVersion = await _getFirmwareVersion(device);


    if (_v1Regex.hasMatch(firmwareVersion)) {
      return OpenEarableV1(
        name: device.name,
        disconnectNotifier: disconnectNotifier!,
        bleManager: bleManager!,
        discoveredDevice: device,
      );
    } else if (_v2Regex.hasMatch(firmwareVersion)) {
      return OpenEarableV2(
        name: device.name,
        disconnectNotifier: disconnectNotifier!,
        bleManager: bleManager!,
        discoveredDevice: device,
      );
    } else {
      throw Exception('OpenEarable version is not supported');
    }
  }

  Future<String> _getFirmwareVersion(DiscoveredDevice device) async {
    List<int> softwareGenerationBytes = await bleManager!.read(
      deviceId: device.id,
      serviceId: _deviceInfoServiceUuid,
      characteristicId: _deviceFirmwareVersionCharacteristicUuid,
    );
    _logger.d("Raw Firmware Version: $softwareGenerationBytes");
    int firstZeroIndex = softwareGenerationBytes.indexOf(0);
    if (firstZeroIndex != -1) {
      softwareGenerationBytes = softwareGenerationBytes.sublist(0, firstZeroIndex);
    }
    return String.fromCharCodes(softwareGenerationBytes);
  }
}
