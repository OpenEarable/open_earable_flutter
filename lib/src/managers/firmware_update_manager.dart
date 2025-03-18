import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:cbor/cbor.dart';
import 'package:open_earable_flutter/src/constants.dart';
import 'package:flutter/services.dart' show rootBundle;

Logger logger = Logger(printer: SimplePrinter());

// Constants for the firmware image structure
const int IMAGE_TLV_INFO_SIZE = 4; // Size of the TLV info header
const int IMAGE_TLV_ENTRY_MIN_SIZE = 4; // Minimum size of a TLV entry

const int IMAGE_TLV_SHA256 = 0x10; // SHA-256 hash type

enum FirmwareUpdateStatus { idle, uploading, confirming, rebooting, success }

class FirmwareUpdateManager {
  int lastAcknowledgedOffset = 0;
  bool chunkAcknowledged = false;

  var _progressController = StreamController<double>.broadcast();
  var _statusController = StreamController<FirmwareUpdateStatus>.broadcast();

  Stream<double> get progressStream => _progressController.stream;
  Stream<FirmwareUpdateStatus> get statusStream => _statusController.stream;

  void updateProgress(double value) {
    logger.d("Upload Progress: $value");
    _progressController.add(value < 1 ? value : 1);
  }

  void updateStatus(FirmwareUpdateStatus status) {
    logger.d("Upload Status: $status");
    _statusController.add(status);
  }

  Future<Uint8List> loadFirmwareFromAssets(String filePath) async {
    ByteData byteData = await rootBundle.load(filePath);
    return byteData.buffer.asUint8List();
  }

  Future<void> updateFirmware(String deviceId, String assetPath) async {
    updateStatus(FirmwareUpdateStatus.idle);
    updateProgress(0.0);

    await enableNotifications(deviceId);
    setupListener(deviceId);
    Uint8List firmwareData = await loadFirmwareFromAssets(assetPath);

    logger.d('Firmware data loaded. Size: ${firmwareData.length} bytes');

    // Determine the SHA256 hash of the firmware
    var sha256Hash = extractHashFromTlv(firmwareData);
    await sendFirmwareData(deviceId, firmwareData, sha256Hash);
    await confirmUpdate(deviceId, sha256Hash);
    await rebootDevice(deviceId);
  }

  Future<void> sendFirmwareData(
    String deviceId,
    Uint8List firmwareData,
    Uint8List sha256Hash, {
    int mtu = 20,
  }) async {
    updateStatus(FirmwareUpdateStatus.uploading);
    var mtu = await UniversalBle.requestMtu(deviceId, 247);

    logger.d("MTU size: $mtu");
    int chunkSize = mtu - 100;

    int offset = 0;
    int seq = 0;
    while (offset < firmwareData.length) {
      int currentChunkSize = (firmwareData.length - offset).clamp(0, chunkSize);

      Uint8List dataChunk =
          firmwareData.sublist(offset, offset + currentChunkSize);

      Uint8List payload = createCborImageUploadPayload(
        offset: offset,
        dataChunk: dataChunk,
        totalSize: offset == 0 ? firmwareData.length : null,
        sha256: offset == 0 ? sha256Hash : null,
      );
      Uint8List header = buildSmpHeader(0, 2, 0, payload.length, 1, seq, 1);
      logger.d("header generated: $header, payloadLen: ${payload.length}");

      Uint8List packet = Uint8List(header.length + payload.length);
      if (packet.length > mtu) {
        throw Exception("Packet size exceeds MTU: ${packet.length} > $mtu");
      }
      packet.setAll(0, header);
      packet.setAll(header.length, payload);

      logger.d("packet length: ${packet.length}");

      await sendPacket(deviceId, packet, offset: offset, seq: seq);
      updateProgress(
          lastAcknowledgedOffset / (firmwareData.length - chunkSize));
      seq += 1;
      offset += currentChunkSize;
    }
  }

  Future<void> sendPacket(
    String deviceId,
    Uint8List packet, {
    offset = 0,
    seq = 0,
  }) async {
    int maxRetries = 3;
    bool success = false;
    int attempt = 0;
    while (!success && attempt < maxRetries) {
      attempt++;
      try {
        chunkAcknowledged = false;
        await UniversalBle.writeValue(
          deviceId,
          smpServiceUuid,
          smpCharacteristic,
          packet,
          BleOutputProperty.withoutResponse,
        );
        var a = 0;
        while (!chunkAcknowledged) {
          a += 1;
          await Future.delayed(const Duration(milliseconds: 10));
        }
        logger.d(
          "Chunk $seq at offset $offset sent successfully after $attempt attempts and $a cycles.",
        );
        success = true;
      } catch (e) {
        logger
            .e("Error sending chunk at offset $offset on attempt $attempt: $e");
        await Future.delayed(const Duration(milliseconds: 100));
        if (attempt >= maxRetries) {
          logger
              .e("Failed to send chunk after $maxRetries attempts. Aborting.");
          return;
        }
      }
    }
  }

  Uint8List buildSmpHeader(
    int version,
    int op,
    int flags,
    int dataLen,
    int group,
    int seq,
    int cmdId,
  ) {
    // First Byte: 7 6 5     4 3      2 1 0
    //             Reserved  Version  Op
    int firstByte = ((version & 0x3) << 3) | (op & 0x3);

    return Uint8List.fromList([
      firstByte,
      flags, // Flags
      (dataLen >> 8) & 0xFF, // Data Length (high byte)
      dataLen & 0xFF, // Data Length (low byte)
      (group >> 8) & 0xFF, // Group ID (high byte)
      group & 0xFF, // Group ID (low byte)
      seq & 0xFF, // Sequence number
      cmdId & 0xFF // Command ID
    ]);
  }

  Future<void> enableNotifications(String deviceId) async {
    UniversalBle.discoverServices(deviceId);
    await UniversalBle.setNotifiable(
      deviceId,
      smpServiceUuid,
      smpCharacteristic,
      BleInputProperty.notification,
    ).then((_) {
      logger.d("Notifications enabled successfully.");
    }).catchError((error) {
      logger.e("Failed to enable notifications: $error");
    });
  }

  Future<void> confirmUpdate(String deviceId, Uint8List hash) async {
    updateStatus(FirmwareUpdateStatus.confirming);
    logger.d("Confirming update...");
    final confirmPayload = Uint8List.fromList(
      cbor.encode(
        CborMap({
          CborString("hash"): CborBytes(hash),
          CborString("confirm"):
              const CborBool(true), // Confirm the new firmware
        }),
      ),
    );

    var header = buildSmpHeader(0, 2, 0, confirmPayload.length, 1, 0, 0);
    Uint8List packet = Uint8List(header.length + confirmPayload.length);

    packet.setAll(0, header);
    packet.setAll(header.length, confirmPayload);

    await sendPacket(deviceId, packet);
  }

  Future<void> rebootDevice(String deviceId) async {
    updateStatus(FirmwareUpdateStatus.rebooting);
    logger.d("Device rebooting...");
    final resetPacket = buildSmpHeader(0, 2, 0, 0, 0, 0, 5);
    await sendPacket(deviceId, resetPacket);
  }

  void setupListener(deviceId) {
    logger.d("Setup listener");
    UniversalBle.onValueChange = (
      String receivedDeviceId,
      String characteristicUuid,
      Uint8List value,
    ) {
      int headerLength = 8;
      // Remove the header
      Uint8List cborData = value.sublist(headerLength);
      try {
        final decoded = cbor.decode(cborData);
        logger.d('Received notification');
        logger.d("  Raw value: $value");
        logger.d("  Decoded value: $decoded");
        if (decoded is CborMap) {
          // Access the value for the key 'off'
          var offValue = decoded[CborString('off')];
          if (offValue is CborSmallInt) {
            // Convert CborSmallInt to Dart int
            lastAcknowledgedOffset = offValue.value;
          } else {
            logger.d('Decoded data is not a CborSmallInt');
          }
        } else {
          logger.d('Decoded data is not a CborMap');
        }
        // Check if the notification is an acknowledgment
        if (true) {
          //decoded.containsKey('off')) {
          chunkAcknowledged = true; // Set the acknowledgment flag
        }
      } catch (e) {
        logger.e('Error decoding CBOR: $e');
      }
    };
  }

  Uint8List createCborImageUploadPayload({
    required int offset,
    required Uint8List dataChunk,
    int? totalSize,
    Uint8List? sha256,
    int image = 0,
    bool upgrade = false,
  }) {
    final payload = <CborValue, CborValue>{
      CborString('off'): CborSmallInt(offset),
      CborString('data'): CborBytes(dataChunk),
    };

    // Add fields that are required only for the first chunk
    if (offset == 0) {
      payload[CborValue('image')] = CborSmallInt(image);
      if (totalSize != null) {
        payload[CborValue('len')] = CborSmallInt(totalSize);
      }
      if (sha256 != null) {
        payload[CborValue('sha')] = CborBytes(sha256);
      }
      payload[CborValue('upgrade')] = CborBool(upgrade);
    }

    var map = CborMap(payload);

    return Uint8List.fromList(cbor.encode(map));
  }

  Future<BleService> findSmpService(String deviceId) async {
    final services = await UniversalBle.discoverServices(deviceId);

    final smpService = services.firstWhere(
      (service) => service.uuid == smpServiceUuid,
      orElse: () => throw Exception(
        "SMP service not found. Cannot proceed with firmware update.",
      ),
    );
    return smpService;
  }

  // Parse the firmware image and compute the hash
  Uint8List extractHashFromTlv(Uint8List firmwareData) {
    try {
      // structure of mcuboot image format: https://docs.mcuboot.com/design.html#image-format
      // Parse header
      final header = firmwareData.sublist(0, 32);
      final magic = header.buffer.asByteData().getUint32(0, Endian.little);
      final headerSize = header.buffer
          .asByteData()
          .getUint32(8, Endian.little); // ih_img_size at offset 16
      final imageSize = header.buffer
          .asByteData()
          .getUint32(12, Endian.little); // ih_img_size at offset 16

      // Locate the TLV trailer
      final tlvOffset = headerSize + imageSize;

      // Iterate through TLV entries and find hash
      var tlvEntryOffset = tlvOffset + IMAGE_TLV_INFO_SIZE;
      while (tlvEntryOffset + IMAGE_TLV_ENTRY_MIN_SIZE < firmwareData.length) {
        final tlvEntry = firmwareData.sublist(
          tlvEntryOffset,
          tlvEntryOffset + IMAGE_TLV_ENTRY_MIN_SIZE,
        );
        final tlvType = tlvEntry[0];
        final tlvLength =
            tlvEntry.buffer.asByteData().getUint16(2, Endian.little);

        if (tlvType == IMAGE_TLV_SHA256) {
          final hashValue = firmwareData.sublist(
            tlvEntryOffset + 4,
            tlvEntryOffset + 4 + tlvLength,
          );
          logger.d(
            'Hash stored in TLV: ${hashValue.map((byte) => byte.toRadixString(16).padLeft(2, '0')).toList().join()}',
          );
          return hashValue;
        }

        // Move to the next TLV entry
        tlvEntryOffset += 4 + tlvLength;
      }
    } catch (e) {
      logger.e('Error parsing firmware image: $e');
    }
    throw Exception('Hash not found in TLV trailer.');
  }

  void dispose() {
    _progressController.close();
    _statusController.close();
  }
}
