import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';
import 'package:cbor/cbor.dart';
import 'package:open_earable_flutter/src/constants.dart';
import 'package:flutter/services.dart' show rootBundle;

// Constants for the firmware image structure
const int IMAGE_TLV_INFO_SIZE = 4; // Size of the TLV info header
const int IMAGE_TLV_ENTRY_MIN_SIZE = 4; // Minimum size of a TLV entry

const int IMAGE_TLV_SHA256 = 0x10; // SHA-256 hash type

class FirmwareUpdateManager {
  FirmwareUpdateManager();
  bool chunkAcknowledged = false;
  Future<Uint8List> loadFirmwareFromAssets(String filePath) async {
    ByteData byteData = await rootBundle.load(filePath);
    return byteData.buffer.asUint8List();
  }

  Future<void> sendFirmwareData(
    String deviceId,
    String assetPath, {
    int mtu = 20,
  }) async {
    await enableNotifications(deviceId);
    setupListener(deviceId);
    Uint8List firmwareData = await loadFirmwareFromAssets(assetPath);

    print('Firmware data loaded. Size: ${firmwareData.length} bytes');

    // Determine the SHA256 hash of the firmware
    var sha256Hash = extractHashFromTlv(firmwareData);

    var mtu = await UniversalBle.requestMtu(deviceId, 247);

    print("MTU size: $mtu");
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
      print("header generated: $header, payloadLen: ${payload.length}");

      Uint8List packet = Uint8List(header.length + payload.length);
      if (packet.length > mtu) {
        throw Exception("Packet size exceeds MTU: ${packet.length} > $mtu");
      }
      packet.setAll(0, header);
      packet.setAll(header.length, payload);

      print("payload length: ${packet.length}");

      int maxRetries = 3;
      bool success = false;
      int attempt = 0;
      while (!success && attempt < maxRetries) {
        print("Offset $offset");
        attempt++;
        try {
          print("seqence: $seq");
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
          print("took $a cycles to acknowledge");
          success = true;
          seq += 1;
          print(
              "Chunk sent successfully after $attempt attempts. Offset: $offset");
        } catch (e) {
          print(
              "Error sending chunk at offset $offset on attempt $attempt: $e");
          await Future.delayed(const Duration(milliseconds: 100));
          if (attempt >= maxRetries) {
            print("Failed to send chunk after $maxRetries attempts. Aborting.");
            return;
          }
        }
      }
      offset += currentChunkSize;
    }
    await applyUpdate(deviceId, sha256Hash);
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
      print("Notifications enabled successfully.");
    }).catchError((error) {
      print("Failed to enable notifications: $error");
    });
  }

  Future<void> applyUpdate(String deviceId, Uint8List hash) async {
    print(hash);
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

    int maxRetries = 3;
    bool success = false;
    int attempt = 0;

    while (!success && attempt < maxRetries) {
      attempt++;
      try {
        await UniversalBle.writeValue(
          deviceId,
          smpServiceUuid,
          smpCharacteristic,
          packet,
          BleOutputProperty.withoutResponse,
        );
        success = true;
        print("Firmware confirmed after $attempt attempts");
      } catch (e) {
        print("Error sending chunk on attempt $attempt: $e");
        await Future.delayed(const Duration(milliseconds: 100));
        if (attempt >= maxRetries) {
          print("Failed to send chunk after $maxRetries attempts. Aborting.");
          return;
        }
      }
    }
    await Future.delayed(const Duration(seconds: 5));
    final resetPayload = Uint8List.fromList(
      cbor.encode(
        CborMap({}),
      ),
    );
    final resetHeader = buildSmpHeader(0, 2, 0, resetPayload.length, 0, 0, 5);

    Uint8List resetPacket = Uint8List(resetHeader.length + resetPayload.length);
    packet.setAll(0, resetHeader);
    packet.setAll(resetHeader.length, resetPacket);

    success = false;
    attempt = 0;
    while (!success && attempt < maxRetries) {
      attempt++;
      try {
        await UniversalBle.writeValue(
          deviceId,
          smpServiceUuid,
          smpCharacteristic,
          Uint8List.fromList(resetPacket),
          BleOutputProperty.withoutResponse,
        );
        success = true;
        print("Device rebooting after $attempt attempts");
      } catch (e) {
        print("Error sending chunk on attempt $attempt: $e");
        await Future.delayed(const Duration(milliseconds: 100));
        if (attempt >= maxRetries) {
          print("Failed to send chunk after $maxRetries attempts. Aborting.");
          return;
        }
      }
    }
    print("Device rebooting...");
  }

  void setupListener(deviceId) {
    print("Setup liestener");
    UniversalBle.onValueChange = (
      String receivedDeviceId,
      String characteristicUuid,
      Uint8List value,
    ) {
      print("got notification");
      print('Received notification: $value');
      int headerLength = 8;
      // Remove the header
      Uint8List cborData = value.sublist(headerLength);
      try {
        final decoded = cbor.decode(cborData);
        print('Received notification: $decoded');

        // Check if the notification is an acknowledgment
        if (true) {
          //decoded.containsKey('off')) {
          chunkAcknowledged = true; // Set the acknowledgment flag
        }
      } catch (e) {
        print('Error decoding CBOR: $e');
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

  Future<BleCharacteristic> findSmpCharacteristic(
    String deviceId,
    BleService smpService,
  ) async {
    final smpCharacteristic = smpService.characteristics.firstWhere(
      (characteristic) =>
          characteristic.uuid == "da2e7828-fbce-4e01-ae9e-261174997c48",
      orElse: () => throw Exception(
        "SMP characteristic not found. Cannot proceed with firmware update.",
      ),
    );
    return smpCharacteristic;
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
          print(
            'Stored Hash: ${hashValue.map((byte) => byte.toRadixString(16).padLeft(2, '0')).toList().join()}',
          );
          return hashValue;
        }

        // Move to the next TLV entry
        tlvEntryOffset += 4 + tlvLength;
      }
    } catch (e) {
      print('Error parsing firmware image: $e');
    }
    throw Exception('Hash not found in TLV trailer.');
  }
}
