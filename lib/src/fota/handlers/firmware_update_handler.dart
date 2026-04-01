import 'dart:convert';
import 'dart:io';

import 'package:flutter_archive/flutter_archive.dart';
import 'package:mcumgr_flutter/models/firmware_upgrade_mode.dart';
import '../model/firmware_update_request.dart';
import '../model/manifest.dart';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:uuid/uuid.dart';

import 'package:mcumgr_flutter/mcumgr_flutter.dart';

part 'firmware_update_state.dart';

/// Callback used to surface intermediate pipeline states while the request is
/// being prepared and uploaded.
typedef FirmwareUpdateCallback = void Function(FirmwareUpdateState state);

/// Base link in the firmware update preparation pipeline.
///
/// Concrete handlers implement one step of the process and forward the request
/// to the next handler once their work is complete.
abstract class FirmwareUpdateHandler {
  FirmwareUpdateHandler? _nextHandler;

  /// Processes [request] and eventually returns the active firmware update
  /// manager.
  Future<FirmwareUpdateManager> handleFirmwareUpdate(
    FirmwareUpdateRequest request,
    FirmwareUpdateCallback? callback,
  );

  /// Configures the next handler in the chain.
  Future<void> setNextHandler(FirmwareUpdateHandler handler) async {
    _nextHandler = handler;
  }
}

/// Downloads remote firmware archives before forwarding the request.
class FirmwareDownloader extends FirmwareUpdateHandler {
  @override
  Future<FirmwareUpdateManager> handleFirmwareUpdate(
    FirmwareUpdateRequest request,
    FirmwareUpdateCallback? callback,
  ) async {
    if (request.firmware is LocalFirmware) {
      if (request is MultiImageFirmwareUpdateRequest) {
        request.zipFile = (request.firmware as LocalFirmware).data;
      }
      return await _nextHandler!.handleFirmwareUpdate(request, callback);
    }

    final multiImageRequest = request as MultiImageFirmwareUpdateRequest;

    callback?.call(FirmwareDownloadStarted());

    if (request.firmware == null) {
      throw Exception('Firmware is not selected');
    }

    final remoteFirmware = multiImageRequest.remoteFirmware!;

    final response = await http.get(Uri.parse(remoteFirmware.url));
    if (response.statusCode == 200) {
      multiImageRequest.zipFile = response.bodyBytes;
    } else {
      throw Exception('Failed to download firmware');
    }

    return await _nextHandler!
        .handleFirmwareUpdate(multiImageRequest, callback);
  }
}

/// Extracts multi-image archives and parses their `manifest.json`.
class FirmwareUnpacker extends FirmwareUpdateHandler {
  @override
  Future<FirmwareUpdateManager> handleFirmwareUpdate(
    FirmwareUpdateRequest request,
    FirmwareUpdateCallback? callback,
  ) async {
    callback?.call(FirmwareUnpackStarted());

    if (request.firmware == null) {
      throw Exception('Firmware is not selected');
    }

    if (request is SingleImageFirmwareUpdateRequest) {
      return await _nextHandler!.handleFirmwareUpdate(request, callback);
    }

    final prefix = 'firmware_${const Uuid().v4()}';
    final systemTempDir = await path_provider.getTemporaryDirectory();

    final tempDir = Directory('${systemTempDir.path}/$prefix');
    await tempDir.create();

    final firmware = request as MultiImageFirmwareUpdateRequest;
    final firmwareFileData = firmware.zipFile!;
    final firmwareFile = File('${tempDir.path}/firmware.zip');
    await firmwareFile.writeAsBytes(firmwareFileData);

    final destinationDir = Directory('${tempDir.path}/firmware');
    await destinationDir.create();
    try {
      await ZipFile.extractToDirectory(
        zipFile: firmwareFile,
        destinationDir: destinationDir,
      );
    } catch (e) {
      throw Exception('Failed to unzip firmware');
    }

    // read manifest.json
    final manifestFile = File('${destinationDir.path}/manifest.json');
    final manifestString = await manifestFile.readAsString();
    Map<String, dynamic> manifestJson = json.decode(manifestString);
    Manifest manifest;

    try {
      manifest = Manifest.fromJson(manifestJson);
    } catch (e) {
      throw Exception('Failed to parse manifest.json');
    }

    firmware.firmwareImages = [];
    for (final file in manifest.files) {
      final firmwareFile = File('${destinationDir.path}/${file.file}');
      final firmwareFileData = await firmwareFile.readAsBytes();
      final image = Image(
        image: file.image,
        data: firmwareFileData,
      );
      firmware.firmwareImages!.add(image);
    }

    // delete tempDir
    await tempDir.delete(recursive: true);

    return await _nextHandler!.handleFirmwareUpdate(request, callback);
  }
}

/// Uploads the prepared firmware image data through `mcumgr_flutter`.
class FirmwareUpdater extends FirmwareUpdateHandler {
  final UpdateManagerFactory _updateManagerFactory =
      FirmwareUpdateManagerFactory();

  @override
  Future<FirmwareUpdateManager> handleFirmwareUpdate(
    FirmwareUpdateRequest request,
    FirmwareUpdateCallback? callback,
  ) async {
    callback?.call(FirmwareUploadStarted());

    if (request.peripheral == null) {
      throw Exception('Peripheral is not selected');
    }

    final updateManager = await _updateManagerFactory
        .getUpdateManager(request.peripheral!.identifier);

    updateManager.setup();

    if (request is SingleImageFirmwareUpdateRequest) {
      final fwImage = request.firmwareImage;
      await updateManager.updateWithImageData(
        imageData: fwImage!,
        configuration: const FirmwareUpgradeConfiguration(
          firmwareUpgradeMode: FirmwareUpgradeMode.testOnly,
        ),
      );
      return updateManager;
    } else {
      final multiImageRequest = request as MultiImageFirmwareUpdateRequest;
      updateManager.update(
        multiImageRequest.firmwareImages!,
        configuration: const FirmwareUpgradeConfiguration(
          firmwareUpgradeMode: FirmwareUpgradeMode.testOnly,
        ),
      );
    }

    return updateManager;
  }
}
