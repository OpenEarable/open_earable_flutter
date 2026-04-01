import '../../fota/model/firmware_update_request.dart';

/// Generic capability for wearable firmware-over-the-air (FOTA) operations.
///
/// This capability is intentionally independent of a specific transport or
/// update backend. A wearable may implement it using mcumgr today and a
/// different firmware update mechanism in the future while keeping the same
/// high-level integration surface for apps.
abstract class FotaManager {
  /// Creates a firmware update request for this wearable and the selected
  /// [firmware].
  ///
  /// Implementations may return backend-specific subclasses of
  /// [FirmwareUpdateRequest].
  FirmwareUpdateRequest createFirmwareUpdateRequest(SelectedFirmware firmware);
}
