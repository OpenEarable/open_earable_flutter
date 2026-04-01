import 'package:open_earable_flutter/src/models/capabilities/fota_capability.dart';
import 'package:open_earable_flutter/src/models/capabilities/fota_slot_info_capability.dart';

import 'package:mcumgr_flutter/mcumgr_flutter.dart';

import 'model/firmware_update_request.dart';

/// Standard BLE service UUID for the MCUmgr SMP transport.
const String mcuMgrSmpServiceUuid = '8d53dc1d-1db7-4cd3-868b-8a527460aa84';

/// mcumgr-backed implementation of [FotaManager].
class McuMgrFotaCapability implements FotaManager {
  final String _deviceId;
  final String _deviceName;

  McuMgrFotaCapability({
    required String deviceId,
    required String deviceName,
  })  : _deviceId = deviceId,
        _deviceName = deviceName;

  @override
  FirmwareUpdateRequest createFirmwareUpdateRequest(SelectedFirmware firmware) {
    final peripheral = SelectedPeripheral(
      name: _deviceName,
      identifier: _deviceId,
    );

    if (firmware is RemoteFirmware) {
      return MultiImageFirmwareUpdateRequest(
        peripheral: peripheral,
        firmware: firmware,
      );
    }

    if (firmware is LocalFirmware) {
      if (firmware.type == FirmwareType.singleImage) {
        return SingleImageFirmwareUpdateRequest(
          peripheral: peripheral,
          firmware: firmware,
        );
      }

      return MultiImageFirmwareUpdateRequest(
        peripheral: peripheral,
        firmware: firmware,
      );
    }

    return FirmwareUpdateRequest(
      peripheral: peripheral,
      firmware: firmware,
    );
  }
}

/// mcumgr-backed implementation of [FotaSlotInfoCapability].
class McuMgrFotaSlotInfoManager implements FotaSlotInfoCapability {
  final String _deviceId;
  final UpdateManagerFactory _updateManagerFactory;

  McuMgrFotaSlotInfoManager({
    required String deviceId,
    UpdateManagerFactory? updateManagerFactory,
  })  : _deviceId = deviceId,
        _updateManagerFactory =
            updateManagerFactory ?? FirmwareUpdateManagerFactory();

  @override
  Future<List<FirmwareSlotInfo>> readFirmwareSlots() async {
    final updateManager = await _updateManagerFactory.getUpdateManager(_deviceId);
    try {
      final slots = await updateManager.readImageList();
      if (slots == null) {
        return const [];
      }
      return slots
          .map(FirmwareSlotInfo.fromImageSlot)
          .toList(growable: false);
    } finally {
      await updateManager.kill();
    }
  }
}
