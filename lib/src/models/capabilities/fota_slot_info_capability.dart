import 'package:meta/meta.dart';
import 'package:mcumgr_flutter/mcumgr_flutter.dart';

/// Optional capability for wearables that expose firmware slot or image-table
/// state as part of their update mechanism.
///
/// This is separate from [FotaCapability] because not every FOTA backend uses
/// MCUboot-style slots.
abstract class FotaSlotInfoCapability {
  /// Reads the firmware images or slots currently reported by the wearable.
  Future<List<FirmwareSlotInfo>> readFirmwareSlots();
}

/// Snapshot of one firmware image slot reported by the wearable.
@immutable
class FirmwareSlotInfo {
  /// Image number in the device's firmware image table.
  final int image;

  /// Slot index for the image.
  final int slot;

  /// Human-readable firmware version, when provided by the device.
  final String? version;

  /// Raw image hash bytes.
  final List<int> hash;

  /// Whether the slot contains a bootable image.
  final bool bootable;

  /// Whether the image is marked as pending for the next boot.
  final bool pending;

  /// Whether the image is confirmed.
  final bool confirmed;

  /// Whether the image is currently active.
  final bool active;

  /// Whether the image is marked as permanent.
  final bool permanent;

  /// Hex-encoded representation of [hash].
  final String hashString;

  const FirmwareSlotInfo({
    required this.image,
    required this.slot,
    required this.version,
    required this.hash,
    required this.bootable,
    required this.pending,
    required this.confirmed,
    required this.active,
    required this.permanent,
    required this.hashString,
  });

  /// Creates a library-level slot model from the underlying mcumgr type.
  factory FirmwareSlotInfo.fromImageSlot(ImageSlot slot) {
    return FirmwareSlotInfo(
      image: slot.image,
      slot: slot.slot,
      version: slot.version,
      hash: List<int>.unmodifiable(slot.hash),
      bootable: slot.bootable,
      pending: slot.pending,
      confirmed: slot.confirmed,
      active: slot.active,
      permanent: slot.permanent,
      hashString: slot.hashString,
    );
  }
}

/// Deprecated alias kept for compatibility with the earlier slot-only API.
@Deprecated('Use FotaSlotInfoCapability instead.')
abstract class FirmwareSlotManager implements FotaSlotInfoCapability {}
