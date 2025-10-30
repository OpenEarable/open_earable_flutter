import 'package:pub_semver/pub_semver.dart';

import '../../../open_earable_flutter.dart' show logger;

enum FirmwareSupportStatus {
  supported,
  unsupported,
  tooOld,
  tooNew,
  unknown,
}

abstract class DeviceFirmwareVersion {
  Future<String?> readDeviceFirmwareVersion();
  Future<Version?> readFirmwareVersionNumber();

  VersionConstraint get supportedFirmwareRange;

  Future<FirmwareSupportStatus> checkFirmwareSupport();
}

mixin DeviceFirmwareVersionNumberExt implements DeviceFirmwareVersion {
  @override
  Future<Version?> readFirmwareVersionNumber() async {
    final ver = await readDeviceFirmwareVersion();
    if (ver == null) return null;
    try {
      return Version.parse(ver);
    } catch (e) {
      logger.w('Failed to parse firmware version: $ver, error: $e');
      return null;
    }
  }

  @override
  Future<FirmwareSupportStatus> checkFirmwareSupport() async {
    final Version? ver = await readFirmwareVersionNumber();

    if (ver == null) return FirmwareSupportStatus.unknown;

    if (!supportedFirmwareRange.allows(ver)) {
      if (supportedFirmwareRange is! VersionRange) {
        return FirmwareSupportStatus.unsupported;
      }

      final range = supportedFirmwareRange as VersionRange;
      if (range.max != null && ver > range.max!) {
        return FirmwareSupportStatus.tooNew;
      } else if (range.min != null && ver < range.min!) {
        return FirmwareSupportStatus.tooOld;
      } else {
        return FirmwareSupportStatus.unsupported;
      }
    }

    return FirmwareSupportStatus.supported;
  }

  @override
  VersionConstraint get supportedFirmwareRange => VersionConstraint.any;
}
