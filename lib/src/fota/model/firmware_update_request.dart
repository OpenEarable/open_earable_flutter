import 'dart:typed_data';

import 'package:mcumgr_flutter/mcumgr_flutter.dart';

/// Base request object used by the FOTA pipeline.
///
/// It contains the selected firmware artifact and the target peripheral. The
/// concrete subclasses describe whether the update uses a single raw binary or
/// a multi-image archive.
class FirmwareUpdateRequest {
  /// The firmware artifact selected by the user.
  SelectedFirmware? firmware;

  /// The BLE peripheral that should receive the update.
  SelectedPeripheral? peripheral;

  FirmwareUpdateRequest({
    this.firmware,
    this.peripheral,
  });
}

/// Request for single-image updates backed by a local `.bin` payload.
class SingleImageFirmwareUpdateRequest extends FirmwareUpdateRequest {
  /// Returns the firmware bytes when the selected firmware is a local artifact.
  Uint8List? get firmwareImage =>
      firmware is LocalFirmware ? (firmware as LocalFirmware).data : null;

  SingleImageFirmwareUpdateRequest({
    super.peripheral,
    super.firmware,
  });
}

/// Request for multi-image updates distributed as a `.zip` archive.
///
/// The archive can originate from a remote release or from a local file. During
/// processing, the downloader stores the archive in [zipFile] and the unpacker
/// extracts MCUboot image payloads into [firmwareImages].
class MultiImageFirmwareUpdateRequest extends FirmwareUpdateRequest {
  /// Raw bytes of the downloaded or user-provided firmware archive.
  Uint8List? zipFile;

  /// Parsed image payloads extracted from [zipFile].
  List<Image>? firmwareImages;

  /// Convenience accessor for remote firmware selections.
  RemoteFirmware? get remoteFirmware => firmware as RemoteFirmware?;

  MultiImageFirmwareUpdateRequest({
    this.zipFile,
    this.firmwareImages,
    super.peripheral,
    super.firmware,
  });
}

/// Base type for firmware choices presented to the user.
class SelectedFirmware {
  /// Human-readable firmware name shown in selection UIs.
  String get name => toString();
}

/// Firmware artifact that has to be downloaded before updating.
class RemoteFirmware extends SelectedFirmware {
  @override
  final String name;

  /// Semantic version or release label associated with the artifact.
  final String version;

  /// Direct download URL for the artifact.
  final String url;

  /// Package format of the artifact.
  final FirmwareType type;

  RemoteFirmware({
    required this.name,
    required this.version,
    required this.url,
    required this.type,
  });
}

/// Supported firmware package formats.
enum FirmwareType {
  /// A single update image, typically a raw `.bin` file.
  singleImage,

  /// A multi-image archive, typically an MCUboot-compatible `.zip` bundle.
  multiImage,
}

/// Firmware artifact that is already available on the local device.
class LocalFirmware extends SelectedFirmware {
  @override
  final String name;

  /// Raw contents of the local firmware file.
  final Uint8List data;

  /// Package format of the local artifact.
  final FirmwareType type;

  LocalFirmware({
    required this.name,
    required this.data,
    required this.type,
  });
}

/// Lightweight identifier for the peripheral that should receive the update.
class SelectedPeripheral {
  /// Display name shown to the user.
  final String name;

  /// Platform-specific peripheral identifier used by `mcumgr_flutter`.
  final String identifier;

  SelectedPeripheral({
    required this.name,
    required this.identifier,
  });
}
