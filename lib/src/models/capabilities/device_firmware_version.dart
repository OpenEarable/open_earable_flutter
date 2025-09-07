import '../../../open_earable_flutter.dart' show logger;
import 'version_number.dart';

abstract class DeviceFirmwareVersion {
  Future<String?> readDeviceFirmwareVersion();
  Future<VersionNumber?> readFirmwareVersionNumber();

  Future<bool> isFirmwareSupported();
}

mixin DeviceFirmwareVersionNumberExt implements DeviceFirmwareVersion {
  @override
  Future<VersionNumber?> readFirmwareVersionNumber() async {
    final ver = await readDeviceFirmwareVersion();
    if (ver == null) return null;
    try {
      return VersionNumber.parse(ver);
    } catch (e) {
      logger.w('Failed to parse firmware version: $ver, error: $e');
      return null;
    }
  }

  @override
  Future<bool> isFirmwareSupported() async {
    return true;
  }
}
