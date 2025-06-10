import 'dart:typed_data';

import 'package:mcumgr_flutter/mcumgr_flutter.dart';
import '../model/firmware_image.dart';

class FirmwareUpdateRequest {
  SelectedFirmware? firmware;
  SelectedPeripheral? peripheral;

  FirmwareUpdateRequest({
    this.firmware,
    this.peripheral,
  });
}

class SingleImageFirmwareUpdateRequest extends FirmwareUpdateRequest {
  Uint8List? get firmwareImage =>
      firmware is LocalFirmware ? (firmware as LocalFirmware).data : null;

  SingleImageFirmwareUpdateRequest({
    super.peripheral,
    super.firmware,
  });
}

class MultiImageFirmwareUpdateRequest extends FirmwareUpdateRequest {
  Uint8List? zipFile;
  List<Image>? firmwareImages;

  RemoteFirmware? get remoteFirmware => firmware as RemoteFirmware?;

  MultiImageFirmwareUpdateRequest({
    this.zipFile,
    this.firmwareImages,
    super.peripheral,
    super.firmware,
  });
}

class SelectedFirmware {
  String get name => toString();
}

class RemoteFirmware extends SelectedFirmware {
  @override
  final String name;
  final String version;
  final String url;
  final FirmwareType type;

  RemoteFirmware({
    required this.name,
    required this.version,
    required this.url,
    required this.type,
  });
}

enum FirmwareType {
  singleImage,
  multiImage,
}

class LocalFirmware extends SelectedFirmware {
  @override
  final String name;
  final Uint8List data;
  final FirmwareType type;

  LocalFirmware({
    required this.name,
    required this.data,
    required this.type,
  });
}

class SelectedPeripheral {
  final String name;
  final String identifier;

  SelectedPeripheral({
    required this.name,
    required this.identifier,
  });
}
