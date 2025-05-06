import 'dart:async';
import 'dart:io';
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

  Completer<void>? _acknowledgmentCompleter;
  Completer<List<int>>? _responseCompleter;

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

    List<int> bufferInfo = await getBufferSize(deviceId);
    int bufferSize = bufferInfo[0];
    int bufferCount = bufferInfo[1];

    int mtu = 20;
    if (!kIsWeb && !Platform.isLinux) {
      mtu = await UniversalBle.requestMtu(deviceId, mtu); // Mobile/desktop
    }
    logger.d("MTU size: $mtu");

    const int WRITE_VALUE_BUFFER_SIZE = 10; // for iOS
    if (bufferSize / mtu > WRITE_VALUE_BUFFER_SIZE) {
      final newSize = mtu * WRITE_VALUE_BUFFER_SIZE;
      bufferSize = newSize;
      logger.d(
        'Lowered Reassembly Buffer Size to $newSize due to low MTU (too many Bluetooth API writes per buffer).',
      );
    }
    if (bufferSize > 65535) {
      bufferSize = 65535;
    }
    var configuration = FirmwareUpgradeConfiguration(
        pipelineDepth: bufferCount - 1,
        reassemblyBufferSize: bufferSize,
        byteAlignment: 4);
    logger.d('Device buffer size: $bufferSize, buffer count: $bufferCount');
    await sendFirmwareData(
        deviceId, firmwareData, sha256Hash, configuration, mtu);
    await confirmUpdate(deviceId, sha256Hash);
    await rebootDevice(deviceId);
  }

  Future<void> sendFirmwareData(
    String deviceId,
    Uint8List firmwareData,
    Uint8List sha256Hash,
    FirmwareUpgradeConfiguration configuration,
    int mtu,
  ) async {
    updateStatus(FirmwareUpdateStatus.uploading);

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
      Uint8List header = SmpHeader(
        version: 0,
        op: 2,
        flags: 0,
        dataLen: payload.length,
        group: 1,
        seq: seq,
        cmdId: 1,
      ).toBytes();
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
        lastAcknowledgedOffset / (firmwareData.length - chunkSize),
      );
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
        _acknowledgmentCompleter = Completer<void>();
        chunkAcknowledged = false;
        await UniversalBle.writeValue(
          deviceId,
          smpServiceUuid,
          smpCharacteristic,
          packet,
          BleOutputProperty.withoutResponse,
        );
        await _acknowledgmentCompleter?.future;
        logger.d(
          "Chunk $seq at offset $offset sent successfully after $attempt attempts",
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

  Future<List<int>> getBufferSize(String deviceId) async {
    var bufferRequestHeader = SmpHeader(
      version: 0,
      op: 0,
      flags: 0,
      dataLen: 0,
      group: 0,
      seq: 0,
      cmdId: 6,
    ).toBytes();

    _responseCompleter = Completer<List<int>>();
    sendPacket(deviceId, bufferRequestHeader);
    print("after send");
    return await _responseCompleter!.future;
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
    var header = SmpHeader(
      version: 0,
      op: 2,
      flags: 0,
      dataLen: confirmPayload.length,
      group: 1,
      seq: 0,
      cmdId: 0,
    ).toBytes();
    Uint8List packet = Uint8List(header.length + confirmPayload.length);

    packet.setAll(0, header);
    packet.setAll(header.length, confirmPayload);

    await sendPacket(deviceId, packet);
  }

  Future<void> rebootDevice(String deviceId) async {
    updateStatus(FirmwareUpdateStatus.rebooting);
    logger.d("Device rebooting...");
    final resetPacket = SmpHeader(
      version: 0,
      op: 2,
      flags: 0,
      dataLen: 0,
      group: 0,
      seq: 0,
      cmdId: 5,
    ).toBytes();
    await sendPacket(deviceId, resetPacket);
  }

  void setupListener(deviceId) {
    logger.d("Setup listener");
    UniversalBle.onValueChange = (
      String receivedDeviceId,
      String characteristicUuid,
      Uint8List value,
    ) {
      print("got notification");
      int smpHeaderLength = 8;
      Uint8List smpHeaderBytes = value.sublist(0, smpHeaderLength);
      SmpHeader smpHeader = SmpHeader.fromBytes(smpHeaderBytes);
      // Remove the header
      Uint8List cborData = value.sublist(smpHeaderLength);
      try {
        final decoded = cbor.decode(cborData);
        logger.d('Received notification');
        logger.d("  Raw value: $value");
        logger.d("  SMP Header: ${smpHeader.toString()}");
        logger.d("  Decoded value: $decoded");
        if (decoded is CborMap) {
          // Image upload response
          if (smpHeader.op == 3 &&
              smpHeader.group == 1 &&
              smpHeader.cmdId == 1) {
            // Access the value for the key 'off'
            var offValue = decoded[CborString('off')];
            if (offValue is CborSmallInt) {
              // Convert CborSmallInt to Dart int
              lastAcknowledgedOffset = offValue.value;
              _acknowledgmentCompleter?.complete();
            } else {
              logger.d('Decoded data is not a CborSmallInt');
            }
          }
          // Buffer Size response
          else if (smpHeader.op == 1 &&
              smpHeader.group == 0 &&
              smpHeader.cmdId == 6) {
            _acknowledgmentCompleter?.complete();
            var bufferSizeValue = decoded[CborString('buf_size')];
            var bufferCountValue = decoded[CborString('buf_count')];
            if (bufferSizeValue is CborSmallInt &&
                bufferCountValue is CborSmallInt) {
              _responseCompleter
                  ?.complete([bufferSizeValue.value, bufferCountValue.value]);
            }
          }
          // System reset response
          else if (smpHeader.op == 3 &&
              smpHeader.group == 0 &&
              smpHeader.cmdId == 5) {
            _acknowledgmentCompleter?.complete();
          }
          // State of image response
          else if (smpHeader.op == 3 &&
              smpHeader.group == 1 &&
              smpHeader.cmdId == 0) {
            _acknowledgmentCompleter?.complete();
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

class SmpHeader {
  final int version;
  final int op;
  final int flags;
  final int dataLen;
  final int group;
  final int seq;
  final int cmdId;

  SmpHeader({
    required this.version,
    required this.op,
    required this.flags,
    required this.dataLen,
    required this.group,
    required this.seq,
    required this.cmdId,
  });

  factory SmpHeader.fromBytes(Uint8List bytes) {
    if (bytes.length != 8) {
      throw Exception(
          'Invalid header length. Expected 8 bytes, got ${bytes.length}');
    }

    final firstByte = bytes[0];
    final version = (firstByte >> 3) & 0x03;
    final op = firstByte & 0x07;
    final flags = bytes[1];
    final dataLen = (bytes[2] << 8) | bytes[3];
    final group = (bytes[4] << 8) | bytes[5];
    final seq = bytes[6];
    final cmdId = bytes[7];

    return SmpHeader(
      version: version,
      op: op,
      flags: flags,
      dataLen: dataLen,
      group: group,
      seq: seq,
      cmdId: cmdId,
    );
  }

  Uint8List toBytes() {
    // First Byte: 7 6 5     4 3      2 1 0
    //             Reserved  Version  Op
    int firstByte = ((version & 0x3) << 3) | (op & 0x7);
    return Uint8List.fromList([
      firstByte,
      flags,
      (dataLen >> 8) & 0xFF, // Data Length (high byte)
      dataLen & 0xFF, // Data Length (low byte)
      (group >> 8) & 0xFF, // Group ID (high byte)
      group & 0xFF, // Group ID (low byte)
      seq & 0xFF, // Sequence number
      cmdId & 0xFF, // Command ID
    ]);
  }

  @override
  String toString() {
    return 'SmpHeader(version: $version, op: $op, flags: $flags, dataLen: $dataLen, group: $group, seq: $seq, cmdId: $cmdId)';
  }
}

class FirmwareUpgradeConfiguration {
  /// Estimated time required for swapping images, in seconds.
  final double estimatedSwapTime;

  /// If enabled, sends an Erase App Settings Command before test/confirm/reset.
  final bool eraseAppSettings;

  /// Enables SMP Pipelining when >1 (multiple packets sent before awaiting response).
  final int pipelineDepth;

  /// Predicts offset jumps when pipelining is enabled.
  final int byteAlignment;

  /// Used instead of MTU for larger packet sizes (max 65535).
  final int reassemblyBufferSize;

  /// Returns true if SMP Pipelining is enabled (pipelineDepth > 1).
  bool get pipeliningEnabled => pipelineDepth > 1;

  FirmwareUpgradeConfiguration({
    this.estimatedSwapTime = 0.0,
    this.eraseAppSettings = false,
    this.pipelineDepth = 1,
    this.byteAlignment = 0,
    this.reassemblyBufferSize = 0,
  }) : assert(
            reassemblyBufferSize <= 65535, 'Cannot exceed UInt16.max (65535)');
}
